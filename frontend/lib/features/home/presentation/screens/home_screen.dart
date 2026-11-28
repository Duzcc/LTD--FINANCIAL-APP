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
import 'package:finance_app/features/wallets/presentation/screens/wallets_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/create_wallet_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallet_detail_screen.dart';
import 'package:finance_app/features/ledger/presentation/screens/ledger_screen.dart';
import 'package:finance_app/features/budgets/presentation/screens/budgets_screen.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:finance_app/features/ai/presentation/widgets/quick_entry_sheet.dart';
import 'package:finance_app/features/ai/presentation/screens/insights_screen.dart';
import 'package:finance_app/features/ai/presentation/widgets/insight_tile.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/services/insights.dart';
import 'package:finance_app/features/finance/presentation/widgets/entity_icons.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return DefaultTabController(
        length: 3,
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
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(money(p.totalBalance(p.currency), p.currency),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          p.hasManyCurrencies
                              ? 'Tổng số dư • quy đổi mọi ví ≈ ${money(p.convertedTotal(p.currency), p.currency)}'
                              : 'Tổng số dư • Xin chào, ${p.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                  ])),
              const TabBar(tabs: [Tab(text: 'Tổng quan'), Tab(text: 'Sổ nợ'), Tab(text: 'Ví')]),
              const Expanded(child: TabBarView(children: [OverviewTab(), DebtOverview(), WalletList()])),
            ])));
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final now = DateTime.now();
    final expense = p.total(now, income: false);
    final recent = p.inMonth(now, unit: p.currency).take(4).toList();
    final wallets = p.wallets.where((w) => w.currency == p.currency).toList();
    final byCategory = [
      for (final c in p.categories.where((c) => !c.income)) (c, p.total(now, income: false, categoryId: c.id))
    ].where((x) => x.$2 > 0).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final overall = p.overallBudget(now, income: false);
    final budgets = p.budgets
        .where((b) =>
            b.categoryId != null &&
            !p.budgetIncome(b) &&
            b.currency == p.currency &&
            b.month.year == now.year &&
            b.month.month == now.month)
        .toList();
    final due = dueDebts(p);
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionTitle('Ví của tôi', action: 'Xem tất cả', onTap: () => openPage(context, const WalletsScreen())),
      Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final w in wallets.take(3))
              ListTile(
                  leading: RoundIcon(w.icon),
                  title: Text(w.name),
                  subtitle: Text('${money(p.balance(w.id), w.currency)}${w.excluded ? ' • không tính tổng' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPage(context, WalletDetailScreen(walletId: w.id))),
            if (wallets.isEmpty)
              ListTile(
                  title: const Text('Thêm ví đầu tiên'),
                  trailing: const Icon(Icons.add),
                  onTap: () => openPage(context, const CreateWalletScreen())),
          ])),
      ValueListenableBuilder<int>(
          valueListenable: AiRepository.insightsVersion,
          builder: (context, _, __) {
            final repo = AiRepository(p);
            repo.refreshInsightsIfStale();
            final tips = FinanceInsights(p, server: repo.cachedInsights?.forecast).all().take(2).toList();
            if (tips.isEmpty) return const SizedBox.shrink();
            return Column(children: [
              SectionTitle('Phân tích thông minh',
                  action: 'Xem thêm', onTap: () => openPage(context, const InsightsScreen())),
              for (final t in tips) InsightTile(insight: t),
            ]);
          }),
      if (byCategory.isNotEmpty) ...[
        const SectionTitle('Chi tiêu theo danh mục'),
        Panel(
            child: Column(children: [
          for (final (c, amount) in byCategory.take(5))
            Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(children: [
                  Row(children: [
                    Icon(c.icon, size: 18, color: const Color(0xFF9B806B)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.name)),
                    Text('${money(amount, p.currency)} • ${(100 * amount / expense).toStringAsFixed(0)}%')
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value: expense == 0 ? 0 : (amount / expense).clamp(0, 1),
                      minHeight: 5,
                      color: const Color(0xFFCCAD97),
                      backgroundColor: AppColors.backgroundBeige,
                      borderRadius: BorderRadius.circular(4)),
                ])),
        ])),
      ],
      SectionTitle('Ngân sách tháng này', action: 'Quản lý', onTap: () => openPage(context, const BudgetsScreen())),
      Panel(
          child: overall == null && budgets.isEmpty
              ? Row(children: [
                  const RoundIcon(Icons.track_changes),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('Chưa đặt ngân sách. Đặt hạn mức để được cảnh báo khi chi tiêu vượt kế hoạch.')),
                  TextButton(onPressed: () => openPage(context, const BudgetsScreen()), child: const Text('Đặt ngay')),
                ])
              : Column(children: [
                  if (overall != null)
                    BudgetBar(
                        label: 'Tổng chi tiêu',
                        icon: Icons.account_balance_wallet_outlined,
                        used: p.used(overall),
                        target: overall.amount,
                        unit: overall.currency),
                  for (final b in budgets.take(3))
                    BudgetBar(
                        label: p.category(b.categoryId)?.name ?? '',
                        icon: p.category(b.categoryId)?.icon ?? Icons.category_outlined,
                        used: p.used(b),
                        target: b.amount,
                        unit: b.currency),
                ])),
      if (due.isNotEmpty) ...[
        const SectionTitle('Khoản vay/nợ cần chú ý'),
        Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final d in due.take(4))
                ListTile(
                    leading: RoundIcon(d.entry.kind == EntryKind.lend ? Icons.north_east : Icons.south_west,
                        color: d.days < 0 ? AppColors.accentRed : AppColors.accentOrange),
                    title: Text(
                        '${d.entry.kind == EntryKind.lend ? 'Thu nợ' : 'Trả nợ'} • ${p.personName(d.entry.personId)}'),
                    subtitle: Text(dueLabel(d.days)),
                    trailing: Text(money(d.remaining, d.unit), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => openPage(
                        context,
                        AddTransactionScreen(
                            initialKind: d.entry.kind == EntryKind.lend ? EntryKind.collect : EntryKind.repay,
                            initialPersonId: d.entry.personId,
                            initialWalletId: d.entry.walletId,
                            initialAmount: d.remaining))),
            ])),
      ],
      SectionTitle('Giao dịch gần đây', action: 'Xem tất cả', onTap: () => openPage(context, const LedgerScreen())),
      for (final e in recent) EntryTile(e),
      if (recent.isEmpty)
        OutlinedButton.icon(
            onPressed: () => openPage(context, const AddTransactionScreen()),
            icon: const Icon(Icons.add),
            label: const Text('Ghi giao dịch đầu tiên')),
      const SizedBox(height: 12),
      const Panel(
          color: Color(0xFFE8D9CC),
          child: Row(children: [
            RoundIcon(Icons.lightbulb_outline),
            SizedBox(width: 12),
            Expanded(
                child: Text('Mỗi khoản nhỏ được ghi lại là một bước để quản lý tiền tốt hơn.',
                    style: TextStyle(height: 1.5)))
          ])),
    ]);
  }
}

List<({MoneyEntry entry, int days, double remaining, String unit})> dueDebts(FinanceProvider p) {
  final today = dateOnly(DateTime.now());
  final result = <({MoneyEntry entry, int days, double remaining, String unit})>[];
  final seen = <String>{};
  final principals = p.entries
      .where((e) => (e.kind == EntryKind.lend || e.kind == EntryKind.borrow) && e.dueDate != null)
      .toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  for (final e in principals) {
    final unit = p.findWallet(e.walletId)?.currency ?? p.currency;
    final key = '${e.kind.name}|${e.personId}|$unit';
    if (seen.contains(key)) continue;
    final remaining = p.debt(borrowed: e.kind == EntryKind.borrow, personId: e.personId, unit: unit);
    if (remaining <= 0) continue;
    final days = dateOnly(e.dueDate!).difference(today).inDays;
    if (days > 7) continue;
    seen.add(key);
    result.add((entry: e, days: days, remaining: remaining, unit: unit));
  }
  return result;
}

String dueLabel(int days) => days < 0
    ? 'Quá hạn ${-days} ngày'
    : days == 0
        ? 'Đến hạn hôm nay'
        : 'Còn $days ngày đến hạn';

class BudgetBar extends StatelessWidget {
  const BudgetBar(
      {super.key,
      required this.label,
      required this.icon,
      required this.used,
      required this.target,
      required this.unit});
  final String label, unit;
  final IconData icon;
  final double used, target;
  @override
  Widget build(BuildContext context) {
    final color = budgetColor(used, target);
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: const Color(0xFF9B806B)),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text('${money(used, unit)} / ${money(target, unit)}', style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: target <= 0 ? 0 : (used / target).clamp(0, 1),
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.backgroundBeige,
              borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 4),
          Text(used > target ? 'Vượt ${money(used - target, unit)}' : 'Còn lại ${money(target - used, unit)}',
              style: TextStyle(fontSize: 12, color: color)),
        ]));
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
        FittedBox(child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color))),
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
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 12),
          PercentRing(value: t.principal == 0 ? 0 : t.settled / t.principal, color: color),
          const SizedBox(height: 12),
          _Metric('Tổng cộng', money(t.principal, p.currency), AppColors.textPrimary),
          const SizedBox(height: 8),
          _Metric('Còn lại', money(left, p.currency), color),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final entries = p.entries.where((e) => e.kind.isDebt && p.findWallet(e.walletId)?.currency == p.currency).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final payable = p.debt(borrowed: true), receivable = p.debt(borrowed: false);
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
        Text(money(balance, p.currency),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: balance >= 0 ? AppColors.primaryGreen : AppColors.accentRed)),
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
            subtitle: 'Ghi lại người liên quan, số tiền và ngày hẹn trả để dễ theo dõi.',
            icon: Icons.handshake_outlined),
      if (byPerson)
        for (final id in entries.map((e) => e.personId).toSet())
          Padding(padding: const EdgeInsets.only(bottom: 10), child: _PersonDebt(personId: id, entries: entries))
      else
        for (final e in entries) ...[
          EntryTile(e),
          if ((e.kind == EntryKind.lend || e.kind == EntryKind.borrow) &&
              e.dueDate != null &&
              p.debt(borrowed: e.kind == EntryKind.borrow, personId: e.personId) > 0)
            Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 10),
                child: Text(dueLabel(dateOnly(e.dueDate!).difference(dateOnly(DateTime.now())).inDays),
                    style: const TextStyle(fontSize: 12, color: AppColors.accentOrange))),
        ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
                onPressed: () => openPage(context, const AddTransactionScreen(initialKind: EntryKind.borrow)),
                icon: const Icon(Icons.south_west),
                label: const Text('Thêm đi vay'))),
        const SizedBox(width: 10),
        Expanded(
            child: FilledButton.icon(
                onPressed: () => openPage(context, const AddTransactionScreen(initialKind: EntryKind.lend)),
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
    return Panel(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const RoundIcon(Icons.person_outline),
            title: Text(p.personName(personId), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Cần thu ${money(receivable, p.currency)} • Phải trả ${money(payable, p.currency)}'),
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
                if (receivable <= 0 && payable <= 0) const Chip(label: Text('Đã tất toán')),
              ]),
              const SizedBox(height: 8),
              for (final e in own) EntryTile(e),
            ]));
  }
}
