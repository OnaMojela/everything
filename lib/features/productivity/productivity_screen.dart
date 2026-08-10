import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../shell/app_shell.dart';
import 'focus_tab.dart';
import 'habit_editor.dart';
import 'habits_tab.dart';
import 'planner_tab.dart';
import 'tasks_tab.dart';

class ProductivityScreen extends ConsumerStatefulWidget {
  const ProductivityScreen({super.key});

  @override
  ConsumerState<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends ConsumerState<ProductivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productivity'),
        actions: shellActions(context),
        bottom: TabBar(
          controller: _tabs,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Habits'),
            Tab(text: 'Tasks'),
            Tab(text: 'Planner'),
            Tab(text: 'Focus'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [HabitsTab(), TasksTab(), PlannerTab(), FocusTab()],
      ),
      floatingActionButton: switch (_tabs.index) {
        0 => FloatingActionButton.extended(
            heroTag: 'fab_prod',
            onPressed: () => showAppSheet(context, const HabitEditorSheet()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Habit'),
          ),
        1 => FloatingActionButton.extended(
            heroTag: 'fab_prod',
            onPressed: () => showAppSheet(context, const TaskEditorSheet()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Task'),
          ),
        _ => null,
      },
    );
  }
}
