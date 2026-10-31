import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

const _axisStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);

FlTitlesData _titles(
        {required Widget Function(double, TitleMeta) bottom,
        bool left = true,
        double? bottomInterval}) =>
    FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: left,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(compactMoney(v), style: _axisStyle))),
      bottomTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: bottomInterval,
              getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: bottom(v, meta)))),
    );

FlGridData _grid() => FlGridData(
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        const FlLine(color: AppColors.divider, strokeWidth: 1));

/// Biểu đồ cột đơn giản so sánh vài giá trị (ví dụ: kỳ trước – kỳ này).
class CompareBarChart extends StatelessWidget {
  const CompareBarChart(
      {super.key, required this.labels, required this.values, required this.colors});
  final List<String> labels;
  final List<double> values;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) {
    final top = values.fold(0.0, math.max);
    return BarChart(BarChartData(
      maxY: math.max(top * 1.2, 1),
      alignment: BarChartAlignment.spaceEvenly,
      borderData: FlBorderData(show: false),
      gridData: _grid(),
      barTouchData: BarTouchData(enabled: false),
      titlesData: _titles(
          bottom: (v, _) => Text(
              v.toInt() >= 0 && v.toInt() < labels.length ? labels[v.toInt()] : '',
              style: _axisStyle)),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
                toY: values[i],
                width: 34,
                color: colors[i % colors.length],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))
          ])
      ],
    ));
  }
}

/// Biểu đồ cột ghép thu nhập (xanh) – chi tiêu (đỏ) theo từng kỳ.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart(
      {super.key,
      required this.labels,
      required this.incomes,
      required this.expenses});
  final List<String> labels;
  final List<double> incomes, expenses;
  @override
  Widget build(BuildContext context) {
    final top = [...incomes, ...expenses].fold(0.0, math.max);
    final width = labels.length > 16 ? 3.0 : labels.length > 8 ? 6.0 : 12.0;
    final step = labels.length > 16 ? 5 : labels.length > 8 ? 2 : 1;
    return BarChart(BarChartData(
      maxY: math.max(top * 1.15, 1),
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: _grid(),
      barTouchData: BarTouchData(enabled: false),
      titlesData: _titles(bottom: (v, _) {
        final i = v.toInt();
        if (i < 0 || i >= labels.length || i % step != 0) {
          return const SizedBox.shrink();
        }
        return Text(labels[i], style: _axisStyle);
      }),
      barGroups: [
        for (var i = 0; i < labels.length; i++)
          BarChartGroupData(x: i, barsSpace: 2, barRods: [
            BarChartRodData(
                toY: incomes[i],
                width: width,
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(2)),
            BarChartRodData(
                toY: expenses[i],
                width: width,
                color: AppColors.accentRed,
                borderRadius: BorderRadius.circular(2)),
          ])
      ],
    ));
  }
}

/// Đường lũy kế theo ngày: kỳ này (liền) so với kỳ trước (nét đứt).
class TrendLineChart extends StatelessWidget {
  const TrendLineChart(
      {super.key,
      required this.current,
      required this.previous,
      required this.color});
  final List<double> current, previous;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final days = math.max(current.length, previous.length);
    final top = [...current, ...previous].fold(0.0, math.max);
    List<FlSpot> spots(List<double> v) =>
        [for (var i = 0; i < v.length; i++) FlSpot(i + 1.0, v[i])];
    return LineChart(LineChartData(
      minX: 1,
      maxX: math.max(days.toDouble(), 2),
      minY: 0,
      maxY: math.max(top * 1.15, 1),
      borderData: FlBorderData(show: false),
      gridData: _grid(),
      lineTouchData: const LineTouchData(enabled: false),
      titlesData: _titles(
          bottomInterval: 7,
          bottom: (v, _) => Text('${v.toInt()}', style: _axisStyle)),
      lineBarsData: [
        LineChartBarData(
            spots: spots(previous),
            color: AppColors.textGrey,
            barWidth: 2,
            dashArray: const [5, 4],
            dotData: const FlDotData(show: false)),
        LineChartBarData(
            spots: spots(current),
            color: color,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: .12))),
      ],
    ));
  }
}

/// Vòng tròn phần trăm (tiến độ trả nợ / thu nợ / tiết kiệm).
class PercentRing extends StatelessWidget {
  const PercentRing(
      {super.key, required this.value, required this.color, this.size = 64});
  final double value;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: Stack(fit: StackFit.expand, children: [
        CircularProgressIndicator(
            value: value.isFinite ? value.clamp(0, 1) : 0,
            strokeWidth: 6,
            color: color,
            backgroundColor: color.withValues(alpha: .15)),
        Center(
            child: Text('${((value.isFinite ? value : 0) * 100).clamp(0, 999).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
      ]));
}
