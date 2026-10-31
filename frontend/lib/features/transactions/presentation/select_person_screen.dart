import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class SelectPersonScreen extends StatefulWidget {
  const SelectPersonScreen(
      {super.key, this.selectedPerson, this.manage = false});
  final String? selectedPerson;
  final bool manage;
  @override
  State<SelectPersonScreen> createState() => _SelectPersonScreenState();
}

class _SelectPersonScreenState extends State<SelectPersonScreen> {
  String query = '';
  Future<void> edit([MoneyPerson? person]) async {
    final name = await editText(
        context, person == null ? 'Đối tượng mới' : 'Tên đối tượng',
        initial: person?.name ?? '');
    if (name == null || !mounted) return;
    final group = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chọn nhóm đối tượng',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              for (final g in [
                'Cá nhân',
                'Bạn bè & Đồng nghiệp',
                'Cửa hàng & Dịch vụ'
              ])
                ListTile(title: Text(g), onTap: () => Navigator.pop(ctx, g)),
            ])));
    if (group == null || !mounted) return;
    final p = context.read<FinanceProvider>();
    try {
      p.savePerson(MoneyPerson(person?.id ?? p.newId(), name, group));
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final items = p.people
        .where((v) => v.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return FinancePage(
        title: widget.manage ? 'Quản lý đối tượng' : 'Chọn đối tượng',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                  hintText: 'Tìm tên người hoặc cửa hàng',
                  prefixIcon: Icon(Icons.search))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Đối tượng mới')),
          for (final group in items.map((p) => p.group).toSet()) ...[
            SectionTitle(group),
            for (final person in items.where((v) => v.group == group))
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                      leading: RoundIcon(group == 'Cửa hàng & Dịch vụ'
                          ? Icons.storefront_outlined
                          : Icons.person_outline),
                      title: Text(person.name),
                      onTap: () => widget.manage
                          ? edit(person)
                          : Navigator.pop(context, person),
                      trailing: widget.manage
                          ? PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  edit(person);
                                  return;
                                }
                                if (await confirmDelete(
                                        context, 'Xóa ${person.name}?') &&
                                    context.mounted) {
                                  try {
                                    p.deletePerson(person.id);
                                  } catch (e) {
                                    if (context.mounted) message(context, e);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Chỉnh sửa')),
                                    PopupMenuItem(
                                        value: 'delete', child: Text('Xóa'))
                                  ])
                          : person.id == widget.selectedPerson
                              ? const Icon(Icons.check,
                                  color: AppColors.primaryGreen)
                              : null)),
          ],
          if (items.isEmpty)
            const EmptyView(
                title: 'Chưa có đối tượng phù hợp',
                subtitle: 'Thêm người hoặc cửa hàng để gắn vào giao dịch.'),
        ]));
  }
}
