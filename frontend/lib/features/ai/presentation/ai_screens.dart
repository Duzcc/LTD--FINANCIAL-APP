import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/widgets/entry_tile.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/ai/data/ai_models.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'package:finance_app/features/ai/on_device/insights.dart';
import 'package:finance_app/features/ai/on_device/local_assistant.dart';
import 'package:finance_app/features/ai/on_device/quick_parser.dart';
import 'package:finance_app/features/ai/presentation/receipt_scan_screen.dart';
import 'package:finance_app/features/ai/presentation/smart_search_screen.dart';
import 'package:finance_app/features/ai/presentation/voice_input.dart';
import 'package:finance_app/features/ledger/presentation/ledger_screen.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';

/// Mở biểu mẫu giao dịch đã điền sẵn từ kết quả AI (người dùng luôn xác nhận).
Future<void> openParsedEntry(BuildContext context, ParsedEntry r, {String? photo}) async {
  final p = context.read<FinanceProvider>();
  var personId = r.personId;
  if (personId == null && r.newPersonName != null) {
    final existing = p.people
        .where((x) => x.name.toLowerCase() == r.newPersonName!.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      personId = existing.id;
    } else {
      final person = MoneyPerson(p.newId(), r.newPersonName!, 'Bạn bè & Đồng nghiệp');
      p.savePerson(person);
      personId = person.id;
    }
  }
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddTransactionScreen(
          initialKind: r.kind,
          initialAmount: r.amount,
          initialWalletId: r.walletId,
          initialPersonId: personId,
          initialCategoryId: r.categoryId,
          initialNote: r.note,
          initialDate: r.date,
          initialPhoto: photo)));
}

/// Nhập nhanh bằng một câu tự nhiên (gõ hoặc nói). Kết quả hiện ngay bằng mô hình
/// trên thiết bị, sau đó được tinh chỉnh bằng mô hình máy chủ khi đăng nhập.
Future<void> showQuickEntry(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QuickEntrySheet());

class QuickEntrySheet extends StatefulWidget {
  const QuickEntrySheet({super.key});
  @override
  State<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<QuickEntrySheet> {
  final text = TextEditingController();
  Timer? _debounce;
  ParsedEntry? _remote;
  String _remoteFor = '';
  bool _refining = false;
  static const examples = [
    'ăn phở 45k sáng nay',
    'đổ xăng 70.000 hôm qua',
    'lương tháng 15tr',
    'cho Minh mượn 500k',
    'trả nợ Lan 1tr2',
    'cà phê với bạn 2 ly 60k',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    text.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    final repo = AiRepository(context.read<FinanceProvider>());
    _debounce?.cancel();
    if (!repo.remoteAvailable || text.text.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 650), () async {
      final query = text.text.trim();
      setState(() => _refining = true);
      final (result, remote) = await repo.parse(query);
      if (!mounted || text.text.trim() != query) return;
      setState(() {
        _refining = false;
        _remote = remote ? result : null;
        _remoteFor = query;
      });
    });
  }

  Future<void> confirm(ParsedEntry r) async {
    final nav = Navigator.of(context);
    final ctx = nav.context;
    nav.pop();
    await openParsedEntry(ctx, r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final query = text.text.trim();
    final fromServer = _remote != null && _remoteFor == query;
    final r = query.isEmpty ? null : (fromServer ? _remote! : QuickEntryParser(p).parse(query));
    return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: AppColors.primaryGreen),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Nhập nhanh bằng AI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                TextButton.icon(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      final ctx = nav.context;
                      nav.pop();
                      openPage(ctx, const ReceiptScanScreen());
                    },
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Quét hóa đơn')),
              ]),
              const SizedBox(height: 6),
              const Text('Gõ hoặc nói như đang nhắn tin, ứng dụng tự hiểu số tiền, loại giao dịch, danh mục, người và ngày.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                  key: const ValueKey('quick-entry'),
                  controller: text,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _changed(),
                  onSubmitted: (_) {
                    if (r?.amount != null) confirm(r!);
                  },
                  decoration: InputDecoration(
                      hintText: 'Ví dụ: ăn trưa 50k với đồng nghiệp',
                      prefixIcon: const Icon(Icons.edit_note),
                      suffixIcon: VoiceInputButton(onText: (v) {
                        text.text = v;
                        text.selection = TextSelection.collapsed(offset: v.length);
                        _changed();
                      }))),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in examples)
                  ActionChip(
                      label: Text(e, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        text.text = e;
                        _changed();
                      }),
              ]),
              if (r != null) ...[
                const SizedBox(height: 16),
                Panel(
                    color: AppColors.primaryGreenSurface,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            child: Text(r.kind.label,
                                style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text(
                            r.amount == null
                                ? 'Chưa thấy số tiền'
                                : money(r.amount!, p.findWallet(r.walletId)?.currency ?? 'VND'),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: r.kind.sign > 0 ? AppColors.primaryGreen : AppColors.accentRed)),
                      ]),
                      const SizedBox(height: 8),
                      _row(Icons.category_outlined, 'Danh mục', p.category(r.categoryId)?.name),
                      _row(Icons.account_balance_wallet_outlined, 'Ví', p.findWallet(r.walletId)?.name),
                      _row(Icons.person_outline, 'Đối tượng',
                          r.personId != null ? p.personName(r.personId) : r.newPersonName == null ? null : '${r.newPersonName} (mới)'),
                      _row(Icons.event_outlined, 'Ngày', '${dayLabel(r.date)} ${TimeOfDay.fromDateTime(r.date).format(context)}'),
                      _row(Icons.notes, 'Ghi chú', r.note.isEmpty ? null : r.note),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                          value: r.confidence,
                          minHeight: 4,
                          color: AppColors.primaryGreen,
                          backgroundColor: Colors.white,
                          borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 4),
                      Text(
                          'Độ tin cậy ${(r.confidence * 100).round()}% • '
                          '${_refining ? 'đang hỏi AI máy chủ…' : fromServer ? 'AI máy chủ' : 'AI trên thiết bị'}'
                          ' • kiểm tra lại trước khi lưu',
                          style: const TextStyle(fontSize: 11)),
                    ])),
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: r.amount == null ? null : () => confirm(r),
                        icon: const Icon(Icons.check),
                        label: const Text('Tiếp tục'))),
              ],
            ])));
  }

  Widget _row(IconData icon, String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
            child: Text(value ?? '—',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]));
}

/// Phân tích thông minh: ưu tiên mô hình máy chủ (dự báo có khoảng tin cậy,
/// phát hiện bất thường, gợi ý ngân sách); luôn kèm phân tích trên thiết bị.
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
    try {
      p.saveBudget(MoneyBudget(
          id: existing?.id ?? p.newId(),
          categoryId: s.categoryId,
          month: month,
          amount: s.amount,
          currency: p.currency));
      message(context, 'Đã đặt ngân sách ${p.category(s.categoryId)?.name}: ${money(s.amount, p.currency)}');
    } on ArgumentError catch (e) {
      message(context, e.message);
    }
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
              // Các điểm đáng chú ý dùng cùng dự báo với thẻ phía trên
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
                            if (f.nextMonth != null)
                              Text('Ước tính tháng sau: ${money(f.nextMonth!, p.currency)}'),
                          ] else
                            Text('Đã chi ${money(local.spent, p.currency)} • trung bình ${money(local.dailyAverage, p.currency)}/ngày • còn ${local.daysLeft} ngày'),
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
                            ? 'Đang lấy phân tích từ AI máy chủ…'
                            : f != null
                                ? 'Mô hình máy chủ: hồ sơ chi theo thứ trong tuần + Holt, tách khoản định kỳ (sai số kiểm định ~19%).'
                                : 'Phân tích chạy trên thiết bị (đăng nhập để dùng mô hình máy chủ chính xác hơn).',
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
                                    child: Text('⚠ ${a.reasons.join(' • ')}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: a.kind == 'duplicate' ? AppColors.accentOrange : AppColors.accentRed))),
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
                                  subtitle: Text(
                                      '${s.group == 'needs' ? 'Thiết yếu' : 'Mong muốn'} • ${s.note}',
                                      style: const TextStyle(fontSize: 11)),
                                  trailing: TextButton(
                                      onPressed: () => _applyBudget(p, s),
                                      child: Text(compactMoney(s.amount)))),
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

class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.insight});
  final Insight insight;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.level) {
      InsightLevel.danger => (Icons.error_outline, AppColors.accentRed),
      InsightLevel.warning => (Icons.warning_amber_rounded, AppColors.accentYellow),
      InsightLevel.good => (Icons.verified_outlined, AppColors.primaryGreen),
      InsightLevel.info => (Icons.lightbulb_outline, const Color(0xFF8D7564)),
    };
    final isSubscription = insight.title.startsWith('Có vẻ là khoản cố định');
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
                tileColor: Colors.transparent,
                leading: RoundIcon(icon, color: color),
                title: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(insight.detail, style: const TextStyle(height: 1.4)),
                onTap: insight.categoryId != null
                    ? () => openPage(context, LedgerScreen(initialCategoryId: insight.categoryId))
                    : isSubscription
                        ? () => openPage(context, const RecurringScreen())
                        : null)));
  }
}

class ChatMessage {
  const ChatMessage(this.fromUser, this.text, {this.source, this.actions = const []});
  final bool fromUser;
  final String text;
  final String? source;
  final List<AssistantAction> actions;
}

/// Trợ lý tài chính: mô hình ngôn ngữ ở máy chủ gọi công cụ trên dữ liệu thật
/// (khi đăng nhập), ngược lại dùng trợ lý chạy trên thiết bị. Trợ lý chỉ
/// *đề xuất* ghi giao dịch / đặt ngân sách — người dùng bấm xác nhận.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[
    const ChatMessage(false,
        'Xin chào! Mình là trợ lý tài chính. Bạn có thể hỏi về chi tiêu, ngân sách, công nợ, dự báo, giao dịch bất thường, hoặc nhờ mình ghi giúp một khoản chi.',
        source: 'Trợ lý')
  ];
  final done = <AssistantAction>{};
  bool busy = false;
  static const _sources = {
    'ai-service': 'AI máy chủ',
    'llm': 'AI máy chủ (LLM)',
    'rules': 'AI máy chủ',
    'device': 'AI trên thiết bị',
  };

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || busy) return;
    final p = context.read<FinanceProvider>();
    setState(() {
      messages.add(ChatMessage(true, q));
      busy = true;
      input.clear();
    });
    final history = [
      for (final m in messages.skip(1).toList().reversed.take(10).toList().reversed)
        {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
    ];
    final r = await AiRepository(p).chat(history);
    if (!mounted) return;
    setState(() {
      messages.add(ChatMessage(false, r.reply, source: _sources[r.source] ?? 'AI máy chủ', actions: r.actions));
      busy = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (scroll.hasClients) {
      scroll.animateTo(scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> run(AssistantAction a) async {
    final p = context.read<FinanceProvider>();
    final d = a.data;
    if (a.type == 'create_transaction') {
      await openParsedEntry(
          context,
          ParsedEntry(
              kind: kindFromName(d['kind'] as String?),
              amount: (d['amount'] as num?)?.toDouble(),
              date: DateTime.tryParse('${d['date']}')?.toLocal() ?? DateTime.now(),
              note: '${d['note'] ?? ''}',
              categoryId: p.category(d['categoryId'] as String?) == null ? null : d['categoryId'] as String?,
              personId: d['personId'] as String?,
              newPersonName: d['newPersonName'] as String?,
              walletId: p.findWallet(d['walletId'] as String?) == null ? null : d['walletId'] as String?));
      if (!mounted) return;
    } else if (a.type == 'set_budget') {
      final month = DateTime.tryParse('${d['month']}') ?? DateTime.now();
      final m = DateTime(month.year, month.month);
      final existing = p.budgets
          .where((b) => b.categoryId == d['categoryId'] && b.walletId == null && b.currency == p.currency && b.month == m)
          .firstOrNull;
      try {
        p.saveBudget(MoneyBudget(
            id: existing?.id ?? p.newId(),
            categoryId: d['categoryId'] as String?,
            month: m,
            amount: (d['amount'] as num).toDouble(),
            currency: p.currency));
        message(context, 'Đã đặt ngân sách.');
      } on ArgumentError catch (e) {
        message(context, e.message);
        return;
      }
    }
    setState(() => done.add(a));
  }

  Widget _actionCard(FinanceProvider p, AssistantAction a) {
    final d = a.data;
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final title = a.type == 'set_budget'
        ? 'Đặt ngân sách ${p.category(d['categoryId'] as String?)?.name ?? ''}: ${money(amount, p.currency)}'
        : '${kindFromName(d['kind'] as String?).label} ${money(amount, p.currency)}'
            '${p.category(d['categoryId'] as String?) != null ? ' • ${p.category(d['categoryId'] as String?)!.name}' : ''}';
    final isDone = done.contains(a);
    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.primaryGreenSurface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.task_alt, size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton(onPressed: isDone ? null : () => run(a), child: Text(isDone ? 'Đã xong' : 'Xác nhận')),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return FinancePage(
        title: 'Trợ lý AI',
        bottom: Row(children: [
          Expanded(
              child: TextField(
                  key: const ValueKey('assistant-input'),
                  controller: input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: send,
                  decoration: InputDecoration(
                      hintText: 'Hỏi về tài chính của bạn…',
                      suffixIcon: VoiceInputButton(
                          onText: (v) => input.text = v, onDone: () => send(input.text))))),
          const SizedBox(width: 8),
          IconButton.filled(
              tooltip: 'Gửi', onPressed: busy ? null : () => send(input.text), icon: const Icon(Icons.send)),
        ]),
        child: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          for (final m in messages)
            Align(
                alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .85),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: m.fromUser ? AppColors.primaryGreen : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: m.fromUser ? null : Border.all(color: AppColors.divider)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.text,
                          style: TextStyle(height: 1.45, color: m.fromUser ? Colors.white : AppColors.textPrimary)),
                      for (final a in m.actions) _actionCard(p, a),
                      if (m.source != null) ...[
                        const SizedBox(height: 4),
                        Text(m.source!, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
                      ],
                    ]))),
          if (busy) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          if (messages.length <= 1)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in [...LocalAssistant.suggestions, 'Có giao dịch nào bất thường không?', 'Gợi ý ngân sách cho mình'])
                ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => send(s)),
            ]),
          const SizedBox(height: 8),
          const Text(
              'Khi đăng nhập, câu hỏi được gửi tới máy chủ của bạn; trợ lý chỉ đọc số liệu cần thiết qua công cụ, không gửi mật khẩu hay thông tin đăng nhập.',
              style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ]));
  }
}
