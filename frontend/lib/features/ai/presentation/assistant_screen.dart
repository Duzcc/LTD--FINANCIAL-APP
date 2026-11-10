import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/widgets/brand_logo.dart';
import 'package:finance_app/app/notification_service.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/core/widgets/photo_picker.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/services/quick_parser.dart';
import 'package:finance_app/features/ai/domain/services/spending_coach.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/ai/presentation/voice_input.dart';
import 'package:finance_app/features/ai/presentation/widgets/receipt_review_card.dart';
import 'package:finance_app/features/ai/presentation/widgets/reminders_sheet.dart';

class ChatMessage {
  const ChatMessage(this.fromUser, this.text, {this.source, this.actions = const [], this.imagePath, this.receipt});
  final bool fromUser;
  final String text;
  final String? source, imagePath;
  final List<AssistantAction> actions;
  final ReceiptResult? receipt;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.repository});
  final AiRepository? repository;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final messages = <ChatMessage>[];
  final done = <AssistantAction>{};
  final savedReceipts = <ChatMessage>{};
  bool busy = false;
  static const _sources = {
    'ai-service': 'AI máy chủ',
    'llm': 'AI máy chủ (LLM)',
    'rules': 'AI máy chủ',
    'device': 'AI trên thiết bị',
  };
  static const _starters = [
    'Hôm nay tôi được chi bao nhiêu?',
    'Tháng này tôi đã chi bao nhiêu?',
    'Tìm các khoản ăn uống tuần này',
    'Nhắc tôi đóng tiền điện ngày 15 hàng tháng',
    'Gợi ý ngân sách cho mình',
    'Có giao dịch nào bất thường không?',
  ];

  AiRepository get repo => widget.repository ?? AiRepository(context.read<FinanceProvider>());

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _add(ChatMessage m) {
    setState(() => messages.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || busy) return;
    final r = repo;
    input.clear();
    _add(ChatMessage(true, q));
    setState(() => busy = true);
    final history = [
      for (final m in messages
          .where((m) => m.receipt == null && m.imagePath == null)
          .toList()
          .reversed
          .take(10)
          .toList()
          .reversed)
        {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
    ];
    final reply = await r.chat(history);
    if (!mounted) return;
    setState(() => busy = false);
    _add(ChatMessage(false, reply.reply, source: _sources[reply.source] ?? 'AI máy chủ', actions: reply.actions));
  }

  Future<void> attachReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        useSafeArea: true,
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(
                  title: Text('Gửi hóa đơn', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Chụp thẳng, đủ sáng, thấy rõ các dòng hàng và dòng tổng.')),
              ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Chụp hóa đơn'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Chọn ảnh từ thư viện'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery)),
              const SizedBox(height: 8),
            ]));
    if (source == null || !mounted) return;
    final path = await choosePhoto(context, source);
    if (path == null || !mounted) return;
    await readReceipt(repo, path);
  }

  Future<void> readReceipt(AiRepository r, String path) async {
    _add(ChatMessage(true, 'Hóa đơn', imagePath: path));
    setState(() => busy = true);
    ReceiptResult? result;
    final failure = await failureOf(() async => result = await r.readReceipt(path));
    if (!mounted) return;
    setState(() => busy = false);
    final read = result;
    if (read != null) {
      _add(ChatMessage(false, _receiptSummary(read), source: read.source, receipt: read, imagePath: path));
    } else {
      _add(ChatMessage(false, '${errorText(failure!)} Bạn có thể chụp lại hoặc nhập tay.', source: 'Trợ lý'));
    }
  }

  String _receiptSummary(ReceiptResult r) {
    final p = context.read<FinanceProvider>();
    final parts = [
      'Mình đọc được hóa đơn${r.merchant == null ? '' : ' ${r.merchant}'}',
      if (r.date != null)
        'ngày ${dayLabel(r.date!)}${r.date!.hour + r.date!.minute > 0 ? ' lúc ${r.date!.hour}:${r.date!.minute.toString().padLeft(2, '0')}' : ''}',
      if (r.items.isNotEmpty) '${r.items.length} món',
      if (r.total != null) 'tổng ${money(r.total!, p.currency)}',
    ];
    final kind = r.kind == EntryKind.income ? 'Mình xếp vào khoản thu. ' : '';
    return '${parts.join(', ')}. $kind'
        '${r.total == null ? 'Mình chưa thấy tổng tiền, bạn nhập giúp nhé.' : 'Kiểm tra loại thu/chi và danh mục rồi bấm Ghi.'}';
  }

  void _receiptSaved(ChatMessage m, List<MoneyEntry> entries) {
    final p = context.read<FinanceProvider>();
    setState(() => savedReceipts.add(m));
    final names = {for (final e in entries) p.category(e.categoryId)?.name ?? ''}.where((n) => n.isNotEmpty).join(', ');
    final income = entries.first.kind == EntryKind.income;
    final warnings = income ? const <String>[] : SpendingCoach(p).budgetWarnings({for (final e in entries) e.categoryId!});
    _add(ChatMessage(
        false,
        [
          'Đã ghi ${entries.length} ${income ? 'khoản thu' : 'khoản chi'} vào $names, tổng ${money(entries.fold(0.0, (s, e) => s + e.amount), p.currency)}.',
          ...warnings,
        ].join('\n'),
        source: 'Trợ lý',
        actions: [
          AssistantAction('show_transactions', {
            'ids': [for (final e in entries) e.id]
          })
        ]));
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
          .where(
              (b) => b.categoryId == d['categoryId'] && b.walletId == null && b.currency == p.currency && b.month == m)
          .firstOrNull;
      final saved = await attempt(context, () {
        p.saveBudget(MoneyBudget(
            id: existing?.id ?? p.newId(),
            categoryId: d['categoryId'] as String?,
            month: m,
            amount: (d['amount'] as num).toDouble(),
            currency: p.currency));
        message(context, 'Đã đặt ngân sách.');
      });
      if (!saved || !mounted) return;
    } else if (a.type == 'create_reminder') {
      final reminder = SpendingReminder(
          id: p.newId(),
          title: '${d['title']}',
          at: DateTime.parse('${d['at']}'),
          repeat: ReminderRepeat.values.byName('${d['repeat']}'));
      p.saveReminder(reminder);
      final granted = await NotificationService.instance.requestPermission();
      if (!mounted) return;
      message(
          context,
          granted
              ? 'Đã đặt nhắc nhở lúc ${reminderWhen(reminder.at)}.'
              : 'Đã lưu nhắc nhở. Hãy cho phép thông báo trong Cài đặt để nhận nhắc.');
    }
    setState(() => done.add(a));
  }

  String _actionTitle(FinanceProvider p, AssistantAction a) {
    final d = a.data;
    final amount = (d['amount'] as num?)?.toDouble() ?? 0;
    final category = p.category(d['categoryId'] as String?);
    return switch (a.type) {
      'set_budget' => 'Đặt ngân sách ${category?.name ?? ''}: ${money(amount, p.currency)}',
      'create_reminder' => 'Nhắc "${d['title']}" lúc ${reminderWhen(DateTime.parse('${d['at']}'))}'
          '${d['repeat'] == 'none' ? '' : ' • ${ReminderRepeat.values.byName('${d['repeat']}').label.toLowerCase()}'}',
      _ => '${kindFromName(d['kind'] as String?).label} ${money(amount, p.currency)}'
          '${category != null ? ' • ${category.name}' : ''}',
    };
  }

  Widget _actionCard(FinanceProvider p, AssistantAction a) {
    final isDone = done.contains(a);
    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.primaryGreenSurface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(a.type == 'create_reminder' ? Icons.notifications_active_outlined : Icons.task_alt,
              size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(_actionTitle(p, a), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          TextButton(onPressed: isDone ? null : () => run(a), child: Text(isDone ? 'Đã xong' : 'Xác nhận')),
        ]));
  }

  Widget _transactions(FinanceProvider p, AssistantAction a) {
    final ids = [for (final id in (a.data['ids'] as List? ?? const [])) '$id'];
    final byId = {for (final e in p.entries) e.id: e};
    final found = [for (final id in ids) byId[id]].whereType<MoneyEntry>().toList();
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(children: [
          for (final e in found.take(8)) EntryTile(e),
          if (found.length > 8) Text('và ${found.length - 8} giao dịch khác', style: const TextStyle(fontSize: 12)),
        ]));
  }

  /// Tin nhắn của trợ lý có ảnh đại diện bên trái; tin của người dùng giữ nguyên.
  Widget _withAvatar(ChatMessage m, Widget bubble) => m.fromUser
      ? bubble
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: BrandLogo.aiAvatar(size: 30)),
          Expanded(child: bubble),
        ]);

  Widget _bubble(FinanceProvider p, ChatMessage m) {
    final wide = m.receipt != null || m.actions.any((a) => a.type == 'show_transactions');
    return Align(
        alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (wide ? 1 : .85)),
            margin: const EdgeInsets.only(bottom: 10),
            child:
                Column(crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              if (m.fromUser && m.imagePath != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(m.imagePath!),
                        width: 180,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 180,
                            height: 80,
                            color: AppColors.primaryGreen,
                            alignment: Alignment.center,
                            child: const Icon(Icons.receipt_long, color: Colors.white))))
              else
                Material(
                    color: m.fromUser ? AppColors.primaryGreen : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: m.fromUser ? BorderSide.none : const BorderSide(color: AppColors.divider)),
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.text,
                              style: TextStyle(height: 1.45, color: m.fromUser ? Colors.white : AppColors.textPrimary)),
                          for (final a in m.actions)
                            if (a.type == 'show_transactions') _transactions(p, a) else _actionCard(p, a),
                          if (m.source != null) ...[
                            const SizedBox(height: 4),
                            Text(m.source!, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
                          ],
                        ]))),
              if (m.receipt != null) ...[
                const SizedBox(height: 8),
                ReceiptReviewCard(
                    receipt: m.receipt!,
                    imagePath: m.imagePath,
                    saved: savedReceipts.contains(m),
                    onSaved: (entries) => _receiptSaved(m, entries)),
              ],
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final greeting =
        ChatMessage(false, SpendingCoach(p, reminders: p.reminders).greeting(p.displayName), source: 'Trợ lý');
    return FinancePage(
        title: 'Trợ lý AI',
        actions: [
          IconButton(
              tooltip: 'Nhắc nhở',
              onPressed: () => showReminders(context),
              icon: Badge(
                  isLabelVisible: p.reminders.any((r) => !r.expired(DateTime.now())),
                  label: Text('${p.reminders.where((r) => !r.expired(DateTime.now())).length}'),
                  child: const Icon(Icons.notifications_none))),
          IconButton(
              tooltip: 'Phân tích thông minh',
              onPressed: () => openPage(context, const InsightsScreen()),
              icon: const Icon(Icons.insights_outlined)),
          if (messages.isNotEmpty)
            IconButton(
                tooltip: 'Cuộc trò chuyện mới',
                onPressed: busy
                    ? null
                    : () => setState(() {
                          messages.clear();
                          done.clear();
                          savedReceipts.clear();
                        }),
                icon: const Icon(Icons.refresh)),
        ],
        bottom: Row(children: [
          IconButton(
              key: const ValueKey('assistant-attach'),
              tooltip: 'Gửi ảnh hóa đơn',
              onPressed: busy ? null : attachReceipt,
              icon: const Icon(Icons.document_scanner_outlined)),
          Expanded(
              child: TextField(
                  key: const ValueKey('assistant-input'),
                  controller: input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: send,
                  decoration: InputDecoration(
                      hintText: 'Hỏi, nhờ ghi, đặt nhắc…',
                      suffixIcon: VoiceInputButton(onText: (v) => input.text = v, onDone: () => send(input.text))))),
          const SizedBox(width: 8),
          IconButton.filled(
              tooltip: 'Gửi', onPressed: busy ? null : () => send(input.text), icon: const Icon(Icons.send)),
        ]),
        child: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          if (messages.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 16),
                child: Center(child: BrandLogo.ai(size: 72))),
          _withAvatar(greeting, _bubble(p, greeting)),
          for (final m in messages) _withAvatar(m, _bubble(p, m)),
          if (busy)
            const Padding(
                padding: EdgeInsets.all(8),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Đang xử lý…', style: TextStyle(fontSize: 12)),
                ])),
          if (messages.isEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              ActionChip(
                  avatar: const Icon(Icons.document_scanner_outlined, size: 16),
                  label: const Text('Quét hóa đơn', style: TextStyle(fontSize: 12)),
                  onPressed: attachReceipt),
              for (final s in _starters)
                ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => send(s)),
            ]),
            const SizedBox(height: 12),
            const Text(
                'Khi đăng nhập, câu hỏi được gửi tới máy chủ của bạn; trợ lý chỉ đọc số liệu cần thiết, '
                'không gửi mật khẩu hay thông tin đăng nhập. Ảnh hóa đơn được nhận dạng chữ ngay trên điện thoại.',
                style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
          ],
        ]));
  }
}
