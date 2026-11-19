import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:finance_app/features/banking/domain/vietqr.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/banking/data/repositories/bank_repository.dart';

class ReceiveQrScreen extends StatefulWidget {
  const ReceiveQrScreen({super.key, required this.walletId, this.personId, this.amount});
  final String walletId;

  final String? personId;
  final double? amount;
  @override
  State<ReceiveQrScreen> createState() => _ReceiveQrScreenState();
}

class _ReceiveQrScreenState extends State<ReceiveQrScreen> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(text: widget.amount == null ? '' : formatAmountInput(widget.amount!));
  late final note = TextEditingController(text: widget.personId == null ? '' : 'Tra no');
  String? payload, content;
  double? requested;
  PaymentRequestInfo? request;
  String? offlineReason;
  Timer? poller;
  bool busy = false;

  bool get collecting => widget.personId != null;

  @override
  void dispose() {
    poller?.cancel();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  String? amountValidator(String? v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return collecting ? 'Nhập số tiền cần thu' : null;
    final n = parseAmount(text);
    if (n == null || !n.isFinite || n <= 0) return 'Nhập số tiền lớn hơn 0';
    if (n != n.roundToDouble()) return 'Số tiền VND phải là số nguyên';
    if (n > 500000000) return 'Tối đa 500.000.000 ₫ mỗi mã QR';
    if (collecting) {
      final left = context.read<FinanceProvider>().debt(borrowed: false, personId: widget.personId, unit: 'VND');
      if (n > left) return 'Vượt số còn phải thu (${money(left)})';
    }
    return null;
  }

  Future<void> generate() async {
    if (!form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    final w = p.findWallet(widget.walletId)!;
    final value = parseAmount(amount.text);
    setState(() {
      busy = true;
      offlineReason = null;
    });
    PaymentRequestInfo? created;
    if (p.signedIn) {
      final failure = await failureOf(() async => created = await BankRepository(p).create(
          walletId: w.id,
          amount: value,
          kind: collecting ? 'collect' : 'income',
          personId: widget.personId,
          note: note.text));
      final offline = failure is ApiException && failure.isNetwork;
      if (failure != null && !offline) {
        if (mounted) {
          setState(() => busy = false);
          message(context, failure);
        }
        return;
      }
      // mất mạng vẫn hiện mã QR, chỉ không tự ghi giao dịch được
      if (offline) offlineReason = 'Mất kết nối mạng nên chưa thể tự ghi giao dịch khi tiền về.';
    } else {
      offlineReason =
          'Bạn chưa đăng nhập: hãy tự ghi giao dịch sau khi nhận tiền. Đăng nhập và kết nối SePay để ghi tự động.';
    }
    if (!mounted) return;
    final made = created;
    final text = transferContent([if (made != null) made.code, note.text].join(' '));
    setState(() {
      busy = false;
      request = made;
      requested = value;
      content = text;
      payload = buildVietQr(bin: w.bankBin!, account: w.bankAccount!, amount: value, content: text);
    });
    if (made != null) {
      poller = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
    }
  }

  Future<void> refresh() async {
    final current = request;
    if (current == null || !current.isPending) return;
    final p = context.read<FinanceProvider>();
    final next = await BankRepository(p).get(current.id).orNullOnApiError();
    if (next == null || !mounted) return;
    if (!next.isPending) poller?.cancel();
    if (next.isPaid) await p.syncNow();
    if (mounted) setState(() => request = next);
  }

  Future<void> cancel() async {
    final current = request;
    if (current == null) return;
    await attempt(context, () async {
      final next = await BankRepository(context.read<FinanceProvider>()).cancel(current.id);
      poller?.cancel();
      if (mounted) setState(() => request = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final w = p.findWallet(widget.walletId);
    if (w == null || !w.hasBank) {
      return const FinancePage(
          title: 'Nhận tiền',
          child: EmptyView(title: 'Ví chưa liên kết ngân hàng', subtitle: 'Sửa ví để thêm tài khoản ngân hàng.'));
    }
    return FinancePage(
        title: collecting ? 'Thu nợ bằng VietQR' : 'Nhận tiền bằng VietQR',
        child: payload == null ? _form(p, w) : _qr(p, w));
  }

  Widget _form(FinanceProvider p, MoneyWallet w) {
    return Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        key: form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const RoundIcon(Icons.account_balance_outlined),
                  title: Text(bankByBin(w.bankBin)?.name ?? 'Ngân hàng'),
                  subtitle: Text('${w.bankAccount} • ${w.bankHolder}\nVí: ${w.name}'))),
          const SizedBox(height: 12),
          if (collecting)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    'Thu nợ từ ${p.personName(widget.personId)} • còn phải thu ${money(p.debt(borrowed: false, personId: widget.personId, unit: 'VND'))}')),
          TextFormField(
              key: const ValueKey('qr-amount'),
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [AmountInputFormatter()],
              decoration: InputDecoration(
                  labelText: collecting ? 'Số tiền cần thu' : 'Số tiền',
                  hintText: collecting ? null : 'Để trống: người chuyển tự nhập',
                  suffixText: '₫'),
              validator: amountValidator),
          const SizedBox(height: 12),
          TextFormField(
              controller: note,
              maxLength: 15,
              decoration: const InputDecoration(
                  labelText: 'Nội dung chuyển khoản',
                  hintText: 'VD: Tien dien',
                  helperText: 'Tự chuyển thành IN HOA không dấu'),
              validator: (v) => (v ?? '').length > 15 ? 'Tối đa 15 ký tự' : null),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: busy ? null : generate,
              icon: const Icon(Icons.qr_code_2),
              label: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Đang tạo…' : 'Tạo mã QR'))),
          const SizedBox(height: 12),
          const Text(
              'Mã VietQR quét được bằng mọi ứng dụng ngân hàng tại Việt Nam. Khi đã kết nối SePay, tiền về sẽ tự được ghi vào ví.',
              style: TextStyle(fontSize: 12, height: 1.5)),
        ]));
  }

  Widget _qr(FinanceProvider p, MoneyWallet w) {
    final bank = bankByBin(w.bankBin)?.name ?? '';
    final r = request;
    final shareText = [
      'Ngân hàng: $bank',
      'Số tài khoản: ${w.bankAccount}',
      'Chủ tài khoản: ${w.bankHolder}',
      if (requested != null) 'Số tiền: ${money(requested!)}',
      if (content!.isNotEmpty) 'Nội dung: $content',
    ].join('\n');
    return ListView(padding: const EdgeInsets.all(16), children: [
      Panel(
          child: Column(children: [
        if (r?.isPaid == true) ...[
          const Icon(Icons.check_circle, size: 72, color: AppColors.primaryGreen),
          const SizedBox(height: 8),
          Text('Đã nhận ${money(r!.paidAmount ?? 0)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Giao dịch đã được ghi vào ví.', textAlign: TextAlign.center),
        ] else
          Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child:
                  QrImageView(key: const ValueKey('vietqr'), data: payload!, size: 240, backgroundColor: Colors.white)),
        const SizedBox(height: 12),
        Text(bank, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(w.bankHolder ?? ''),
        if (requested != null)
          Text(money(requested!), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ])),
      const SizedBox(height: 12),
      Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
                title: const Text('Số tài khoản'),
                subtitle: Text(w.bankAccount!),
                trailing: IconButton(
                    tooltip: 'Sao chép',
                    onPressed: () => copyText(context, 'số tài khoản', w.bankAccount!),
                    icon: const Icon(Icons.copy, size: 20))),
            if (content!.isNotEmpty)
              ListTile(
                  title: const Text('Nội dung chuyển khoản'),
                  subtitle: Text(content!),
                  trailing: IconButton(
                      tooltip: 'Sao chép',
                      onPressed: () => copyText(context, 'nội dung', content!),
                      icon: const Icon(Icons.copy, size: 20))),
          ])),
      const SizedBox(height: 12),
      if (r != null)
        Panel(
            color: AppColors.primaryGreenSurface,
            child: Row(children: [
              if (r.isPending) ...[
                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
              ],
              Expanded(
                  child: Text(
                      switch (r.status) {
                        'pending' =>
                          'Đang chờ tiền về… Giữ nguyên nội dung chuyển khoản (mã ${r.code}) để tự ghi giao dịch.',
                        'paid' => 'Đã đối soát qua SePay.',
                        'cancelled' => 'Đã hủy yêu cầu. Tiền chuyển vào sẽ không được tự ghi.',
                        _ => 'Yêu cầu đã hết hạn.',
                      },
                      style: const TextStyle(height: 1.4))),
            ]))
      else if (offlineReason != null)
        Panel(color: AppColors.primaryGreenSurface, child: Text(offlineReason!, style: const TextStyle(height: 1.4))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed: () =>
                    SharePlus.instance.share(ShareParams(text: shareText, subject: 'Thông tin chuyển khoản')),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Chia sẻ'))),
        if (r?.isPending == true) ...[
          const SizedBox(width: 10),
          Expanded(
              child:
                  TextButton.icon(onPressed: cancel, icon: const Icon(Icons.close), label: const Text('Hủy yêu cầu'))),
        ],
      ]),
    ]);
  }
}
