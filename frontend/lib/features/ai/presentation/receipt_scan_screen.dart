import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/ai/data/ai_models.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'package:finance_app/features/ai/on_device/quick_parser.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';

/// Quét hóa đơn bằng OCR.
///
/// Ảnh được nhận dạng chữ ngay trên điện thoại (Apple Vision / Google ML Kit), sau đó phân tích
/// tổng tiền, ngày, cửa hàng, các dòng hàng. Tổng tiền được kiểm tra chéo (dòng TỔNG, tiền khách
/// đưa − tiền thừa, tổng các dòng hàng) và hiện độ tin cậy; người dùng sửa được trước khi lưu.
/// Ảnh hóa đơn được đính kèm vào giao dịch.
class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({super.key, this.repository});

  /// Cho phép kiểm thử thay bằng kho AI giả lập.
  final AiRepository? repository;
  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  final pasted = TextEditingController();
  final total = TextEditingController();
  final note = TextEditingController();
  String? imagePath;
  ReceiptResult? result;
  String? error;
  bool busy = false, showPaste = false, showText = false;

  AiRepository get repo => widget.repository ?? AiRepository(context.read<FinanceProvider>());

  @override
  void dispose() {
    pasted.dispose();
    total.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ReceiptResult> Function() task) async {
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final r = await task();
      if (!mounted) return;
      setState(() {
        result = r;
        total.text = r.total == null ? '' : formatAmountInput(r.total!);
        note.text = r.note.isEmpty ? 'Hóa đơn' : r.note;
        if (r.total == null) error = 'Không tìm thấy tổng tiền — hãy nhập tay hoặc chụp lại rõ hơn.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.code == 'AI_NOT_SUPPORTED'
            ? 'Máy chủ chưa bật đọc ảnh hóa đơn. Bạn có thể dán nội dung hóa đơn bên dưới.'
            : e.message;
        showPaste = true;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Lưu ảnh vào thư mục ứng dụng để đính kèm giao dịch, rồi đọc hóa đơn.
  Future<void> pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 2200, imageQuality: 90);
    } catch (_) {
      if (mounted) message(context, 'Không mở được camera/thư viện ảnh.');
      return;
    }
    if (file == null) return;
    var path = file.path;
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/receipts');
      await dir.create(recursive: true);
      path = (await File(file.path).copy('${dir.path}/hoa_don_${DateTime.now().millisecondsSinceEpoch}.jpg')).path;
    } catch (_) {
      // giữ đường dẫn tạm của image_picker
    }
    if (!mounted) return;
    setState(() => imagePath = path);
    final r = repo;
    await _run(() => r.readReceipt(path));
  }

  Future<void> analyzeText() async {
    final r = repo;
    final text = pasted.text;
    await _run(() async {
      if (r.remoteAvailable) {
        try {
          return (await r.receiptFromText(text)).withSource('AI máy chủ', text: text);
        } on ApiException {
          // phân tích trên thiết bị
        }
      }
      return r.parseLocally(text);
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
            kind: EntryKind.expense,
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
              for (final (name, amount) in r.items)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
                      Text(money(amount, p.currency), style: const TextStyle(fontSize: 13)),
                    ])),
              if (r.items.isNotEmpty) const Divider(),
              TextField(
                  key: const ValueKey('receipt-total'),
                  controller: total,
                  keyboardType: TextInputType.number,
                  inputFormatters: [AmountInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.accentRed),
                  decoration: InputDecoration(labelText: 'Tổng cộng', suffixText: p.currency)),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Ghi chú')),
              if (p.category(r.categoryId) != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Danh mục gợi ý: ${p.category(r.categoryId)!.name}')),
              const SizedBox(height: 4),
              Text('Nguồn: ${r.source}', style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
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
                      onPressed: create, icon: const Icon(Icons.add), label: const Text('Tạo giao dịch chi'))),
            ])),
          ],
        ]));
  }
}
