import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class SelectCategoryScreen extends StatefulWidget {
  const SelectCategoryScreen(
      {super.key,
      this.selectedCategoryId,
      this.income = false,
      this.manage = false});
  final String? selectedCategoryId;
  final bool income, manage;
  @override
  State<SelectCategoryScreen> createState() => _SelectCategoryScreenState();
}

class _SelectCategoryScreenState extends State<SelectCategoryScreen> {
  String query = '';
  late bool income = widget.income;
  Future<void> edit([MoneyCategory? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    var symbol = c?.symbol ?? 13;
    final key = GlobalKey<FormState>();
    final result = await showDialog<(String, int)>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                    title: Text(c == null
                        ? (income ? 'Danh mục thu mới' : 'Danh mục chi mới')
                        : 'Sửa danh mục'),
                    content: SizedBox(
                        width: 320,
                        child: Form(
                            key: key,
                            child: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  TextFormField(
                                      controller: name,
                                      autofocus: c == null,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      decoration: const InputDecoration(
                                          labelText: 'Tên danh mục'),
                                      validator: (v) => (v ?? '').trim().isEmpty
                                          ? 'Vui lòng nhập tên danh mục'
                                          : null),
                                  const SizedBox(height: 16),
                                  const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('Biểu tượng')),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (var i = 0;
                                        i < MoneyCategory.icons.length;
                                        i++)
                                      InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              setDialog(() => symbol = i),
                                          child: CircleAvatar(
                                              radius: 20,
                                              backgroundColor: symbol == i
                                                  ? const Color(0xFFD9BEA9)
                                                  : AppColors.backgroundBeige,
                                              child: Icon(MoneyCategory.icons[i],
                                                  size: 20,
                                                  color:
                                                      const Color(0xFF8D7564)))),
                                  ]),
                                ])))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy')),
                      FilledButton(
                          onPressed: () {
                            if (key.currentState!.validate()) {
                              Navigator.pop(ctx, (name.text.trim(), symbol));
                            }
                          },
                          child: const Text('Lưu')),
                    ])));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    if (result == null || !mounted) return;
    final p = context.read<FinanceProvider>();
    try {
      p.saveCategory(
          MoneyCategory(c?.id ?? p.newId(), result.$1, income, result.$2));
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final items = p.categories
        .where((c) =>
            c.income == income &&
            c.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return FinancePage(
        title: widget.manage ? 'Quản lý danh mục' : 'Chọn danh mục',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.manage) ...[
            SegmentedButton<bool>(segments: const [
              ButtonSegment(value: false, label: Text('Chi tiêu')),
              ButtonSegment(value: true, label: Text('Thu nhập'))
            ], selected: {
              income
            }, onSelectionChanged: (v) => setState(() => income = v.first)),
            const SizedBox(height: 16)
          ],
          TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                  hintText: 'Tìm danh mục', prefixIcon: Icon(Icons.search))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Danh mục mới')),
          const SizedBox(height: 12),
          for (final c in items)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                    leading: RoundIcon(c.icon),
                    title: Text(c.name),
                    subtitle: widget.manage
                        ? Text(
                            '${p.entries.where((e) => e.categoryId == c.id).length} giao dịch',
                            style: const TextStyle(fontSize: 12))
                        : null,
                    onTap: () =>
                        widget.manage ? edit(c) : Navigator.pop(context, c),
                    trailing: widget.manage
                        ? PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                edit(c);
                                return;
                              }
                              if (await confirmDelete(
                                      context, 'Xóa ${c.name}?') &&
                                  context.mounted) {
                                try {
                                  p.deleteCategory(c.id);
                                } catch (e) {
                                  if (context.mounted) message(context, e);
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Chỉnh sửa')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Xóa'))
                                ])
                        : c.id == widget.selectedCategoryId
                            ? const Icon(Icons.check,
                                color: AppColors.primaryGreen)
                            : const Icon(Icons.chevron_right))),
          if (items.isEmpty)
            const EmptyView(
                title: 'Không tìm thấy danh mục',
                subtitle: 'Thử tên khác hoặc thêm danh mục mới.'),
        ]));
  }
}
