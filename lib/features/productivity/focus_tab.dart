import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

/// A running session, persisted so it survives the app being killed.
/// Everything derives from timestamps — no drifting counters.
class ActiveFocus {
  final String? subjectId;
  final int? goalMinutes; // timer mode
  final bool pomodoro;
  final int workMin;
  final int breakMin;
  final int cycles;
  final DateTime startedAt;
  final DateTime phaseStartedAt;
  final int phaseIndex; // even = work, odd = break
  final int bankedWorkSeconds;

  const ActiveFocus({
    required this.subjectId,
    required this.goalMinutes,
    required this.pomodoro,
    this.workMin = 25,
    this.breakMin = 5,
    this.cycles = 4,
    required this.startedAt,
    required this.phaseStartedAt,
    this.phaseIndex = 0,
    this.bankedWorkSeconds = 0,
  });

  bool get isWorkPhase => phaseIndex.isEven;
  int get phaseSeconds => (isWorkPhase ? workMin : breakMin) * 60;
  int get totalPhases => cycles * 2 - 1; // ends on a work phase

  ActiveFocus copyWith({DateTime? phaseStartedAt, int? phaseIndex, int? bankedWorkSeconds}) =>
      ActiveFocus(
        subjectId: subjectId,
        goalMinutes: goalMinutes,
        pomodoro: pomodoro,
        workMin: workMin,
        breakMin: breakMin,
        cycles: cycles,
        startedAt: startedAt,
        phaseStartedAt: phaseStartedAt ?? this.phaseStartedAt,
        phaseIndex: phaseIndex ?? this.phaseIndex,
        bankedWorkSeconds: bankedWorkSeconds ?? this.bankedWorkSeconds,
      );

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'goalMinutes': goalMinutes,
        'pomodoro': pomodoro,
        'workMin': workMin,
        'breakMin': breakMin,
        'cycles': cycles,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'phaseStartedAt': phaseStartedAt.millisecondsSinceEpoch,
        'phaseIndex': phaseIndex,
        'bankedWorkSeconds': bankedWorkSeconds,
      };

  static ActiveFocus? fromJson(Map<String, Object?> j) {
    final started = j['startedAt'] as int?;
    if (started == null) return null;
    return ActiveFocus(
      subjectId: j['subjectId'] as String?,
      goalMinutes: j['goalMinutes'] as int?,
      pomodoro: (j['pomodoro'] as bool?) ?? false,
      workMin: (j['workMin'] as int?) ?? 25,
      breakMin: (j['breakMin'] as int?) ?? 5,
      cycles: (j['cycles'] as int?) ?? 4,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      phaseStartedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['phaseStartedAt'] as int?) ?? started),
      phaseIndex: (j['phaseIndex'] as int?) ?? 0,
      bankedWorkSeconds: (j['bankedWorkSeconds'] as int?) ?? 0,
    );
  }
}

const _prefsKey = 'active_focus_v1';

class FocusTab extends ConsumerStatefulWidget {
  const FocusTab({super.key});

  @override
  ConsumerState<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends ConsumerState<FocusTab> {
  // setup state
  String? subjectId;
  int? goalMinutes = 25;
  bool pomodoroMode = false;
  (int, int) pomodoroPreset = (25, 5);
  int pomodoroCycles = 4;

  // running state
  ActiveFocus? active;
  Timer? _ticker;
  int _now = 0; // triggers rebuilds

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final restored = ActiveFocus.fromJson(jsonDecode(raw) as Map<String, Object?>);
      if (restored != null) {
        setState(() => active = restored);
        _startTicker();
      }
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (active == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(active!.toJson()));
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _advancePomodoroIfNeeded();
      if (mounted) setState(() => _now++);
    });
  }

  Future<void> _start() async {
    final a = ActiveFocus(
      subjectId: subjectId,
      goalMinutes: pomodoroMode ? null : goalMinutes,
      pomodoro: pomodoroMode,
      workMin: pomodoroPreset.$1,
      breakMin: pomodoroPreset.$2,
      cycles: pomodoroCycles,
      startedAt: DateTime.now(),
      phaseStartedAt: DateTime.now(),
    );
    setState(() => active = a);
    _startTicker();
    await _persist();

    final notifications = ref.read(notificationServiceProvider);
    final subject = _subjectName();
    await notifications.showFocusOngoing(subject ?? 'Focus', a.startedAt);
    if (a.pomodoro) {
      await notifications.schedulePhaseEnd('Break time',
          '${a.workMin} minutes done — take ${a.breakMin}', _phaseEndTime(a));
    } else if (a.goalMinutes != null) {
      await notifications.schedulePhaseEnd('Goal reached 🎉',
          '${a.goalMinutes} minutes of focus complete',
          a.startedAt.add(Duration(minutes: a.goalMinutes!)));
    }
  }

  DateTime _phaseEndTime(ActiveFocus a) =>
      a.phaseStartedAt.add(Duration(seconds: a.phaseSeconds));

  /// Walk forward through any phases that completed while we weren't looking
  /// (app killed / backgrounded). Ends the session if all cycles are done.
  void _advancePomodoroIfNeeded() {
    var a = active;
    if (a == null || !a.pomodoro) return;
    var changed = false;
    while (DateTime.now().difference(a!.phaseStartedAt).inSeconds >= a.phaseSeconds) {
      final banked =
          a.bankedWorkSeconds + (a.isWorkPhase ? a.phaseSeconds : 0);
      if (a.phaseIndex + 1 > a.totalPhases - 1) {
        // Final work phase finished — complete the whole session.
        _finish(save: true, precomputedWork: banked);
        return;
      }
      a = a.copyWith(
        phaseIndex: a.phaseIndex + 1,
        phaseStartedAt: a.phaseStartedAt.add(Duration(seconds: a.phaseSeconds)),
        bankedWorkSeconds: banked,
      );
      changed = true;
    }
    if (changed) {
      setState(() => active = a);
      _persist();
      final notifications = ref.read(notificationServiceProvider);
      final isLast = a.phaseIndex == a.totalPhases - 1;
      notifications.schedulePhaseEnd(
        a.isWorkPhase
            ? (isLast ? 'Pomodoro complete 🎉' : 'Break time')
            : 'Back to work',
        a.isWorkPhase
            ? (isLast ? 'Great session — it has been saved' : 'Take ${a.breakMin} minutes')
            : '${a.workMin} minutes of focus',
        _phaseEndTime(a),
      );
    }
  }

  int _currentWorkSeconds() {
    final a = active;
    if (a == null) return 0;
    if (!a.pomodoro) return DateTime.now().difference(a.startedAt).inSeconds;
    final phaseElapsed = DateTime.now().difference(a.phaseStartedAt).inSeconds;
    return a.bankedWorkSeconds +
        (a.isWorkPhase ? phaseElapsed.clamp(0, a.phaseSeconds) : 0);
  }

  Future<void> _finish({required bool save, int? precomputedWork}) async {
    final a = active;
    if (a == null) return;
    final seconds = precomputedWork ?? _currentWorkSeconds();
    _ticker?.cancel();
    _ticker = null;
    setState(() => active = null);
    await _persist();

    final notifications = ref.read(notificationServiceProvider);
    await notifications.cancelFocusOngoing();
    await notifications.cancelPhaseEnd();

    if (save && seconds >= 60) {
      await ref.read(repoProvider).recordFocusSession(
            subjectId: a.subjectId,
            startedAt: a.startedAt,
            durationSeconds: seconds,
            goalMinutes: a.pomodoro ? a.workMin * a.cycles : a.goalMinutes,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Session saved · ${formatDuration(Duration(seconds: seconds))}')));
      }
    } else if (save && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessions under a minute are not recorded.')));
    }
  }

  String? _subjectName() {
    final subjects = ref.read(focusSubjectsProvider).valueOrNull ?? const [];
    return subjects.where((s) => s.id == (active?.subjectId ?? subjectId)).firstOrNull?.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(focusSubjectsProvider).valueOrNull ?? const [];
    final sessions = ref.watch(focusSessionsProvider).valueOrNull ?? const [];
    final a = active;
    final running = a != null;

    final subject = subjects
        .where((s) => s.id == (running ? a.subjectId : subjectId))
        .firstOrNull;
    final color = subject != null ? Color(subject.colorValue) : theme.colorScheme.primary;

    final todaySeconds = sessions
        .where((s) => dayKey(s.startedAt) == dayKey(today))
        .fold<int>(0, (x, s) => x + s.durationSeconds);

    // ring + clock values
    double progress = 0;
    String clock;
    String caption;
    if (!running) {
      clock = pomodoroMode
          ? '${pomodoroPreset.$1}:00'
          : (goalMinutes != null ? '$goalMinutes:00' : '00:00');
      caption = pomodoroMode
          ? '${pomodoroPreset.$1}/${pomodoroPreset.$2} × $pomodoroCycles'
          : (goalMinutes == null ? 'Open session' : '$goalMinutes min goal');
    } else if (a.pomodoro) {
      final phaseElapsed =
          DateTime.now().difference(a.phaseStartedAt).inSeconds.clamp(0, a.phaseSeconds);
      final remaining = a.phaseSeconds - phaseElapsed;
      progress = phaseElapsed / a.phaseSeconds;
      clock = _fmtClock(remaining);
      final cycle = a.phaseIndex ~/ 2 + 1;
      caption = a.isWorkPhase
          ? 'Focus · round $cycle of ${a.cycles}'
          : 'Break · round $cycle of ${a.cycles}';
    } else {
      final elapsed = DateTime.now().difference(a.startedAt).inSeconds;
      clock = _fmtClock(elapsed);
      progress = a.goalMinutes == null
          ? 0
          : (elapsed / (a.goalMinutes! * 60)).clamp(0.0, 1.0);
      caption = subject?.name ?? 'Focusing';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s8, Tokens.s16, 96),
      children: [
        AppCard(
          padding: const EdgeInsets.all(Tokens.s24),
          child: Column(
            children: [
              ProgressRing(
                progress: progress,
                color: running && a.pomodoro && !a.isWorkPhase
                    ? const Color(0xFF2E9E5B)
                    : color,
                size: 200,
                strokeWidth: 12,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clock,
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
                    ),
                    Text(
                      caption,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Tokens.s24),
              if (!running) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Timer')),
                    ButtonSegment(value: true, label: Text('Pomodoro')),
                  ],
                  selected: {pomodoroMode},
                  onSelectionChanged: (s) => setState(() => pomodoroMode = s.first),
                ),
                const SizedBox(height: Tokens.s16),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: const Text('No subject'),
                        selected: subjectId == null,
                        onSelected: (_) => setState(() => subjectId = null),
                      ),
                      const SizedBox(width: Tokens.s8),
                      for (final s in subjects) ...[
                        ChoiceChip(
                          avatar: Icon(appIcon(s.iconCode),
                              size: 16, color: Color(s.colorValue)),
                          label: Text(s.name),
                          selected: subjectId == s.id,
                          onSelected: (_) => setState(() => subjectId = s.id),
                        ),
                        const SizedBox(width: Tokens.s8),
                      ],
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Subject'),
                        onPressed: () =>
                            showAppSheet(context, const _SubjectEditorSheet()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s12),
                if (!pomodoroMode)
                  Wrap(
                    spacing: Tokens.s8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final g in [15, 25, 45, 60, 90])
                        ChoiceChip(
                          label: Text('$g min'),
                          selected: goalMinutes == g,
                          onSelected: (_) => setState(() => goalMinutes = g),
                        ),
                      ChoiceChip(
                        label: const Text('No goal'),
                        selected: goalMinutes == null,
                        onSelected: (_) => setState(() => goalMinutes = null),
                      ),
                    ],
                  )
                else ...[
                  Wrap(
                    spacing: Tokens.s8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in [(25, 5), (50, 10), (90, 15)])
                        ChoiceChip(
                          label: Text('${p.$1}/${p.$2}'),
                          selected: pomodoroPreset == p,
                          onSelected: (_) => setState(() => pomodoroPreset = p),
                        ),
                    ],
                  ),
                  const SizedBox(height: Tokens.s8),
                  Wrap(
                    spacing: Tokens.s8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final c in [2, 3, 4, 6])
                        ChoiceChip(
                          label: Text('$c rounds'),
                          selected: pomodoroCycles == c,
                          onSelected: (_) => setState(() => pomodoroCycles = c),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Tokens.s20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 52),
                    backgroundColor: color,
                  ),
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(pomodoroMode ? 'Start pomodoro' : 'Start focus'),
                ),
              ] else
                // The two buttons share the row rather than sizing themselves:
                // a fixed 160px minimum on Finish plus Discard's intrinsic
                // width overflowed narrow phones by a few pixels.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52)),
                        onPressed: () => _finish(save: false),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Discard'),
                      ),
                    ),
                    const SizedBox(width: Tokens.s12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52), backgroundColor: color),
                        onPressed: () => _finish(save: true),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Finish'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s12),
        Row(
          children: [
            Expanded(
                child: StatTile(
                    label: 'Today',
                    value: formatDuration(Duration(seconds: todaySeconds)),
                    icon: Icons.today_rounded)),
            const SizedBox(width: Tokens.s12),
            Expanded(
                child: StatTile(
                    label: 'Sessions',
                    value: '${sessions.length}',
                    icon: Icons.history_rounded)),
          ],
        ),
        if (sessions.isNotEmpty) ...[
          const SectionHeader('Recent sessions'),
          AppCard(
            padding: const EdgeInsets.all(Tokens.s12),
            child: Column(
              children: [
                for (final s in sessions.take(8))
                  Builder(builder: (context) {
                    final subj =
                        subjects.where((x) => x.id == s.subjectId).firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          IconBadge(
                            icon: subj != null
                                ? appIcon(subj.iconCode)
                                : Icons.center_focus_strong_rounded,
                            color: subj != null
                                ? Color(subj.colorValue)
                                : theme.colorScheme.primary,
                            size: 36,
                          ),
                          const SizedBox(width: Tokens.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(subj?.name ?? 'Focus session',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                Text(formatDay(s.startedAt),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Text(formatDuration(Duration(seconds: s.durationSeconds)),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _fmtClock(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _SubjectEditorSheet extends ConsumerStatefulWidget {
  const _SubjectEditorSheet();

  @override
  ConsumerState<_SubjectEditorSheet> createState() => _SubjectEditorSheetState();
}

class _SubjectEditorSheetState extends ConsumerState<_SubjectEditorSheet> {
  final name = TextEditingController();
  Color color = itemColors.first;
  IconData icon = Icons.school_rounded;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'New subject',
      actionLabel: 'Create',
      onAction: () async {
        if (name.text.trim().isEmpty) return;
        final db = ref.read(dbProvider);
        await db.into(db.focusSubjects).insert(FocusSubjectsCompanion.insert(
              id: newId(),
              name: name.text.trim(),
              colorValue: color.toARGB32(),
              iconCode: icon.codePoint,
            ));
        if (context.mounted) Navigator.pop(context);
      },
      children: [
        TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name (Maths, Reading, Deep work…)'),
        ),
        const SizedBox(height: Tokens.s16),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s16),
        IconPickerGrid(selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
      ],
    );
  }
}
