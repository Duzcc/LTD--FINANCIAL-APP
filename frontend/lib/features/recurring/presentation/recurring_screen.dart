import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_person_screen.dart';

/// Danh sách giao dịch định kỳ (tiền nhà, lương, gói cước, nạp tiết kiệm…).
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final rules = [...p.recurring]..sort((a, b) => a.upcoming.compareTo(b.upcoming));
    return FinancePage(
        title: 'Giao dịch định kỳ',
        actions: [
          IconButton(
              tooltip: 'Thêm giao dịch định kỳ',
              onPressed: () => openPage(context, const RecurringEditor()),
              icon: const Icon(Icons.add))
        ],
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Ứng dụng tự ghi giao dịch khi đến hạn (mỗi lần mở ứng dụng). Dùng cho tiền nhà, lương, gói cước hoặc tự động nạp ví tiết kiệm.',
              style: TextStyle(height: 1.5)),
          if (p.recurringError != null) ...[
            const SizedBox(height: 12),
            Panel(
                color: const Color(0xFFF7E9E6),
                child: Text(p.recurringError!,
                    style: const TextStyle(color: AppColors.accentRed))),
          ],
          const SizedBox(height: 12),
          for (final r in rules)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                        tileColor: Colors.transparent,
                        leading: RoundIcon(
                            r.kind == EntryKind.transfer
                                ? Icons.savings_outlined
                                : p.category(r.categoryId)?.icon ?? Icons.repeat,
                            color: r.active ? const Color(0xFF8D7564) : AppColors.textGrey),
                        title: Text(r.note.isNotEmpty
                            ? r.note
                            : p.category(r.categoryId)?.name ?? r.kind.label),
                        subtitle: Text(
                            '${r.describe} • ${p.findWallet(r.walletId)?.name ?? ''}${r.kind == EntryKind.transfer ? ' → ${p.findWallet(r.destinationId)?.name ?? ''}' : ''}\n'
                            '${r.active ? 'Lần tới: ${dayLabel(r.upcoming)}' : 'Đã dừng'}'),
                        isThreeLine: true,
                        trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  money(r.amount,
                                      p.findWallet(r.walletId)?.currency ?? 'VND'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: r.kind == EntryKind.transfer
                                          ? AppColors.textPrimary
                                          : r.kind.sign > 0
                                              ? AppColors.primaryGreen
                                              : AppColors.accentRed)),
                            ]),
                        onTap: () => openPage(context, RecurringEditor(rule: r))))),
          if (rules.isEmpty)
            EmptyView(
                title: 'Chưa có giao dịch định kỳ',
                subtitle: 'Ví dụ: tiền nhà ngày 5 hằng tháng, lương ngày 10, nạp tiết kiệm 1 triệu mỗi tháng.',
                icon: Icons.event_repeat,
                action: 'Tạo giao dịch định kỳ',
                onTap: () => openPage(context, const RecurringEditor())),
        ]));
  }
}

class RecurringEditor extends StatefulWidget {
  const RecurringEditor(
      {super.key,
      this.rule,
      this.initialKind = EntryKind.expense,
      this.initialWalletId,
      this.initialDestinationId,
      this.initialAmount,
      this.initialNote});
  final RecurringRule? rule;
  final EntryKind initialKind;
  final String? initialWalletId, initialDestinationId, initialNote;
  final double? initialAmount;
  @override
  State<RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<RecurringEditor> {
  final form = GlobalKey<FormState>();
  late final r = widget.rule;
  late EntryKind kind = r?.kind ?? widget.initialKind;
  late final amount = TextEditingController(
      text: formatAmountInput(r?.amount ?? widget.initialAmount ?? 0));
  late final note = TextEditingController(text: r?.note ?? widget.initialNote ?? '');
  late String? walletId = r?.walletId ?? widget.initialWalletId,
      destinationId = r?.destinationId ?? widget.initialDestinationId,
      categoryId = r?.categoryId,
      personId = r?.personId;
  late RepeatFrequency frequency = r?.frequency ?? RepeatFrequency.monthly;
  late int interval = r?.interval ?? 1;
  late DateTime start = r?.startDate ?? DateUtilsDate.day(DateTime.now());
  late DateTime? end = r?.endDate;
  late bool active = r?.active ?? true;

  @override
  void initState() {
    super.initState();
    final p = context.read<FinanceProvider>();
    if (p.findWallet(walletId) == null) walletId = p.wallets.firstOrNull?.id;
    categoryId ??= p.categories.where((c) => c.income == kind.isIncome).firstOrNull?.id;
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    final changedSchedule = r == null ||
        r!.startDate != start ||
        r!.frequency != frequency ||
        r!.interval != interval;
    try {
      var rule = RecurringRule(
          id: r?.id ?? p.newId(),
          kind: kind,
          amount: parseAmount(amount.text)!,
          walletId: walletId!,
          destinationId: kind == EntryKind.transfer ? destinationId : null,
          categoryId: kind.isIncome || kind.isExpense ? categoryId : null,
          personId: personId,
          note: note.text.trim(),
          frequency: frequency,
          interval: interval,
          startDate: start,
          endDate: end,
          nextDate: r?.nextDate,
          active: active);
      // Sửa lịch của quy tắc đã chạy: chỉ áp dụng cho các lần đến hạn sau hôm nay.
      if (r != null && changedSchedule) {
        rule = rule.copyWith(nextDate: rule.nextAfter(DateTime.now()));
      }
      p.saveRecurring(rule);
      final created = p.runRecurring();
      message(
          context,
          created > 0
              ? 'Đã lưu và tạo $created giao dịch đến hạn.'
              : 'Đã lưu giao dịch định kỳ.');
      Navigator.pop(context);
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final wallet = p.findWallet(walletId);
    return FinancePage(
        title: r == null ? 'Tạo giao dịch định kỳ' : 'Sửa giao dịch định kỳ',
        bottom: FilledButton(
            onPressed: save,
            child: const Padding(padding: EdgeInsets.all(14), child: Text('Lưu'))),
        child: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in [
                  EntryKind.expense,
                  EntryKind.income,
                  EntryKind.transfer,
                  EntryKind.repay,
                  EntryKind.collect
                ])
                  ChoiceChip(
                      label: Text(k == EntryKind.transfer ? 'Chuyển / nạp tiết kiệm' : k.label),
                      selected: kind == k,
                      onSelected: (_) => setState(() {
                            kind = k;
                            final c = p.category(categoryId);
                            if (c == null || c.income != kind.isIncome) {
                              categoryId = p.categories
                                  .where((c) => c.income == kind.isIncome)
                                  .firstOrNull
                                  ?.id;
                            }
                          })),
              ]),
              const SizedBox(height: 16),
              TextFormField(
                  controller: amount,
                  inputFormatters: [AmountInputFormatter()],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Số tiền mỗi lần', suffixText: wallet?.currency ?? 'VND'),
                  validator: (v) {
                    final n = parseAmount(v ?? '');
                    return n == null || n <= 0 ? 'Nhập số tiền lớn hơn 0' : null;
                  }),
              const SizedBox(height: 12),
              TextFormField(
                  controller: note,
                  decoration: const InputDecoration(
                      labelText: 'Tên / ghi chú', hintText: 'Ví dụ: Tiền nhà, Netflix, Lương')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  key: ValueKey('rw-$walletId'),
                  initialValue: walletId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: kind == EntryKind.transfer ? 'Từ ví' : 'Ví'),
                  items: [
                    for (final w in p.wallets)
                      DropdownMenuItem(value: w.id, child: Text('${w.name} (${w.currency})'))
                  ],
                  onChanged: (v) => setState(() {
                        walletId = v;
                        if (destinationId == v) destinationId = null;
                      }),
                  validator: (v) => v == null ? 'Chọn ví' : null),
              if (kind == EntryKind.transfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    key: ValueKey('rd-$destinationId-$walletId'),
                    initialValue: destinationId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Đến ví (ví tiết kiệm)'),
                    items: [
                      for (final w in p.wallets.where(
                          (w) => w.id != walletId && w.currency == wallet?.currency))
                        DropdownMenuItem(value: w.id, child: Text(w.name))
                    ],
                    onChanged: (v) => setState(() => destinationId = v),
                    validator: (v) => v == null ? 'Chọn ví nhận' : null),
              ],
              if (kind.isIncome || kind.isExpense)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    tileColor: Colors.transparent,
                    leading: RoundIcon(p.category(categoryId)?.icon ?? Icons.category_outlined),
                    title: const Text('Danh mục'),
                    subtitle: Text(p.category(categoryId)?.name ?? 'Chọn danh mục'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final c = await openPage<MoneyCategory>(
                          context,
                          SelectCategoryScreen(
                              selectedCategoryId: categoryId, income: kind.isIncome));
                      if (c != null && mounted) setState(() => categoryId = c.id);
                    }),
              if (kind.isDebt)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    tileColor: Colors.transparent,
                    leading: const RoundIcon(Icons.person_outline),
                    title: const Text('Đối tượng'),
                    subtitle: Text(personId == null ? 'Bắt buộc' : p.personName(personId)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final person = await openPage<MoneyPerson>(
                          context, SelectPersonScreen(selectedPerson: personId));
                      if (person != null && mounted) setState(() => personId = person.id);
                    }),
              const SectionTitle('Lịch lặp'),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<RepeatFrequency>(
                        initialValue: frequency,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tần suất'),
                        items: [
                          for (final f in RepeatFrequency.values)
                            DropdownMenuItem(value: f, child: Text(f.label))
                        ],
                        onChanged: (v) => setState(() => frequency = v ?? frequency))),
                const SizedBox(width: 12),
                SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<int>(
                        initialValue: interval,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Mỗi'),
                        items: [
                          for (final n in [1, 2, 3, 4, 6, 12])
                            DropdownMenuItem(value: n, child: Text('$n ${frequency.unit}'))
                        ],
                        onChanged: (v) => setState(() => interval = v ?? 1))),
              ]),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  tileColor: Colors.transparent,
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Bắt đầu từ'),
                  subtitle: Text(dayLabel(start)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null && mounted) setState(() => start = d);
                  }),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  tileColor: Colors.transparent,
                  leading: const Icon(Icons.stop_circle_outlined),
                  title: const Text('Kết thúc'),
                  subtitle: Text(end == null ? 'Không giới hạn' : dayLabel(end!)),
                  trailing: end == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: 'Bỏ ngày kết thúc',
                          onPressed: () => setState(() => end = null),
                          icon: const Icon(Icons.clear)),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: end ?? start,
                        firstDate: start,
                        lastDate: DateTime(2100));
                    if (d != null && mounted) setState(() => end = d);
                  }),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  tileColor: Colors.transparent,
                  title: const Text('Đang hoạt động'),
                  value: active,
                  onChanged: (v) => setState(() => active = v)),
              if (r != null)
                TextButton.icon(
                    icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
                    label: const Text('Xóa giao dịch định kỳ',
                        style: TextStyle(color: AppColors.accentRed)),
                    onPressed: () async {
                      if (await confirmAction(context,
                              title: 'Xóa giao dịch định kỳ?',
                              content: 'Các giao dịch đã được tạo trước đó vẫn được giữ lại.',
                              confirm: 'Xóa',
                              danger: true) &&
                          context.mounted) {
                        p.deleteRecurring(r!.id);
                        Navigator.pop(context);
                      }
                    }),
            ])));
  }
}
