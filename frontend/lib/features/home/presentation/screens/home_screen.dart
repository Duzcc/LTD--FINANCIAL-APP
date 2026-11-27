import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/brand_logo.dart';
import 'package:finance_app/core/utils/dates.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/charts.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';
import 'package:finance_app/features/wallets/presentation/screens/currency_selection_screen.dart';
import 'package:finance_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:finance_app/features/statistics/domain/period_report.dart';
import 'package:finance_app/features/ledger/presentation/screens/ledger_screen.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:finance_app/features/ai/presentation/widgets/quick_entry_sheet.dart';
import 'package:finance_app/features/banking/presentation/screens/receive_qr_screen.dart';

// Màn hình tổng quan
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return DefaultTabController(
        length: 2,
        child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 12, 8),
                  child: Row(children: [
                    IconButton(
                        key: const ValueKey('open-drawer'),
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu)),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Flexible(
                                child: Text(
                                    secret(p.hideBalance, p.totalBalance(p.currency),
                                        p.currency),
                                    style: const TextStyle(
                                        fontSize: 26, fontWeight: FontWeight.w800),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            IconButton(
                                tooltip: p.hideBalance ? 'Hiện số dư' : 'Ẩn số dư',
                                onPressed: () => p.preferences(hidden: !p.hideBalance),
                                icon: Icon(
                                    p.hideBalance
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18))
                          ]),
                          Text(
                              p.hasManyCurrencies && !p.hideBalance
                                  ? 'Tổng số dư • quy đổi mọi ví ≈ ${money(p.convertedTotal(p.currency), p.currency)}'
                                  : 'Tổng số dư • Xin chào, ${p.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ])),
                    IconButton(
                        key: const ValueKey('quick-entry-button'),
                        tooltip: 'Nhập nhanh bằng AI',
                        onPressed: () => showQuickEntry(context),
                        icon: const BrandLogo.ai(size: 26)),
                    IconButton(
                        tooltip: 'Tìm giao dịch',
                        onPressed: () => openPage(context, const LedgerScreen()),
                        icon: const Icon(Icons.search)),
                    IconButton(
                        tooltip: 'Chọn tiền tệ báo cáo',
                        onPressed: () async {
                          final unit = await openPage<String>(context,
                              CurrencySelectionScreen(selectedCurrency: p.currency));
                          if (unit != null) p.preferences(unit: unit);
                        },
                        icon: const Icon(Icons.currency_exchange, size: 22)),
                  ])),
              const TabBar(tabs: [Tab(text: 'Báo cáo'), Tab(text: 'Sổ nợ')]),
              const Expanded(
                  child: TabBarView(children: [OverviewTab(), DebtOverview()])),
            ])));
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final recent = p.entriesInCurrency(p.currency).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ReportCarousel(),
        SectionTitle(
          'Giao dịch gần đây',
          action: 'Xem tất cả',
          onTap: () => openPage(context, const LedgerScreen(allDates: true)),
        ),
        for (final entry in recent.take(4)) EntryTile(entry),
        if (recent.isEmpty)
          OutlinedButton.icon(
            onPressed: () => openPage(context, const AddTransactionScreen()),
            icon: const Icon(Icons.add),
            label: const Text('Ghi giao dịch đầu tiên'),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

String dueLabel(int days) => days < 0
    ? 'Quá hạn ${-days} ngày'
    : days == 0
        ? 'Đến hạn hôm nay'
        : 'Còn $days ngày đến hạn';

// Báo cáo nhanh theo tuần và tháng
class ReportCarousel extends StatefulWidget {
  const ReportCarousel({super.key});
  @override
  State<ReportCarousel> createState() => _ReportCarouselState();
}

class _ReportCarouselState extends State<ReportCarousel> {
  final controller = PageController();
  int page = 0;
  bool weekly = false;
  bool trendIncome = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void go(int i) => controller.animateToPage(i,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final now = DateTime.now();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final showWeek = page == 0 && weekly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          showWeek ? 'Báo cáo tuần này' : 'Báo cáo tháng này',
          action: 'Xem báo cáo',
          onTap: () => openPage(
            context,
            StatisticsScreen(weekly: showWeek, showIncome: page == 1 && trendIncome),
          ),
        ),
        Panel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              SizedBox(
                  height: 250 + 40 * scale,
                  child: PageView(
                      controller: controller,
                      onPageChanged: (i) => setState(() => page = i),
                      children: [spending(p, now), trend(p, now)])),
              Row(children: [
                IconButton(
                    tooltip: 'Báo cáo trước',
                    onPressed: page == 0 ? null : () => go(0),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 2; i++)
                    AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: page == i ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color:
                                page == i ? AppColors.primaryGreen : AppColors.divider,
                            borderRadius: BorderRadius.circular(4))),
                ])),
                IconButton(
                    tooltip: 'Báo cáo tiếp theo',
                    onPressed: page == 1 ? null : () => go(1),
                    icon: const Icon(Icons.chevron_right)),
              ]),
            ])),
      ],
    );
  }

  Widget spending(FinanceProvider p, DateTime now) {
    final today = dateOnly(now);
    final DateTime start, prevStart, end;
    if (weekly) {
      start = DateTime(today.year, today.month, today.day - today.weekday + 1);
      prevStart = DateTime(start.year, start.month, start.day - 7);
      end = DateTime(start.year, start.month, start.day + 7);
    } else {
      start = DateTime(now.year, now.month);
      prevStart = DateTime(now.year, now.month - 1);
      end = DateTime(now.year, now.month + 1);
    }
    final current = p.sumBetween(start, end, income: false);
    final previous = p.sumBetween(prevStart, start, income: false);
    final change = previous == 0 ? null : (current - previous) / previous;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
            child: Text('Báo cáo chi tiêu',
                style: TextStyle(fontWeight: FontWeight.w700))),
        SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            segments: const [
              ButtonSegment(value: true, label: Text('Tuần')),
              ButtonSegment(value: false, label: Text('Tháng')),
            ],
            selected: {weekly},
            onSelectionChanged: (v) => setState(() => weekly = v.first)),
      ]),
      const SizedBox(height: 8),
      Text(money(current, p.currency),
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentRed)),
      Text(
          change == null
              ? 'Tổng đã chi ${weekly ? 'tuần' : 'tháng'} này'
              : 'Tổng đã chi • ${change >= 0 ? 'tăng' : 'giảm'} ${(change.abs() * 100).toStringAsFixed(0)}% so với ${weekly ? 'tuần' : 'tháng'} trước',
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Expanded(
          child: current == 0 && previous == 0
              ? const Center(
                  child: Text('Nhập giao dịch để xem báo cáo',
                      textAlign: TextAlign.center))
              : CompareBarChart(
                  labels: weekly
                      ? const ['Tuần trước', 'Tuần này']
                      : const ['Tháng trước', 'Tháng này'],
                  values: [previous, current],
                  colors: const [Color(0xFFD9BEA9), AppColors.accentRed])),
    ]);
  }

  Widget trend(FinanceProvider p, DateTime now) {
    final month = DateTime(now.year, now.month);
    final entries = p.entriesInCurrency(p.currency);
    final currentMonth = PeriodReport(
      from: month,
      until: DateTime(now.year, now.month, now.day + 1),
      entries: entries,
    );
    final previousMonth = PeriodReport(
      from: DateTime(now.year, now.month - 1),
      until: month,
      entries: entries,
    );

    List<double> cumulative(PeriodReport report) {
      final values = <double>[];
      var sum = 0.0;
      for (final day in report.series.values) {
        sum += trendIncome ? day.income : day.expense;
        values.add(sum);
      }
      return values;
    }

    final current = cumulative(currentMonth);
    final previous = cumulative(previousMonth);
    final income = currentMonth.totals.income;
    final expense = currentMonth.totals.expense;
    final color = trendIncome ? AppColors.primaryGreen : AppColors.accentRed;
    Widget metric(String label, double value, bool forIncome) => Expanded(
        child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => trendIncome = forIncome),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  FittedBox(
                      child: Text(money(value, p.currency),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: forIncome
                                  ? AppColors.primaryGreen
                                  : AppColors.accentRed))),
                  const SizedBox(height: 6),
                  Container(
                      height: 3,
                      color: trendIncome == forIncome
                          ? (forIncome ? AppColors.primaryGreen : AppColors.accentRed)
                          : Colors.transparent),
                ]))));
    return Column(children: [
      const Align(
          alignment: Alignment.centerLeft,
          child:
              Text('Báo cáo xu hướng', style: TextStyle(fontWeight: FontWeight.w700))),
      const SizedBox(height: 6),
      Row(children: [
        metric('Tổng đã chi', expense, false),
        const SizedBox(width: 8),
        metric('Tổng thu', income, true),
      ]),
      const SizedBox(height: 10),
      Expanded(
          child: current.every((v) => v == 0) && previous.every((v) => v == 0)
              ? const Center(child: Text('Nhập giao dịch để xem báo cáo'))
              : TrendLineChart(current: current, previous: previous, color: color)),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 14, height: 3, color: color),
        const Text('  Tháng này     ', style: TextStyle(fontSize: 11)),
        Container(width: 14, height: 3, color: AppColors.textGrey),
        const Text('  Tháng trước', style: TextStyle(fontSize: 11)),
      ]),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        FittedBox(
            child: Text(value,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: color))),
      ]);
}

class DebtOverview extends StatefulWidget {
  const DebtOverview({super.key});
  @override
  State<DebtOverview> createState() => _DebtOverviewState();
}

class _DebtOverviewState extends State<DebtOverview> {
  bool byPerson = true;

  Widget side(FinanceProvider p, {required bool borrowed}) {
    final t = p.debtTotals(borrowed: borrowed);
    final left = math.max(0.0, t.principal - t.settled);
    final color = borrowed ? AppColors.accentRed : AppColors.primaryGreen;
    return Panel(
        color: borrowed ? const Color(0xFFF7E9E6) : const Color(0xFFE6F2EA),
        child: Column(children: [
          Text(borrowed ? 'Đi vay • phải trả' : 'Cho vay • cần thu',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 12),
          PercentRing(
              value: t.principal == 0 ? 0 : t.settled / t.principal, color: color),
          const SizedBox(height: 12),
          _Metric('Tổng cộng', secret(p.hideBalance, t.principal, p.currency),
              AppColors.textPrimary),
          const SizedBox(height: 8),
          _Metric('Còn lại', secret(p.hideBalance, left, p.currency), color),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final entries = p.entries
        .where((e) => e.kind.isDebt && p.findWallet(e.walletId)?.currency == p.currency)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final payable = p.debt(borrowed: true), receivable = p.debt(borrowed: false);
    final remaining = byPerson ? const <String, double>{} : p.remainingByLoan();
    final balance = receivable - payable;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: side(p, borrowed: true)),
        const SizedBox(width: 12),
        Expanded(child: side(p, borrowed: false)),
      ]),
      const SizedBox(height: 12),
      Panel(
          child: Row(children: [
        const Icon(Icons.balance_outlined, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(balance == 0
                ? 'Cân bằng'
                : balance > 0
                    ? 'Cân bằng • bạn đang được nợ'
                    : 'Cân bằng • bạn đang nợ')),
        Text(secret(p.hideBalance, balance, p.currency),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: balance >= 0 ? AppColors.primaryGreen : AppColors.accentRed)),
      ])),
      const SizedBox(height: 16),
      SegmentedButton<bool>(segments: const [
        ButtonSegment(value: true, label: Text('Xem theo người')),
        ButtonSegment(value: false, label: Text('Xem theo ngày'))
      ], selected: {
        byPerson
      }, onSelectionChanged: (v) => setState(() => byPerson = v.first)),
      const SizedBox(height: 16),
      if (entries.isEmpty)
        const EmptyView(
            title: 'Không có giao dịch nợ nào',
            subtitle:
                'Ghi lại người liên quan, số tiền và ngày hẹn trả để dễ theo dõi.',
            icon: Icons.handshake_outlined),
      if (byPerson)
        for (final id in entries.map((e) => e.personId).toSet())
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonDebt(personId: id, entries: entries))
      else
        for (final e in entries) ...[
          EntryTile(e),
          if (e.dueDate != null && remaining.containsKey(e.id))
            Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 10),
                child: Text(
                    dueLabel(dateOnly(e.dueDate!)
                        .difference(dateOnly(DateTime.now()))
                        .inDays),
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.accentOrange))),
        ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
                onPressed: () => openPage(
                    context, const AddTransactionScreen(initialKind: EntryKind.borrow)),
                icon: const Icon(Icons.south_west),
                label: const Text('Thêm đi vay'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton.icon(
                onPressed: () => openPage(
                    context, const AddTransactionScreen(initialKind: EntryKind.lend)),
                icon: const Icon(Icons.north_east),
                label: const Text('Thêm cho vay'))),
      ]),
    ]);
  }
}

class _PersonDebt extends StatelessWidget {
  const _PersonDebt({required this.personId, required this.entries});
  final String? personId;
  final List<MoneyEntry> entries;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final receivable = p.debt(borrowed: false, personId: personId);
    final payable = p.debt(borrowed: true, personId: personId);
    final own = entries.where((e) => e.personId == personId).toList();
    final wallet = own.first.walletId;
    final debtWallet = p.findWallet(wallet);
    final bankWallet = debtWallet != null && debtWallet.hasBank
        ? debtWallet
        : p.wallets.where((w) => w.hasBank).firstOrNull;
    final receivableVnd = p.debt(borrowed: false, personId: personId, unit: 'VND');
    return Panel(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const RoundIcon(Icons.person_outline),
            title: Text(p.personName(personId),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'Cần thu ${secret(p.hideBalance, receivable, p.currency)} • Phải trả ${secret(p.hideBalance, payable, p.currency)}'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Wrap(spacing: 8, children: [
                if (receivable > 0)
                  OutlinedButton(
                      onPressed: () => openPage(
                          context,
                          AddTransactionScreen(
                              initialKind: EntryKind.collect,
                              initialPersonId: personId,
                              initialWalletId: wallet,
                              initialAmount: receivable)),
                      child: const Text('Thu nợ')),
                if (receivableVnd > 0 && bankWallet != null)
                  OutlinedButton.icon(
                      onPressed: () => openPage(
                          context,
                          ReceiveQrScreen(
                              walletId: bankWallet.id,
                              personId: personId,
                              amount: receivableVnd)),
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('Đòi nợ bằng QR')),
                if (payable > 0)
                  OutlinedButton(
                      onPressed: () => openPage(
                          context,
                          AddTransactionScreen(
                              initialKind: EntryKind.repay,
                              initialPersonId: personId,
                              initialWalletId: wallet,
                              initialAmount: payable)),
                      child: const Text('Trả nợ')),
                if (receivable <= 0 && payable <= 0)
                  const Chip(label: Text('Đã tất toán')),
              ]),
              const SizedBox(height: 8),
              for (final e in own) EntryTile(e),
            ]));
  }
}
