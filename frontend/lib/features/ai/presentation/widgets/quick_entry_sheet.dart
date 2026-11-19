import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/brand_logo.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/services/quick_parser.dart';
import 'package:finance_app/features/ai/presentation/screens/receipt_scan_screen.dart';
import 'package:finance_app/features/ai/presentation/widgets/voice_input_button.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';

Future<void> openParsedEntry(BuildContext context, ParsedEntry r, {String? photo}) async {
  final p = context.read<FinanceProvider>();
  var personId = r.personId;
  if (personId == null && r.newPersonName != null) {
    final existing = p.people.where((x) => x.name.toLowerCase() == r.newPersonName!.toLowerCase()).firstOrNull;
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

Future<void> showQuickEntry(BuildContext context) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const QuickEntrySheet());

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
                const BrandLogo.ai(size: 28),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Nhập nhanh bằng AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
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
              const Text(
                  'Gõ hoặc nói như đang nhắn tin, ứng dụng tự hiểu số tiền, loại giao dịch, danh mục, người và ngày.',
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
                        Expanded(child: Text(r.kind.label, style: const TextStyle(fontWeight: FontWeight.w700))),
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
                      _row(
                          Icons.person_outline,
                          'Đối tượng',
                          r.personId != null
                              ? p.personName(r.personId)
                              : r.newPersonName == null
                                  ? null
                                  : '${r.newPersonName} (mới)'),
                      _row(Icons.event_outlined, 'Ngày',
                          '${dayLabel(r.date)} ${TimeOfDay.fromDateTime(r.date).format(context)}'),
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
                          '${_refining ? 'đang phân tích thêm…' : 'kiểm tra lại trước khi lưu'}',
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
        Expanded(child: Text(value ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]));
}
