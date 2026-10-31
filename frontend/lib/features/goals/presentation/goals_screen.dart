import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';

/// Ngân sách (màn hình Mục tiêu): mục tiêu tổng của tháng và mục tiêu theo danh mục.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool income = false;

  Future<void> editOverall(FinanceProvider p, MoneyBudget? current) async {
    final text = await editText(
        context, income ? 'Mục tiêu thu nhập tháng' : 'Mục tiêu chi tiêu tháng',
        initial: current == null ? '' : formatAmountInput(current.amount),
        numeric: true);
    if (text == null || !mounted) return;
    final amount = parseAmount(text);
    if (amount == null || amount <= 0) {
      message(context, 'Nhập số tiền mục tiêu lớn hơn 0.');
      return;
    }
    try {
      p.saveBudget(MoneyBudget(
          id: current?.id ?? p.newId(),
          categoryId: null,
          month: month,
          amount: amount,
          currency: p.currency,
          income: income));
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final now = DateTime.now();
    final budgets = p.budgets
        .where((b) =>
            b.categoryId != null &&
            b.month.year == month.year &&
            b.month.month == month.month &&
            b.currency == p.currency &&
            p.budgetIncome(b) == income)
        .toList();
    final overall = p.overallBudget(month, income: income);
    final actual = p.total(month, income: income);
    final categoryTarget = budgets.fold(0.0, (s, b) => s + b.amount);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == now.year && month.month == now.month;
    final daysLeft = isCurrent ? days - now.day + 1 : 0;
    final prev = DateTime(month.year, month.month - 1);
    final prevHas = p.budgets.any((b) =>
        b.month.year == prev.year &&
        b.month.month == prev.month &&
        b.currency == p.currency);
    final target = overall?.amount ?? 0;
    final color = budgetColor(actual, target, income: income);
    return FinancePage(
        title: income ? 'Mục tiêu thu nhập' : 'Mục tiêu chi tiêu',
        actions: [
          IconButton(
              tooltip: 'Cài đặt danh mục',
              onPressed: () => openPage(
                  context, SelectCategoryScreen(manage: true, income: income)),
              icon: const Icon(Icons.tune))
        ],
        child: ListView(padding: const EdgeInsets.all(16), children: [
          MonthPicker(
              value: month, onChanged: (v) => setState(() => month = v)),
          Text(
              '${dayLabel(month)} – ${dayLabel(DateTime(month.year, month.month + 1, 0))}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: false, label: Text('Chi tiêu')),
            ButtonSegment(value: true, label: Text('Thu nhập'))
          ], selected: {
            income
          }, onSelectionChanged: (v) => setState(() => income = v.first)),
          const SizedBox(height: 16),
          Panel(
              color: const Color(0xFFEDE3DA),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              income ? 'MỤC TIÊU THU THÁNG NÀY' : 'MỤC TIÊU CHI THÁNG NÀY',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700))),
                      IconButton(
                          tooltip: 'Sửa mục tiêu tháng',
                          onPressed: () => editOverall(p, overall),
                          icon: const Icon(Icons.edit_outlined, size: 20)),
                      if (overall != null)
                        IconButton(
                            tooltip: 'Xóa mục tiêu tháng',
                            onPressed: () async {
                              if (await confirmDelete(
                                  context, 'Xóa mục tiêu tháng?')) {
                                p.deleteBudget(overall.id);
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 20)),
                    ]),
                    Text(overall == null ? 'Chưa đặt' : money(target, p.currency),
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (overall != null) ...[
                      LinearProgressIndicator(
                          value: (actual / target).clamp(0, 1),
                          minHeight: 8,
                          color: color,
                          backgroundColor: Colors.white,
                          borderRadius: BorderRadius.circular(8)),
                      const SizedBox(height: 8),
                    ],
                    Text(
                        '${income ? 'Đã thu' : 'Đã chi'}: ${money(actual, p.currency)}'
                        '${overall == null ? '' : income ? (actual >= target ? ' • đã đạt mục tiêu' : ' • còn thiếu ${money(target - actual, p.currency)}') : (actual > target ? ' • vượt ${money(actual - target, p.currency)}' : ' • còn lại ${money(target - actual, p.currency)}')}',
                        style: TextStyle(
                            color: overall == null ? null : color,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (overall == null)
                      const Text(
                          'Chạm biểu tượng bút chì để đặt mục tiêu cho cả tháng.',
                          style: TextStyle(fontSize: 12))
                    else if (!income && isCurrent && target > actual)
                      Text(
                          'Bạn có thể chi trung bình ${money((target - actual) / daysLeft, p.currency)}/ngày trong $daysLeft ngày còn lại.',
                          style: const TextStyle(fontSize: 12))
                    else
                      Text(
                          'Trung bình mục tiêu: ${money(target / days, p.currency)}/ngày',
                          style: const TextStyle(fontSize: 12)),
                    if (overall != null && categoryTarget > target) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: AppColors.accentYellow),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                'Tổng mục tiêu các danh mục (${money(categoryTarget, p.currency)}) lớn hơn mục tiêu tháng. Hãy cân đối lại.',
                                style: const TextStyle(fontSize: 12))),
                      ]),
                    ],
                  ])),
          SectionTitle('Theo danh mục',
              action: 'Thêm mới',
              onTap: () => openPage(
                  context, BudgetEditor(month: month, income: income))),
          const Text('Chạm vào từng danh mục để chỉnh mục tiêu riêng.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          for (final b in budgets) _BudgetTile(budget: b, month: month, income: income),
          if (budgets.isEmpty)
            EmptyView(
                title: 'Chưa có mục tiêu theo danh mục',
                subtitle:
                    'Chọn danh mục và ví. Tiến độ tự cập nhật khi bạn ghi giao dịch.',
                icon: Icons.track_changes,
                action: 'Tạo mục tiêu',
                onTap: () => openPage(
                    context, BudgetEditor(month: month, income: income))),
          if (budgets.isEmpty && overall == null && prevHas)
            Center(
                child: TextButton.icon(
                    onPressed: () {
                      final n = p.copyBudgets(prev, month);
                      message(
                          context,
                          n == 0
                              ? 'Không có mục tiêu nào để sao chép.'
                              : 'Đã sao chép $n mục tiêu từ tháng trước.');
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Sao chép mục tiêu tháng trước'))),
          const SizedBox(height: 16),
          const Wrap(spacing: 14, runSpacing: 6, children: [
            _Legend(AppColors.onPlan, 'Đúng kế hoạch'),
            _Legend(AppColors.remaining, 'Sắp chạm hạn mức (≥ 80%)'),
            _Legend(AppColors.overPlan, 'Vượt kế hoạch'),
          ]),
        ]));
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile(
      {required this.budget, required this.month, required this.income});
  final MoneyBudget budget;
  final DateTime month;
  final bool income;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final b = budget;
    final c = p.category(b.categoryId);
    final used = p.used(b);
    final color = budgetColor(used, b.amount, income: income);
    void edit() => openPage(
        context, BudgetEditor(month: month, income: income, budget: b));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: edit,
            child: Panel(
                child: Column(children: [
              Row(children: [
                RoundIcon(c?.icon ?? Icons.category_outlined),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(c?.name ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          b.walletId == null
                              ? 'Tất cả ví ${b.currency}'
                              : p.findWallet(b.walletId)?.name ?? '',
                          style: const TextStyle(fontSize: 12))
                    ])),
                Text(money(b.amount, b.currency),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                PopupMenuButton<String>(
                    tooltip: 'Tùy chọn',
                    onSelected: (v) async {
                      if (v == 'edit') {
                        edit();
                      } else if (await confirmDelete(
                              context, 'Xóa mục tiêu ${c?.name ?? ''}?') &&
                          context.mounted) {
                        p.deleteBudget(b.id);
                      }
                    },
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                          PopupMenuItem(value: 'delete', child: Text('Xóa')),
                        ]),
              ]),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: (used / b.amount).clamp(0, 1),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8),
                  color: color,
                  backgroundColor: AppColors.backgroundBeige),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Text(
                        '${income ? 'Đã thu' : 'Đã chi'} ${money(used, b.currency)}',
                        style: const TextStyle(fontSize: 12))),
                Text(
                    income
                        ? (used >= b.amount
                            ? 'Đã đạt mục tiêu'
                            : 'Còn thiếu ${money(b.amount - used, b.currency)}')
                        : (used > b.amount
                            ? 'Vượt ${money(used - b.amount, b.currency)}'
                            : 'Còn lại ${money(b.amount - used, b.currency)}'),
                    style: TextStyle(fontSize: 12, color: color)),
              ]),
            ]))));
  }
}

class BudgetEditor extends StatefulWidget {
  const BudgetEditor(
      {super.key, required this.month, required this.income, this.budget});
  final DateTime month;
  final bool income;
  final MoneyBudget? budget;
  @override
  State<BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<BudgetEditor> {
  final form = GlobalKey<FormState>();
  late final amount =
      TextEditingController(text: formatAmountInput(widget.budget?.amount ?? 0));
  late String? categoryId = widget.budget?.categoryId;
  late String walletId = widget.budget?.walletId ?? '';
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final unit = widget.budget?.currency ?? p.currency;
    final m = widget.budget?.month ?? widget.month;
    final used = categoryId == null
        ? 0.0
        : p.total(m,
            income: widget.income,
            categoryId: categoryId,
            walletId: walletId.isEmpty ? null : walletId,
            unit: unit);
    return FinancePage(
        title: widget.budget == null ? 'Tạo mục tiêu' : 'Chỉnh sửa mục tiêu',
        child: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                  'Tháng ${m.month}/${m.year} • ${widget.income ? 'Thu nhập' : 'Chi tiêu'} • $unit'),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Danh mục'),
                  items: [
                    for (final c
                        in p.categories.where((c) => c.income == widget.income))
                      DropdownMenuItem(value: c.id, child: Text(c.name))
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                  validator: (v) => v == null ? 'Chọn danh mục' : null),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                  initialValue: walletId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Áp dụng cho ví'),
                  items: [
                    DropdownMenuItem(value: '', child: Text('Tất cả ví $unit')),
                    for (final w in p.wallets.where((w) => w.currency == unit))
                      DropdownMenuItem(value: w.id, child: Text(w.name))
                  ],
                  onChanged: (v) => setState(() => walletId = v ?? '')),
              const SizedBox(height: 16),
              TextFormField(
                  controller: amount,
                  inputFormatters: [AmountInputFormatter()],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Số tiền mục tiêu', suffixText: unit),
                  validator: (v) {
                    final n = parseAmount(v ?? '');
                    return n == null || !n.isFinite || n <= 0
                        ? 'Nhập số tiền lớn hơn 0'
                        : null;
                  }),
              if (categoryId != null) ...[
                const SizedBox(height: 8),
                Text(
                    '${widget.income ? 'Đã thu' : 'Đã chi'} trong tháng: ${money(used, unit)}',
                    style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    try {
                      p.saveBudget(MoneyBudget(
                          id: widget.budget?.id ?? p.newId(),
                          categoryId: categoryId!,
                          month: m,
                          amount: parseAmount(amount.text)!,
                          walletId: walletId.isEmpty ? null : walletId,
                          currency: unit,
                          income: widget.income));
                      Navigator.pop(context);
                    } catch (e) {
                      message(context, e);
                    }
                  },
                  child: const Text('Lưu mục tiêu')),
              if (widget.budget != null)
                TextButton(
                    onPressed: () async {
                      if (await confirmDelete(context, 'Xóa mục tiêu?') &&
                          context.mounted) {
                        p.deleteBudget(widget.budget!.id);
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Xóa mục tiêu')),
            ])));
  }
}
