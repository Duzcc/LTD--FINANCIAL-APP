import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/core/widgets/entry_tile.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';

enum LedgerSort { newest, oldest, amountDesc, amountAsc }

const _sortLabels = {
  LedgerSort.newest: 'Mới nhất',
  LedgerSort.oldest: 'Cũ nhất',
  LedgerSort.amountDesc: 'Số tiền giảm dần',
  LedgerSort.amountAsc: 'Số tiền tăng dần',
};

/// Sổ giao dịch: tìm kiếm, lọc theo tháng/khoảng ngày, loại, ví, danh mục,
/// đối tượng và sắp xếp theo thời gian hoặc số tiền.
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
  LedgerSort sort = LedgerSort.newest;
  DateTimeRange? range;
  bool showFilters = false;

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
    if (walletId.isNotEmpty &&
        !p.wallets.any((w) => w.id == walletId && w.currency == p.currency)) {
      walletId = '';
    }
    if (categoryId.isNotEmpty && p.category(categoryId) == null) {
      categoryId = '';
    }
    if (personId.isNotEmpty && p.personName(personId).isEmpty) personId = '';
    final q = query.trim().toLowerCase();
    final entries = (range == null
            ? p.inMonth(month, unit: p.currency)
            : p.between(DateUtilsDate.day(range!.start),
                DateUtilsDate.day(range!.end).add(const Duration(days: 1)),
                unit: p.currency))
        .where((e) =>
            (walletId.isEmpty ||
                e.walletId == walletId ||
                e.destinationId == walletId) &&
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
      ..sort((a, b) => switch (sort) {
            LedgerSort.newest => b.date.compareTo(a.date),
            LedgerSort.oldest => a.date.compareTo(b.date),
            LedgerSort.amountDesc => b.amount.compareTo(a.amount),
            LedgerSort.amountAsc => a.amount.compareTo(b.amount),
          });
    final income = entries
        .where((e) => e.kind.isIncome && !e.excluded)
        .fold(0.0, (s, e) => s + e.amount);
    final expense = entries
        .where((e) => e.kind.isExpense && !e.excluded)
        .fold(0.0, (s, e) => s + e.amount);
    final byDate = sort == LedgerSort.newest || sort == LedgerSort.oldest;
    final rows = <Widget>[];
    DateTime? lastDay;
    for (final e in entries) {
      final day = DateUtilsDate.day(e.date);
      if (byDate && day != lastDay) {
        lastDay = day;
        final dayEntries =
            entries.where((x) => DateUtilsDate.day(x.date) == day);
        final net = dayEntries.fold(
            0.0,
            (s, x) =>
                s +
                (x.excluded
                    ? 0
                    : x.kind.isIncome
                        ? x.amount
                        : x.kind.isExpense
                            ? -x.amount
                            : 0));
        rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(children: [
              Expanded(
                  child: Text(_weekday(day),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(money(net, p.currency),
                  style: TextStyle(
                      fontSize: 12,
                      color: net >= 0
                          ? AppColors.primaryGreen
                          : AppColors.accentRed)),
            ])));
      }
      rows.add(EntryTile(e));
    }
    return FinancePage(
        title: 'Sổ giao dịch',
        actions: [
          PopupMenuButton<LedgerSort>(
              tooltip: 'Sắp xếp',
              icon: const Icon(Icons.sort),
              initialValue: sort,
              onSelected: (v) => setState(() => sort = v),
              itemBuilder: (_) => [
                    for (final e in _sortLabels.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value))
                  ]),
          IconButton(
              tooltip: 'Thêm giao dịch',
              onPressed: () => openPage(context, const AddTransactionScreen()),
              icon: const Icon(Icons.add))
        ],
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (range == null)
            MonthPicker(
                value: month, onChanged: (v) => setState(() => month = v))
          else
            Row(children: [
              const Icon(Icons.date_range, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      '${dayLabel(range!.start)} – ${dayLabel(range!.end)}',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                  onPressed: () => setState(() => range = null),
                  child: const Text('Theo tháng')),
            ]),
          TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                  hintText: 'Tìm ghi chú, danh mục, đối tượng, số tiền…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      tooltip: 'Bộ lọc',
                      onPressed: () =>
                          setState(() => showFilters = !showFilters),
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
                          label: Text(v.value),
                          selected: type == v.key,
                          onSelected: (_) => setState(() => type = v.key))),
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
                  for (final w
                      in p.wallets.where((w) => w.currency == p.currency))
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
                  const DropdownMenuItem(
                      value: '', child: Text('Tất cả danh mục')),
                  for (final c in p.categories)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.income ? 'thu' : 'chi'})'))
                ],
                onChanged: (v) => setState(() => categoryId = v ?? '')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                key: ValueKey('person-filter-$personId'),
                initialValue: personId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Đối tượng'),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Tất cả đối tượng')),
                  for (final person in p.people)
                    DropdownMenuItem(value: person.id, child: Text(person.name))
                ],
                onChanged: (v) => setState(() => personId = v ?? '')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: const Text('Khoảng thời gian'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: range);
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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${entries.length} giao dịch • ${p.currency}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Sắp xếp: ${_sortLabels[sort]}',
                      style: const TextStyle(fontSize: 12)),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('+${money(income, p.currency)}',
                  style: const TextStyle(color: AppColors.primaryGreen)),
              Text('−${money(expense, p.currency)}',
                  style: const TextStyle(color: AppColors.accentRed)),
            ]),
          ])),
          const SizedBox(height: 8),
          ...rows,
          if (entries.isEmpty)
            EmptyView(
                title: query.isEmpty && activeFilters == 0
                    ? 'Chưa có giao dịch'
                    : 'Không tìm thấy giao dịch',
                subtitle: query.isEmpty && activeFilters == 0
                    ? 'Thêm giao dịch đầu tiên để bắt đầu theo dõi thu chi.'
                    : 'Thử đổi từ khóa, kỳ thời gian hoặc bộ lọc.',
                action: 'Thêm giao dịch',
                onTap: () => openPage(context, const AddTransactionScreen())),
        ]));
  }
}

String _weekday(DateTime d) {
  const names = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
  final today = DateUtilsDate.day(DateTime.now());
  if (d == today) return 'Hôm nay • ${dayLabel(d)}';
  if (d == today.subtract(const Duration(days: 1))) return 'Hôm qua • ${dayLabel(d)}';
  return '${names[d.weekday - 1]} • ${dayLabel(d)}';
}
