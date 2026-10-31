import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/charts.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/ledger/presentation/ledger_screen.dart';

enum StatPeriod { month, year, range }

/// Thống kê và báo cáo: thu – chi theo thời gian, theo danh mục, lọc theo kỳ.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  DateTime anchor = DateTime.now();
  StatPeriod period = StatPeriod.month;
  DateTimeRange? range;
  bool income = false;

  (DateTime, DateTime) get bounds => switch (period) {
        StatPeriod.month => (
            DateTime(anchor.year, anchor.month),
            DateTime(anchor.year, anchor.month + 1)
          ),
        StatPeriod.year => (DateTime(anchor.year), DateTime(anchor.year + 1)),
        StatPeriod.range => (
            DateUtilsDate.day(range!.start),
            DateUtilsDate.day(range!.end).add(const Duration(days: 1))
          ),
      };

  String get title => switch (period) {
        StatPeriod.month => 'Tháng ${DateFormat('MM/yyyy').format(anchor)}',
        StatPeriod.year => 'Năm ${anchor.year}',
        StatPeriod.range =>
          '${dayLabel(range!.start)} – ${dayLabel(range!.end)}',
      };

  void shift(int step) => setState(() => anchor = period == StatPeriod.year
      ? DateTime(anchor.year + step)
      : DateTime(anchor.year, anchor.month + step));

  Future<void> pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: range ??
            DateTimeRange(start: DateTime(now.year, now.month), end: now));
    if (r != null && mounted) {
      setState(() {
        range = r;
        period = StatPeriod.range;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final (from, to) = bounds;
    final totalIncome = p.sumBetween(from, to, income: true);
    final totalExpense = p.sumBetween(from, to, income: false);
    final total = income ? totalIncome : totalExpense;
    final categories = [
      for (final c in p.categories.where((c) => c.income == income))
        (c, p.sumBetween(from, to, income: income, categoryId: c.id))
    ].where((x) => x.$2 > 0).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    // Chuỗi thời gian: theo ngày nếu ≤ 62 ngày, ngược lại theo tháng.
    final daily = to.difference(from).inDays <= 62;
    final labels = <String>[];
    final incomes = <double>[], expenses = <double>[];
    if (daily) {
      for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
        final next = DateTime(d.year, d.month, d.day + 1);
        labels.add('${d.day}');
        incomes.add(p.sumBetween(d, next, income: true));
        expenses.add(p.sumBetween(d, next, income: false));
      }
    } else {
      for (var m = DateTime(from.year, from.month);
          m.isBefore(to);
          m = DateTime(m.year, m.month + 1)) {
        final next = DateTime(m.year, m.month + 1);
        final start = m.isBefore(from) ? from : m;
        final end = next.isAfter(to) ? to : next;
        labels.add('T${m.month}');
        incomes.add(p.sumBetween(start, end, income: true));
        expenses.add(p.sumBetween(start, end, income: false));
      }
    }
    const colors = [
      Color(0xFFAF8F79),
      Color(0xFF83A38B),
      Color(0xFFD8B77E),
      Color(0xFF8E9FAE),
      Color(0xFFB69AA6),
      Color(0xFFD38B7D),
      Color(0xFF8DB8AE)
    ];
    final diff = totalIncome - totalExpense;
    return FinancePage(
        title: 'Báo cáo thu chi',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (value, label) in const [
              (StatPeriod.month, 'Tháng'),
              (StatPeriod.year, 'Năm'),
              (StatPeriod.range, 'Khoảng ngày'),
            ])
              ChoiceChip(
                  label: Text(label),
                  selected: period == value,
                  onSelected: (_) {
                    if (value == StatPeriod.range) {
                      pickRange();
                    } else {
                      setState(() => period = value);
                    }
                  }),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
                tooltip: 'Kỳ trước',
                onPressed: period == StatPeriod.range ? null : () => shift(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: InkWell(
                    onTap: period == StatPeriod.range ? pickRange : null,
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600)))),
            IconButton(
                tooltip: 'Kỳ sau',
                onPressed: period == StatPeriod.range ? null : () => shift(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          Panel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: _Stat('Thu nhập', money(totalIncome, p.currency),
                          AppColors.primaryGreen)),
                  Expanded(
                      child: _Stat('Chi tiêu', money(totalExpense, p.currency),
                          AppColors.accentRed)),
                ]),
                const Divider(height: 24),
                Row(children: [
                  Expanded(
                      child: Text(diff >= 0 ? 'Tiết kiệm được' : 'Chi vượt thu')),
                  Text(money(diff.abs(), p.currency),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: diff >= 0
                              ? AppColors.primaryGreen
                              : AppColors.accentRed)),
                ]),
                if (totalIncome > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                      'Chi tiêu bằng ${(100 * totalExpense / totalIncome).toStringAsFixed(0)}% thu nhập',
                      style: const TextStyle(fontSize: 12)),
                ],
              ])),
          const SectionTitle('Thu nhập và chi tiêu theo thời gian'),
          Panel(
              child: Column(children: [
            SizedBox(
                height: 200,
                child: totalIncome == 0 && totalExpense == 0
                    ? const Center(child: Text('Chưa có dữ liệu trong kỳ này'))
                    : IncomeExpenseChart(
                        labels: labels, incomes: incomes, expenses: expenses)),
            const SizedBox(height: 8),
            const Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                        radius: 5, backgroundColor: AppColors.primaryGreen),
                    Text('  Thu nhập', style: TextStyle(fontSize: 12)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 5, backgroundColor: AppColors.accentRed),
                    Text('  Chi tiêu', style: TextStyle(fontSize: 12)),
                  ]),
                ]),
          ])),
          const SizedBox(height: 16),
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: false, label: Text('Chi tiêu')),
            ButtonSegment(value: true, label: Text('Thu nhập'))
          ], selected: {
            income
          }, onSelectionChanged: (v) => setState(() => income = v.first)),
          const SizedBox(height: 16),
          Panel(
              child: Column(children: [
            if (total == 0)
              const EmptyView(
                  title: 'Chưa có dữ liệu báo cáo',
                  subtitle: 'Các giao dịch thu chi sẽ được tổng hợp tại đây.',
                  icon: Icons.pie_chart_outline)
            else
              SizedBox(
                  height: 230,
                  child: Stack(alignment: Alignment.center, children: [
                    PieChart(PieChartData(
                        centerSpaceRadius: 70,
                        sectionsSpace: 3,
                        sections: [
                          for (final (i, (_, value)) in categories.indexed)
                            PieChartSectionData(
                                value: value,
                                color: colors[i % colors.length],
                                radius: 28,
                                showTitle: false)
                        ])),
                    SizedBox(
                        width: 130,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(income ? 'Tổng thu' : 'Tổng chi'),
                          Text(money(total, p.currency),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 17))
                        ])),
                  ])),
            for (final (i, (c, value)) in categories.indexed)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  tileColor: Colors.transparent,
                  leading: RoundIcon(c.icon, color: colors[i % colors.length]),
                  title: Text(c.name),
                  subtitle: Text(money(value, p.currency)),
                  trailing: Text('${(100 * value / total).toStringAsFixed(1)}%'),
                  onTap: () => openPage(context, LedgerScreen(initialCategoryId: c.id))),
          ])),
        ]));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        FittedBox(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 18, color: color))),
      ]);
}
