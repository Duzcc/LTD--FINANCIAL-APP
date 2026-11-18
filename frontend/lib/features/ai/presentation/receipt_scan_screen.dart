import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/core/widgets/photo_picker.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/services/quick_parser.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';

class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({super.key, this.repository});

  final AiRepository? repository;
  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> with BusyState {
  final pasted = TextEditingController();
  final total = TextEditingController();
  final note = TextEditingController();
  String? imagePath;
  ReceiptResult? result;
  bool showPaste = false, showText = false;

  AiRepository get repo => widget.repository ?? AiRepository(context.read<FinanceProvider>());

  @override
  void dispose() {
    pasted.dispose();
    total.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ReceiptResult> Function() task) async {
    setState(() => result = null);
    ReceiptResult? read;
    final failure = await runBusy(() async => read = await task());
    if (!mounted) return;
    final r = read;
    if (r == null) {
      setState(() {
        if (failure is ApiException && failure.code == 'AI_NOT_SUPPORTED') {
          error = 'Chưa đọc được ảnh hóa đơn. Bạn có thể dán nội dung hóa đơn bên dưới.';
        }
        showPaste = true;
      });
      return;
    }
    setState(() {
      result = r;
      total.text = r.total == null ? '' : formatAmountInput(r.total!);
      note.text = r.note.isEmpty ? 'Hóa đơn' : r.note;
      if (r.total == null) error = 'Không tìm thấy tổng tiền — hãy nhập tay hoặc chụp lại rõ hơn.';
    });
  }

  Future<void> pick(ImageSource source) async {
    final path = await choosePhoto(context, source);
    if (path == null || !mounted) return;
    setState(() => imagePath = path);
    await _run(() => repo.readReceipt(path));
  }

  Future<void> analyzeText() async {
    final r = repo;
    final text = pasted.text;
    await _run(() async {
      final remote = r.remoteAvailable ? await r.receiptFromText(text).orNullOnApiError() : null;
      return remote?.withSource('Trợ lý AI', text: text) ?? r.parseLocally(text);
    });
  }

  Future<void> create() async {
    final r = result;
    final amount = parseAmount(total.text);
    if (r == null || amount == null || amount <= 0) {
      message(context, 'Nhập tổng tiền hợp lệ.');
      return;
    }
    final p = context.read<FinanceProvider>();
    final now = DateTime.now();
    final d = r.date;
    final date = d == null || DateUtils.isSameDay(d, now) ? now : DateTime(d.year, d.month, d.day, d.hour == 0 ? 12 : d.hour, d.minute);
    await openParsedEntry(
        context,
        ParsedEntry(
            kind: r.kind,
            amount: amount,
            date: date,
            note: note.text.trim().isEmpty ? 'Hóa đơn' : note.text.trim(),
            categoryId: p.category(r.categoryId) == null ? null : r.categoryId,
            walletId: p.wallets.firstOrNull?.id,
            confidence: r.confidence),
        photo: imagePath);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final r = result;
    final level = r == null
        ? null
        : r.confidence >= 0.8
            ? (AppColors.primaryGreen, 'Tin cậy cao')
            : r.confidence >= 0.55
                ? (AppColors.accentYellow, 'Nên kiểm tra lại')
                : (AppColors.accentRed, 'Độ tin cậy thấp — kiểm tra kỹ');
    return FinancePage(
        title: 'Quét hóa đơn',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              color: AppColors.primaryGreenSurface,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Chụp thẳng, đủ sáng, thấy rõ dòng TỔNG CỘNG.', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('Chữ được nhận dạng ngay trên điện thoại; ảnh được đính kèm vào giao dịch.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: FilledButton.icon(
                          onPressed: busy ? null : () => pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Chụp ảnh'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: busy ? null : () => pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Chọn ảnh'))),
                ]),
                TextButton(
                    onPressed: () => setState(() => showPaste = !showPaste),
                    child: const Text('Hoặc dán nội dung hóa đơn')),
              ])),
          if (showPaste) ...[
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('receipt-text'),
                controller: pasted,
                minLines: 4,
                maxLines: 10,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Dán văn bản hóa đơn')),
            const SizedBox(height: 8),
            FilledButton.tonal(
                onPressed: busy || pasted.text.trim().isEmpty ? null : analyzeText,
                child: const Text('Phân tích văn bản')),
          ],
          if (imagePath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(imagePath!), height: 220, fit: BoxFit.cover, width: double.infinity,
                    cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          ],
          if (busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Đang đọc hóa đơn…', style: TextStyle(fontSize: 12)),
                ])),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: AppColors.accentRed))),
          if (r != null && level != null) ...[
            const SectionTitle('Kết quả'),
            Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(r.merchant ?? 'Cửa hàng không rõ',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: level.$1.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                    child: Text('${level.$2} • ${(r.confidence * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: level.$1, fontWeight: FontWeight.w600))),
              ]),
              if (r.date != null) Text('Ngày ${dayLabel(r.date!)}'),
              if (r.checks.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Tổng tiền khớp với: ${r.checks.join(', ')}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
              const Divider(),
              for (final i in r.items)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              i.quantity == null || i.quantity == 1 ? i.name : '${i.name} × ${i.quantity!.round()}',
                              style: const TextStyle(fontSize: 13))),
                      Text(money(i.amount, p.currency), style: const TextStyle(fontSize: 13)),
                    ])),
              if (r.items.isNotEmpty) const Divider(),
              SegmentedButton<EntryKind>(
                  segments: const [
                    ButtonSegment(value: EntryKind.expense, label: Text('Khoản chi'), icon: Icon(Icons.arrow_upward)),
                    ButtonSegment(value: EntryKind.income, label: Text('Khoản thu'), icon: Icon(Icons.arrow_downward)),
                  ],
                  selected: {r.kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => result = repo.categorize(r, s.first))),
              const SizedBox(height: 12),
              TextField(
                  key: const ValueKey('receipt-total'),
                  controller: total,
                  keyboardType: TextInputType.number,
                  inputFormatters: [AmountInputFormatter()],
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: r.kind == EntryKind.income ? AppColors.primaryGreen : AppColors.accentRed),
                  decoration: InputDecoration(labelText: 'Tổng cộng', suffixText: p.currency)),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Ghi chú')),
              if (p.category(r.categoryId) != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Danh mục gợi ý: ${p.category(r.categoryId)!.name}')),
              if (r.rawText.isNotEmpty)
                TextButton(
                    onPressed: () => setState(() => showText = !showText),
                    child: Text(showText ? 'Ẩn văn bản nhận dạng' : 'Xem văn bản nhận dạng')),
              if (showText)
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: AppColors.backgroundBeige,
                    child: Text(r.rawText, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                      onPressed: create, icon: const Icon(Icons.add), label: Text(r.kind == EntryKind.income ? 'Tạo giao dịch thu' : 'Tạo giao dịch chi'))),
            ])),
          ],
        ]));
  }
}
