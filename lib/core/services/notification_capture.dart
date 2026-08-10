// Full import: the column comparison helpers are extension methods.
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/logic/bank_parser.dart';
import '../../data/logic/domain_logic.dart';
import '../../data/logic/duplicate_detection.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../settings/app_settings.dart';
import '../utils/utils.dart';

/// Reading notifications is an Android-only capability.
bool get supportsNotificationCapture =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Bridges the Android notification listener to the app: drains captured
/// notifications, parses them and files them in the review inbox.
class NotificationCaptureService {
  static const _channel = MethodChannel('everything/notification_capture');

  final AppDatabase db;
  NotificationCaptureService(this.db);

  /// Whether the user has granted notification access in Android settings.
  Future<bool> hasPermission() async {
    if (!supportsNotificationCapture) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system screen where notification access is granted. Android
  /// does not allow this to be granted programmatically.
  Future<void> openSystemSettings() async {
    if (!supportsNotificationCapture) return;
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException {
      // nothing sensible to do — the settings screen simply didn't open
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!supportsNotificationCapture) return;
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
    } on PlatformException {
      // capture stays off
    }
  }

  Future<void> setMutedPackages(List<String> packages) async {
    if (!supportsNotificationCapture) return;
    try {
      await _channel.invokeMethod('setMutedPackages', {'packages': packages});
    } on PlatformException {
      // muting is best-effort
    }
  }

  /// Pulls everything captured since the last call, parses it, and stores the
  /// transaction-looking ones. Returns how many new items were filed.
  Future<int> drainAndFile({
    bool autoConfirmHighConfidence = false,
    bool syncBalanceFromBank = false,
  }) async {
    if (!supportsNotificationCapture) return 0;
    final List<dynamic> raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>('drain') ?? const [];
    } on PlatformException {
      return 0;
    }

    final accounts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false)))
        .get();
    final ownDigits = ownAccountDigits(accounts);

    var filed = 0;
    for (final entry in raw) {
      final map = Map<String, dynamic>.from(entry as Map);
      final id = (map['key'] as String?) ?? newId();

      // The Android side can re-post the same notification; skip duplicates.
      final existing = await (db.select(db.inboxItems)..where((i) => i.id.equals(id)))
          .getSingleOrNull();
      if (existing != null) continue;

      final title = (map['title'] as String?) ?? '';
      final body = (map['body'] as String?) ?? '';
      final package = (map['package'] as String?) ?? '';
      // Read the message, then decide whose account it is actually about
      // before anything is matched or filed.
      final parsed = resolveOwnership(
        parseBankNotification(title: title, body: body, packageName: package),
        ownDigits,
      );

      // Only money movements are worth keeping.
      if (!parsed.isTransaction) continue;

      final matched = matchAccount(parsed, accounts);
      final suggestedCategory = parsed.merchant.isEmpty
          ? null
          : await Repo(db).suggestCategoryFor(parsed.merchant);
      final postedAt = map['postedAt'] as int?;
      final receivedAt = postedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(postedAt)
          : DateTime.now();
      final appLabel = (map['appLabel'] as String?) ?? '';

      // The same purchase is often announced by the bank app, the messaging
      // app showing its SMS, and caller-ID apps reading the same SMS. Fold
      // those extra reports into the one we already have.
      final recent = await _recentItems(receivedAt);
      final original = Dedupe.findDuplicate(parsed, receivedAt, recent);

      if (original != null) {
        await db.into(db.inboxItems).insert(InboxItemsCompanion.insert(
              id: id,
              packageName: package,
              appLabel: Value(appLabel),
              title: Value(title),
              body: Value(body),
              receivedAt: receivedAt,
              amount: Value(parsed.amountCents),
              txType: Value(parsed.type?.index),
              merchant: Value(parsed.merchant),
              accountLast4: Value(parsed.accountLast4),
              bankName: Value(parsed.bankName),
              confidence: Value(parsed.confidence),
              availableBalance: Value(parsed.availableBalanceCents),
              status: Value(InboxStatus.duplicate.index),
              duplicateOfId: Value(original.id),
            ));

        // Note which app also reported it, and upgrade the kept item if this
        // report knows more (e.g. it includes the card digits).
        final label = appLabel.isNotEmpty ? appLabel : package;
        await (db.update(db.inboxItems)..where((i) => i.id.equals(original.id)))
            .write(InboxItemsCompanion(
          alsoSeenFrom: Value(Dedupe.addSource(original.alsoSeenFrom, label)),
          merchant: Value(original.merchant.isEmpty ? parsed.merchant : original.merchant),
          accountLast4: Value(
              original.accountLast4.isEmpty ? parsed.accountLast4 : original.accountLast4),
          bankName:
              Value(original.bankName.isEmpty ? parsed.bankName : original.bankName),
          // A repeat may carry the balance when the first report didn't.
          availableBalance:
              Value(original.availableBalance ?? parsed.availableBalanceCents),
          confidence: Value(
              parsed.confidence > original.confidence ? parsed.confidence : original.confidence),
          matchedAccountId: Value(original.matchedAccountId ?? matched?.id),
        ));
        continue;
      }

      await db.into(db.inboxItems).insert(InboxItemsCompanion.insert(
            id: id,
            packageName: package,
            appLabel: Value(appLabel),
            title: Value(title),
            body: Value(body),
            receivedAt: receivedAt,
            amount: Value(parsed.amountCents),
            txType: Value(parsed.type?.index),
            merchant: Value(parsed.merchant),
            accountLast4: Value(parsed.accountLast4),
            bankName: Value(parsed.bankName),
            confidence: Value(parsed.confidence),
            matchedAccountId: Value(matched?.id),
            suggestedCategoryId: Value(suggestedCategory),
            availableBalance: Value(parsed.availableBalanceCents),
            status: Value(InboxStatus.pending.index),
          ));
      filed++;

      // Auto-filing only ever happens when the user asked for it, we are sure
      // about the parse, the money moved on an account of theirs, we know
      // which one, and nothing that looks like it is already in the ledger.
      if (autoConfirmHighConfidence &&
          matched != null &&
          parsed.ownership != Ownership.someoneElse &&
          parsed.confidence >= 0.85) {
        final stored = await (db.select(db.inboxItems)..where((i) => i.id.equals(id)))
            .getSingle();
        final alreadyThere =
            await findLedgerDuplicate(stored, accountId: matched.id);
        if (alreadyThere == null) {
          await confirmItem(
            stored,
            accountId: matched.id,
            categoryId: suggestedCategory,
            syncBalance: syncBalanceFromBank,
          );
        }
      }
    }

    // Whatever the order the reports arrived in, leave one row per
    // transaction behind.
    await mergeDuplicateReports();
    return filed;
  }

  /// Items captured close enough in time to be reports of the same purchase.
  Future<List<InboxItem>> _recentItems(DateTime around) {
    final from = around.subtract(Dedupe.contentWindow);
    final to = around.add(Dedupe.contentWindow);
    return (db.select(db.inboxItems)
          ..where((i) =>
              i.receivedAt.isBiggerOrEqualValue(from) &
              i.receivedAt.isSmallerOrEqualValue(to))
          ..orderBy([(i) => OrderingTerm.desc(i.receivedAt)]))
        .get();
  }

  /// The last four digits of every account the user has told us about — the
  /// only numbers that mean "this money is mine".
  static Set<String> ownAccountDigits(List<Account> accounts) => {
        for (final account in accounts)
          for (final hint in account.notificationHints.split(','))
            if (RegExp(r'^\d{4}$').hasMatch(hint.trim())) hint.trim(),
      };

  /// Collapses everything still awaiting review down to one row per
  /// transaction.
  ///
  /// The per-notification check during a drain only sees what was already
  /// stored, so a better report arriving second, or the two halves of a
  /// transfer arriving out of order, can still leave two rows behind. This
  /// pass reconciles the whole queue and keeps the most informative report of
  /// each transaction. Returns how many rows it folded away.
  Future<int> mergeDuplicateReports() async {
    final items = await (db.select(db.inboxItems)
          ..where((i) => i.status.equals(InboxStatus.pending.index))
          ..orderBy([(i) => OrderingTerm.asc(i.receivedAt)]))
        .get();
    if (items.length < 2) return 0;

    final accounts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false)))
        .get();
    final ownDigits = ownAccountDigits(accounts);

    // The reports being kept, one per transaction, alongside the reading each
    // came from so later arrivals can be compared against them.
    final keepers = <InboxItem>[];
    final readings = <ParsedNotification>[];
    var folded = 0;

    for (final item in items) {
      final parsed = resolveOwnership(Dedupe.reparse(item), ownDigits);
      var match = -1;
      for (var i = 0; i < keepers.length; i++) {
        final isRepeat = Dedupe.isSameTransaction(
              parsed,
              item.receivedAt,
              keepers[i],
              existingReading: readings[i],
            ) ||
            Dedupe.isMirrorReport(
                parsed, item.receivedAt, keepers[i], readings[i]);
        if (isRepeat) {
          match = i;
          break;
        }
      }

      if (match < 0) {
        keepers.add(item);
        readings.add(parsed);
        continue;
      }

      if (Dedupe.prefers(parsed, readings[match])) {
        keepers[match] = await _fold(keep: item, drop: keepers[match]);
        readings[match] = parsed;
      } else {
        keepers[match] = await _fold(keep: keepers[match], drop: item);
      }
      folded++;
    }
    return folded;
  }

  /// Files [drop] as a repeat of [keep], moving across anything it knew that
  /// [keep] did not, and re-pointing any reports that were folded into [drop]
  /// earlier. Returns [keep] with those merges applied.
  Future<InboxItem> _fold({
    required InboxItem keep,
    required InboxItem drop,
  }) async {
    var sources = Dedupe.addSource(
      keep.alsoSeenFrom,
      drop.appLabel.isNotEmpty ? drop.appLabel : drop.packageName,
    );
    for (final earlier in drop.alsoSeenFrom.split(',')) {
      sources = Dedupe.addSource(sources, earlier);
    }

    final merged = InboxItemsCompanion(
      alsoSeenFrom: Value(sources),
      merchant: Value(keep.merchant.isEmpty ? drop.merchant : keep.merchant),
      accountLast4:
          Value(keep.accountLast4.isEmpty ? drop.accountLast4 : keep.accountLast4),
      bankName: Value(keep.bankName.isEmpty ? drop.bankName : keep.bankName),
      availableBalance: Value(keep.availableBalance ?? drop.availableBalance),
      matchedAccountId: Value(keep.matchedAccountId ?? drop.matchedAccountId),
      suggestedCategoryId:
          Value(keep.suggestedCategoryId ?? drop.suggestedCategoryId),
      confidence:
          Value(keep.confidence >= drop.confidence ? keep.confidence : drop.confidence),
    );

    await (db.update(db.inboxItems)..where((i) => i.id.equals(keep.id)))
        .write(merged);
    await (db.update(db.inboxItems)..where((i) => i.id.equals(drop.id))).write(
      InboxItemsCompanion(
        status: Value(InboxStatus.duplicate.index),
        duplicateOfId: Value(keep.id),
      ),
    );
    await (db.update(db.inboxItems)
          ..where((i) => i.duplicateOfId.equals(drop.id)))
        .write(InboxItemsCompanion(duplicateOfId: Value(keep.id)));

    return keep.copyWithCompanion(merged);
  }

  /// A transaction already saved that this capture probably repeats.
  Future<Transaction?> findLedgerDuplicate(InboxItem item, {String? accountId}) async {
    if (item.amount == null) return null;
    final from = dayKey(item.receivedAt.subtract(const Duration(days: 1)));
    final to = dayKey(item.receivedAt.add(const Duration(days: 1)));
    final nearby = await (db.select(db.transactions)
          ..where((t) =>
              t.day.isBiggerOrEqualValue(from) & t.day.isSmallerOrEqualValue(to)))
        .get();
    return Dedupe.findLedgerDuplicate(
      ParsedNotification(
        amountCents: item.amount,
        type: item.txType != null ? TxType.values[item.txType!] : null,
        accountLast4: item.accountLast4,
      ),
      item.receivedAt,
      nearby,
      accountId: accountId,
    );
  }

  /// Picks the account whose hints match the notification (card last four
  /// digits first, then bank name). Returns null when nothing matches.
  static Account? matchAccount(ParsedNotification parsed, List<Account> accounts) {
    // Money moving on an account that isn't the user's, with no balance of
    // theirs quoted, belongs to nobody here — matching it on the bank's name
    // alone would book somebody else's payment against their account.
    if (parsed.ownership == Ownership.someoneElse &&
        parsed.availableBalanceCents == null) {
      return null;
    }
    if (parsed.matchHints.isEmpty) return null;
    Account? bankMatch;
    for (final account in accounts) {
      final hints = account.notificationHints
          .toLowerCase()
          .split(',')
          .map((h) => h.trim())
          .where((h) => h.isNotEmpty);
      for (final hint in hints) {
        if (parsed.accountLast4.isNotEmpty && hint == parsed.accountLast4) {
          return account; // digits are the strongest signal
        }
        if (parsed.bankName.isNotEmpty && hint == parsed.bankName.toLowerCase()) {
          bankMatch ??= account;
        }
      }
    }
    return bankMatch;
  }

  /// Turns an inbox item into a real transaction.
  /// Applies the balance the bank reported to [accountId], if the message
  /// carried one and the account type makes it meaningful. Returns the
  /// correction applied in cents, or null when nothing was done.
  Future<int?> applyReportedBalance(InboxItem item, String accountId) async {
    // Re-read the message rather than trust the stored figure: anything
    // captured before a parser fix still holds what was read at the time.
    final reported =
        Dedupe.reparse(item).availableBalanceCents ?? item.availableBalance;
    if (reported == null) return null;
    final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
    if (account == null || !balanceSyncSuitable(account)) return null;
    return Repo(db).syncAccountBalance(accountId, reported);
  }

  Future<void> confirmItem(
    InboxItem item, {
    required String accountId,
    String? categoryId,
    int? amountOverride,
    TxType? typeOverride,
    String? descriptionOverride,
    bool syncBalance = false,
  }) async {
    final amount = amountOverride ?? item.amount;
    final type = typeOverride ??
        (item.txType != null ? TxType.values[item.txType!] : TxType.expense);
    if (amount == null || amount <= 0) return;

    final txId = newId();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          txType: type.index,
          amount: amount,
          accountId: accountId,
          categoryId: Value(categoryId),
          merchant: Value(item.merchant),
          description: Value(descriptionOverride ?? item.merchant),
          note: Value('Captured from ${item.appLabel.isEmpty ? item.packageName : item.appLabel}'),
          day: dayKey(item.receivedAt),
          time: Value(
              '${item.receivedAt.hour.toString().padLeft(2, '0')}:${item.receivedAt.minute.toString().padLeft(2, '0')}'),
          createdAt: DateTime.now(),
        ));

    await (db.update(db.inboxItems)..where((i) => i.id.equals(item.id))).write(
      InboxItemsCompanion(
        status: Value(InboxStatus.confirmed.index),
        matchedAccountId: Value(accountId),
        createdTransactionId: Value(txId),
      ),
    );

    // Remember the choice so this merchant categorises itself next time.
    await Repo(db).learnMerchantCategory(item.merchant, categoryId);

    // Reconcile against the bank's figure *after* the transaction exists, so
    // the two agree exactly.
    if (syncBalance) await applyReportedBalance(item, accountId);
  }

  Future<void> ignoreItem(String id) =>
      (db.update(db.inboxItems)..where((i) => i.id.equals(id)))
          .write(InboxItemsCompanion(status: Value(InboxStatus.ignored.index)));

  Future<void> deleteItem(String id) =>
      (db.delete(db.inboxItems)..where((i) => i.id.equals(id))).go();

  Future<void> clearReviewed() =>
      (db.delete(db.inboxItems)
            ..where((i) => i.status.isNotValue(InboxStatus.pending.index)))
          .go();
}

final notificationCaptureProvider = Provider<NotificationCaptureService>(
  (ref) => NotificationCaptureService(ref.watch(dbProvider)),
);

final inboxItemsProvider = StreamProvider<List<InboxItem>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.inboxItems)
        ..orderBy([(i) => OrderingTerm.desc(i.receivedAt)]))
      .watch();
});

final pendingInboxCountProvider = Provider<int>((ref) {
  final items = ref.watch(inboxItemsProvider).valueOrNull ?? const [];
  return items.where((i) => i.status == InboxStatus.pending.index).length;
});

/// Drains the queue whenever the app starts or returns to the foreground.
final captureRefreshProvider = FutureProvider<int>((ref) async {
  final settings = ref.watch(settingsProvider);
  if (!settings.captureEnabled) return 0;
  return ref.read(notificationCaptureProvider).drainAndFile(
        autoConfirmHighConfidence: settings.captureAutoConfirm,
        syncBalanceFromBank: settings.syncBalanceFromBank,
      );
});
