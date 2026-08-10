import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/widgets.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final expense = categories.where((c) => !c.isIncome).toList();
    final income = categories.where((c) => c.isIncome).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s16, Tokens.s4, Tokens.s16, 96),
        children: [
          const SectionHeader('Spending'),
          AppCard(
            padding: const EdgeInsets.all(Tokens.s8),
            child: Column(children: [for (final c in expense) _row(context, ref, c)]),
          ),
          const SectionHeader('Income'),
          AppCard(
            padding: const EdgeInsets.all(Tokens.s8),
            child: Column(children: [for (final c in income) _row(context, ref, c)]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAppSheet(context, const CategoryEditorSheet()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Category'),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Category c) {
    return ListTile(
      leading: IconBadge(icon: appIcon(c.iconCode), color: Color(c.colorValue), size: 40),
      title: Text(c.name),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showAppSheet(context, CategoryEditorSheet(existing: c)),
    );
  }
}

class CategoryEditorSheet extends ConsumerStatefulWidget {
  final Category? existing;
  const CategoryEditorSheet({super.key, this.existing});

  @override
  ConsumerState<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late Color color =
      widget.existing != null ? Color(widget.existing!.colorValue) : itemColors.first;
  late IconData icon =
      widget.existing != null ? appIcon(widget.existing!.iconCode) : Icons.shopping_bag_rounded;
  late bool isIncome = widget.existing?.isIncome ?? false;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.existing == null ? 'New category' : 'Edit category',
      actionLabel: widget.existing == null ? 'Create category' : 'Save changes',
      onAction: _save,
      titleTrailing: widget.existing == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirmDelete(context,
                    'category (transactions keep their data, uncategorised)')) {
                  final db = ref.read(dbProvider);
                  await (db.delete(db.categories)
                        ..where((c) => c.id.equals(widget.existing!.id)))
                      .go();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
      children: [
        TextField(
          controller: name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: Tokens.s12),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Spending')),
            ButtonSegment(value: true, label: Text('Income')),
          ],
          selected: {isIncome},
          onSelectionChanged: (s) => setState(() => isIncome = s.first),
        ),
        const SizedBox(height: Tokens.s16),
        ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
        const SizedBox(height: Tokens.s16),
        IconPickerGrid(selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
      ],
    );
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) return;
    final db = ref.read(dbProvider);
    final companion = CategoriesCompanion(
      name: Value(name.text.trim()),
      iconCode: Value(icon.codePoint),
      colorValue: Value(color.toARGB32()),
      isIncome: Value(isIncome),
    );
    if (widget.existing == null) {
      await db.into(db.categories).insert(companion.copyWith(
          id: Value(newId()),
          sortOrder: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000)));
    } else {
      await (db.update(db.categories)..where((c) => c.id.equals(widget.existing!.id)))
          .write(companion);
    }
    if (mounted) Navigator.pop(context);
  }
}
