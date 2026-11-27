import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/utils/dates.dart';
import 'package:finance_app/core/widgets/charts.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/finance/presentation/widgets/entity_icons.dart';
import 'package:finance_app/features/statistics/domain/period_report.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';

enum StatPeriod { week, month, year, range }

// Báo cáo thu chi
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, this.weekly = false, this.showIncome = false});

  final bool weekly;
  final bool showIncome;

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  DateTime anchor = DateTime.now();
  late StatPeriod period = widget.weekly ? StatPeriod.week : StatPeriod.month;
  late bool income = widget.showIncome;
  DateTimeRange? range;

  (DateTime, DateTime) get bounds {
    switch (period) {
      case StatPeriod.week:
        final monday =
            DateTime(anchor.year, anchor.month, anchor.day - anchor.weekday + 1);
        return (monday, DateTime(monday.year, monday.month, monday.day + 7));
      case StatPeriod.month:
        return (
          DateTime(anchor.year, anchor.month),
          DateTime(anchor.year, anchor.month + 1)
        );
      case StatPeriod.year:
        return (DateTime(anchor.year), DateTime(anchor.year + 1));
      case StatPeriod.range:
        final end = range!.end;
        return (dateOnly(range!.start), DateTime(end.year, end.month, end.day + 1));
    }
  }

  String periodLabel(DateTime from, DateTime last) {
    if (period == StatPeriod.year) return 'Năm ${from.year}';
    if (period == StatPeriod.month)
      return 'Tháng ${DateFormat('MM/yyyy').format(from)}';
    return '${dayLabel(from)} – ${dayLabel(last)}';
  }

  void shift(int step) {
    setState(() {
      anchor = switch (period) {
        StatPeriod.week => DateTime(anchor.year, anchor.month, anchor.day + 7 * step),
        StatPeriod.month => DateTime(anchor.year, anchor.month + step),
        StatPeriod.year => DateTime(anchor.year + step),
        StatPeriod.range => anchor,
      };
    });
  }

  Future<void> pickRange() async {
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: range,
    );

    if (chosen == null || !mounted) return;
    setState(() {
      range = chosen;
      anchor = chosen.start;
      period = StatPeriod.range;
    });
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final (from, until) = bounds;
    final last = DateTime(until.year, until.month, until.day - 1);
    final currency = finance.currency;
    final report = PeriodReport(
      from: from,
      until: until,
      entries: finance.entriesInCurrency(currency),
    );
    final difference = report.totals.income - report.totals.expense;
    final total = income ? report.totals.income : report.totals.expense;
    final amounts = income ? report.incomeByCategory : report.expenseByCategory;
    final categories = amounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    void openCategory(String? categoryId) {
      openPage(
        context,
        _CategoryTransactions(
          categoryId: categoryId,
          currency: currency,
          from: from,
          until: until,
          income: income,
        ),
      );
    }

    return FinancePage(
      title: 'Báo cáo thu chi',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (value, label) in const [
                (StatPeriod.week, 'Tuần'),
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
                  },
                ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Kỳ trước',
                onPressed: period == StatPeriod.range ? null : () => shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: pickRange,
                  child: Text(periodLabel(from, last), textAlign: TextAlign.center),
                ),
              ),
              IconButton(
                tooltip: 'Kỳ sau',
                onPressed: period == StatPeriod.range ? null : () => shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _Stat('Thu nhập', money(report.totals.income, currency),
                            AppColors.primaryGreen)),
                    Expanded(
                        child: _Stat('Chi tiêu', money(report.totals.expense, currency),
                            AppColors.accentRed)),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                        child:
                            Text(difference >= 0 ? 'Tiết kiệm được' : 'Chi vượt thu')),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money(difference.abs(), currency),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: difference >= 0
                                ? AppColors.primaryGreen
                                : AppColors.accentRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (report.totals.income > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Chi tiêu bằng ${(100 * report.totals.expense / report.totals.income).round()}% thu nhập',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Thu nhập và chi tiêu theo thời gian'),
          Panel(
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: report.totals.income == 0 && report.totals.expense == 0
                      ? const Center(child: Text('Chưa có dữ liệu trong kỳ này'))
                      : IncomeExpenseChart(
                          labels: report.labels,
                          incomes: [
                            for (final bucket in report.series.values) bucket.income
                          ],
                          expenses: [
                            for (final bucket in report.series.values) bucket.expense
                          ],
                        ),
                ),
                const Wrap(
                  spacing: 16,
                  children: [
                    _Legend('Thu nhập', AppColors.primaryGreen),
                    _Legend('Chi tiêu', AppColors.accentRed),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Theo danh mục'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Chi tiêu')),
              ButtonSegment(value: true, label: Text('Thu nhập')),
            ],
            selected: {income},
            onSelectionChanged: (selection) => setState(() => income = selection.first),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                if (categories.isEmpty)
                  const EmptyView(
                    title: 'Chưa có dữ liệu báo cáo',
                    subtitle: 'Chọn kỳ khác hoặc ghi thêm giao dịch.',
                    icon: Icons.pie_chart_outline,
                  )
                else
                  SizedBox(
                    height: 210,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            centerSpaceRadius: 65,
                            sectionsSpace: 3,
                            pieTouchData: PieTouchData(
                              touchCallback: (event, response) {
                                if (event is! FlTapUpEvent) return;
                                final index =
                                    response?.touchedSection?.touchedSectionIndex ?? -1;
                                if (index >= 0 && index < categories.length) {
                                  openCategory(categories[index].key);
                                }
                              },
                            ),
                            sections: [
                              for (final (i, category) in categories.indexed)
                                PieChartSectionData(
                                  value: category.value,
                                  color: _colors[i % _colors.length],
                                  radius: 27,
                                  showTitle: false,
                                ),
                            ],
                          ),
                        ),
                        IgnorePointer(
                          child: SizedBox(
                            width: 118,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(income ? 'Tổng thu' : 'Tổng chi'),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(money(total, currency),
                                      style:
                                          const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final (i, group) in categories.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: RoundIcon(
                      finance.category(group.key)?.icon ?? Icons.category_outlined,
                      color: _colors[i % _colors.length],
                    ),
                    title: Text(finance.category(group.key)?.name ?? 'Chưa phân loại'),
                    subtitle: Text(money(group.value, currency)),
                    trailing:
                        Text('${(100 * group.value / total).toStringAsFixed(1)}%'),
                    onTap: () => openCategory(group.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _colors = [
  Color(0xFFAF8F79),
  Color(0xFF83A38B),
  Color(0xFFD8B77E),
  Color(0xFF8E9FAE),
  Color(0xFFB69AA6),
  Color(0xFFD38B7D),
  Color(0xFF8DB8AE),
];

// Giao dịch của danh mục trong kỳ đang xem
class _CategoryTransactions extends StatelessWidget {
  const _CategoryTransactions({
    required this.categoryId,
    required this.currency,
    required this.from,
    required this.until,
    required this.income,
  });

  final String? categoryId;
  final String currency;
  final DateTime from;
  final DateTime until;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final entries = finance.between(from, until, unit: currency).where((entry) {
      final matchesKind = income ? entry.kind.isIncome : entry.kind.isExpense;
      return !entry.excluded && matchesKind && entry.categoryId == categoryId;
    }).toList();
    final last = DateTime(until.year, until.month, until.day - 1);
    final total = entries.fold(0.0, (sum, entry) => sum + entry.amount);

    return FinancePage(
      title: finance.category(categoryId)?.name ?? 'Chưa phân loại',
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) return EntryTile(entries[index - 1]);
          return Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${dayLabel(from)} – ${dayLabel(last)}'),
                const SizedBox(height: 8),
                _Stat(
                  '${entries.length} giao dịch • ${income ? 'Tổng thu' : 'Tổng chi'}',
                  money(total, currency),
                  income ? AppColors.primaryGreen : AppColors.accentRed,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
