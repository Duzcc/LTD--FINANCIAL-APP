import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/utils/dates.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, this.initialCategoryId});
  final String? initialCategoryId;
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  DateTime month = DateTime.now();
  String query = '', walletId = '', personId = '';
  late String categoryId = widget.initialCategoryId ?? '';
  String type = 'all';
  DateTimeRange? range;
  bool showFilters = false;
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  int get activeFilters => [
        walletId.isNotEmpty,
        categoryId.isNotEmpty,
        personId.isNotEmpty,
        type != 'all',
        range != null
      ].where((v) => v).length;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    if (walletId.isNotEmpty && !p.wallets.any((w) => w.id == walletId && w.currency == p.currency)) {
      walletId = '';
    }
    if (categoryId.isNotEmpty && p.category(categoryId) == null) {
      categoryId = '';
    }
    if (personId.isNotEmpty && p.personName(personId).isEmpty) personId = '';
    final q = query.trim().toLowerCase();
    final entries = (range == null
            ? p.inMonth(month, unit: p.currency)
            : p.between(dateOnly(range!.start), dateOnly(range!.end).add(const Duration(days: 1)), unit: p.currency))
        .where((e) =>
            (walletId.isEmpty || e.walletId == walletId || e.destinationId == walletId) &&
            (categoryId.isEmpty || e.categoryId == categoryId) &&
            (personId.isEmpty || e.personId == personId) &&
            (type == 'all' ||
                type == 'debt' && e.kind.isDebt ||
                type == 'expense' && e.kind.isExpense ||
                type == 'income' && e.kind.isIncome ||
                type == e.kind.name) &&
            (q.isEmpty ||
                '${p.category(e.categoryId)?.name ?? ''} ${e.note} ${p.personName(e.personId)} ${e.amount.toStringAsFixed(0)} ${e.kind.label} ${p.findWallet(e.walletId)?.name ?? ''}'
                    .toLowerCase()
                    .contains(q)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final income = entries.where((e) => e.kind.isIncome && !e.excluded).fold(0.0, (s, e) => s + e.amount);
    final expense = entries.where((e) => e.kind.isExpense && !e.excluded).fold(0.0, (s, e) => s + e.amount);
    final dayNet = <DateTime, double>{};
    for (final e in entries) {
      if (e.excluded) continue;
      final signed = e.kind.isIncome
          ? e.amount
          : e.kind.isExpense
              ? -e.amount
              : 0.0;
      dayNet.update(dateOnly(e.date), (v) => v + signed, ifAbsent: () => signed);
    }
    final header = <Widget>[
      if (range == null)
        MonthPicker(value: month, onChanged: (v) => setState(() => month = v))
      else
        Row(children: [
          const Icon(Icons.date_range, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${dayLabel(range!.start)} – ${dayLabel(range!.end)}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => setState(() => range = null), child: const Text('Theo tháng')),
        ]),
      TextField(
          controller: search,
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
              hintText: 'Tìm ghi chú, danh mục, đối tượng, số tiền…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  tooltip: 'Bộ lọc',
                  onPressed: () => setState(() => showFilters = !showFilters),
                  icon: Badge(
                      isLabelVisible: activeFilters > 0,
                      label: Text('$activeFilters'),
                      child: const Icon(Icons.tune))))),
      const SizedBox(height: 12),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final v in {
              'all': 'Tất cả',
              'expense': 'Chi tiêu',
              'income': 'Thu nhập',
              'transfer': 'Chuyển tiền',
              'debt': 'Vay / Nợ'
            }.entries)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(v.value), selected: type == v.key, onSelected: (_) => setState(() => type = v.key))),
          ])),
      if (showFilters || activeFilters > 1) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            key: ValueKey('wallet-filter-$walletId-${p.currency}'),
            initialValue: walletId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ví'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tất cả ví')),
              for (final w in p.wallets.where((w) => w.currency == p.currency))
                DropdownMenuItem(value: w.id, child: Text(w.name))
            ],
            onChanged: (v) => setState(() => walletId = v ?? '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            key: ValueKey('category-filter-$categoryId'),
            initialValue: categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Danh mục'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tất cả danh mục')),
              for (final c in p.categories)
                DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.income ? 'thu' : 'chi'})'))
            ],
            onChanged: (v) => setState(() => categoryId = v ?? '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
            key: ValueKey('person-filter-$personId'),
            initialValue: personId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Đối tượng'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tất cả đối tượng')),
              for (final person in p.people) DropdownMenuItem(value: person.id, child: Text(person.name))
            ],
            onChanged: (v) => setState(() => personId = v ?? '')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              icon: const Icon(Icons.date_range),
              label: const Text('Khoảng thời gian'),
              onPressed: () async {
                final r = await showDateRangePicker(
                    context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: range);
                if (r != null && mounted) setState(() => range = r);
              }),
          if (activeFilters > 0)
            TextButton.icon(
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Xóa bộ lọc'),
                onPressed: () => setState(() {
                      walletId = categoryId = personId = '';
                      type = 'all';
                      range = null;
                    })),
        ]),
      ],
      const SizedBox(height: 12),
      Panel(
          child: Row(children: [
        Expanded(
            child: Text('${entries.length} giao dịch • ${p.currency}',
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('+${money(income, p.currency)}', style: const TextStyle(color: AppColors.primaryGreen)),
          Text('−${money(expense, p.currency)}', style: const TextStyle(color: AppColors.accentRed)),
        ]),
      ])),
      const SizedBox(height: 8),
    ];
    return FinancePage(
        title: 'Sổ giao dịch',
        child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: header.length + (entries.isEmpty ? 1 : entries.length),
            itemBuilder: (context, i) {
              if (i < header.length) return header[i];
              if (entries.isEmpty) {
                return EmptyView(
                    title: query.isEmpty && activeFilters == 0 ? 'Chưa có giao dịch' : 'Không tìm thấy giao dịch',
                    subtitle: query.isEmpty && activeFilters == 0
                        ? 'Thêm giao dịch đầu tiên để bắt đầu theo dõi thu chi.'
                        : 'Thử đổi từ khóa, kỳ thời gian hoặc bộ lọc.',
                    action: 'Thêm giao dịch',
                    onTap: () => openPage(context, const AddTransactionScreen()));
              }
              final index = i - header.length;
              final e = entries[index];
              final day = dateOnly(e.date);
              final startsDay = index == 0 || dateOnly(entries[index - 1].date) != day;
              if (!startsDay) return EntryTile(e, key: ValueKey(e.id));
              return Column(key: ValueKey(e.id), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _DayHeader(day: day, net: dayNet[day] ?? 0, currency: p.currency),
                EntryTile(e),
              ]);
            }));
  }
}

String _weekday(DateTime d) {
  const names = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
  final today = dateOnly(DateTime.now());
  if (d == today) return 'Hôm nay • ${dayLabel(d)}';
  if (d == today.subtract(const Duration(days: 1))) return 'Hôm qua • ${dayLabel(d)}';
  return '${names[d.weekday - 1]} • ${dayLabel(d)}';
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.net, required this.currency});
  final DateTime day;
  final double net;
  final String currency;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(children: [
        Expanded(child: Text(_weekday(day), style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(money(net, currency),
            style: TextStyle(fontSize: 12, color: net >= 0 ? AppColors.primaryGreen : AppColors.accentRed)),
      ]));
}
