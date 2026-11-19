import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/ai/presentation/widgets/insight_tile.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/services/insights.dart';
import 'package:finance_app/features/ai/presentation/screens/assistant_screen.dart';
import 'package:finance_app/features/ai/presentation/screens/smart_search_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Future<ServerInsights?>? _server;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool force = false}) {
    final repo = AiRepository(Provider.of<FinanceProvider>(context, listen: false));
    _server = !repo.remoteAvailable
        ? Future.value(null)
        : !force && repo.cachedInsights != null
            ? Future.value(repo.cachedInsights)
            : repo.insights();
  }

  void _applyBudget(FinanceProvider p, BudgetSuggestion s) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final existing = p.budgets
        .where((b) =>
            b.categoryId == s.categoryId &&
            b.walletId == null &&
            b.currency == p.currency &&
            b.month.year == month.year &&
            b.month.month == month.month)
        .firstOrNull;
    attempt(context, () {
      p.saveBudget(MoneyBudget(
          id: existing?.id ?? p.newId(),
          categoryId: s.categoryId,
          month: month,
          amount: s.amount,
          currency: p.currency));
      message(context, 'Đã đặt ngân sách ${p.category(s.categoryId)?.name}: ${money(s.amount, p.currency)}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final local = FinanceInsights(p).forecast();
    return FinancePage(
        title: 'Phân tích thông minh',
        actions: [
          IconButton(
              tooltip: 'Tìm kiếm bằng AI',
              onPressed: () => openPage(context, const SmartSearchScreen()),
              icon: const Icon(Icons.manage_search)),
          IconButton(
              tooltip: 'Hỏi trợ lý AI',
              onPressed: () => openPage(context, const AssistantScreen()),
              icon: const Icon(Icons.chat_bubble_outline))
        ],
        child: FutureBuilder<ServerInsights?>(
            future: _server,
            builder: (context, snap) {
              final server = snap.data;
              final f = server?.forecast;
              final items = FinanceInsights(p, server: f).all();
              return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _load(force: true));
                    await _server;
                  },
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Panel(
                        color: const Color(0xFFEDE3DA),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('DỰ BÁO CHI TIÊU CUỐI THÁNG',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(money(f?.projected ?? local.projected, p.currency),
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: local.target != null && (f?.projected ?? local.projected) > local.target!
                                      ? AppColors.accentRed
                                      : AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          if (f != null) ...[
                            Text('Khoảng 80%: ${money(f.lower, p.currency)} – ${money(f.upper, p.currency)}'),
                            Text('Đã chi ${money(f.spent, p.currency)} • còn ${f.daysLeft} ngày'),
                            if (f.nextMonth != null) Text('Ước tính tháng sau: ${money(f.nextMonth!, p.currency)}'),
                          ] else
                            Text(
                                'Đã chi ${money(local.spent, p.currency)} • trung bình ${money(local.dailyAverage, p.currency)}/ngày • còn ${local.daysLeft} ngày'),
                          if (local.target != null) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                                value: ((f?.projected ?? local.projected) / local.target!).clamp(0, 1),
                                minHeight: 8,
                                color: budgetColor(f?.projected ?? local.projected, local.target!),
                                backgroundColor: Colors.white,
                                borderRadius: BorderRadius.circular(8)),
                            const SizedBox(height: 6),
                            Text('So với mục tiêu tháng ${money(local.target!, p.currency)}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ])),
                    const SizedBox(height: 8),
                    Text(
                        snap.connectionState == ConnectionState.waiting
                            ? 'Đang phân tích chi tiêu…'
                            : f != null
                                ? 'Dự báo dựa trên thói quen chi tiêu theo từng ngày trong tuần và các khoản định kỳ của bạn.'
                                : 'Dự báo ước tính từ chi tiêu tháng này. Đăng nhập để có dự báo chi tiết hơn.',
                        style: const TextStyle(fontSize: 12)),
                    if (server != null && (server.anomalies.isNotEmpty || server.spikes.isNotEmpty)) ...[
                      const SectionTitle('Giao dịch bất thường'),
                      for (final s in server.spikes.take(3))
                        InsightTile(
                            insight: Insight(
                                InsightLevel.warning,
                                '${p.category(s.categoryId)?.name ?? 'Danh mục'} tăng ${s.ratio.toStringAsFixed(1)} lần',
                                '30 ngày qua ${money(s.recent, p.currency)}, trung bình ${money(s.baseline, p.currency)}/tháng.',
                                categoryId: s.categoryId)),
                      for (final a in server.anomalies.take(5))
                        if (p.entries.where((e) => e.id == a.transactionId).firstOrNull case final e?)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Panel(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                EntryTile(e),
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Icon(Icons.warning_amber_rounded,
                                          size: 16,
                                          color: a.kind == 'duplicate' ? AppColors.accentOrange : AppColors.accentRed),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(a.reasons.join(' • '),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: a.kind == 'duplicate'
                                                      ? AppColors.accentOrange
                                                      : AppColors.accentRed))),
                                    ])),
                              ]))),
                    ],
                    if (server != null && server.budgets.isNotEmpty) ...[
                      const SectionTitle('Gợi ý ngân sách tháng'),
                      Panel(
                          padding: EdgeInsets.zero,
                          child: Column(children: [
                            for (final s in server.budgets.where((s) => p.category(s.categoryId) != null))
                              ListTile(
                                  dense: true,
                                  title: Text(p.category(s.categoryId)!.name),
                                  subtitle: Text('${s.group == 'needs' ? 'Thiết yếu' : 'Mong muốn'} • ${s.note}',
                                      style: const TextStyle(fontSize: 11)),
                                  trailing: TextButton(
                                      onPressed: () => _applyBudget(p, s), child: Text(compactMoney(s.amount)))),
                          ])),
                      if (server.plan != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                'Thu nhập ~${money((server.plan!['income'] as num).toDouble(), p.currency)}/tháng • '
                                'tiết kiệm dự kiến ${money((server.plan!['savings'] as num).toDouble(), p.currency)} '
                                '(mục tiêu 20%: ${money(((server.plan!['target'] as Map)['savings'] as num).toDouble(), p.currency)})',
                                style: const TextStyle(fontSize: 12))),
                    ],
                    const SectionTitle('Điểm đáng chú ý'),
                    for (final i in items) InsightTile(insight: i),
                    if (items.isEmpty)
                      const EmptyView(
                          title: 'Chưa đủ dữ liệu',
                          subtitle: 'Ghi thêm giao dịch để AI phân tích thói quen chi tiêu của bạn.',
                          icon: Icons.auto_awesome),
                  ]));
            }));
  }
}
