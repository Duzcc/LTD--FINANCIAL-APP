import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/banking/domain/vietqr.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';
import 'package:finance_app/features/banking/data/repositories/bank_repository.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';

class SepayScreen extends StatefulWidget {
  const SepayScreen({super.key});
  @override
  State<SepayScreen> createState() => _SepayScreenState();
}

class _SepayScreenState extends State<SepayScreen> with BusyState {
  SepayStatus? status;
  List<PaymentRequestInfo> requests = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = context.read<FinanceProvider>();
    if (!p.signedIn) return;
    await runBusy(() async {
      final repo = BankRepository(p);
      final s = await repo.sepay();
      final list = await repo.list();
      if (mounted) {
        setState(() {
          status = s;
          requests = list;
        });
      }
    });
  }

  Future<void> createKey() async {
    if (status?.connected == true &&
        !await confirmAction(context,
            title: 'Tạo khóa mới?',
            content: 'Khóa cũ sẽ ngừng hoạt động. Bạn cần dán khóa mới vào cấu hình webhook trên SePay.',
            confirm: 'Tạo khóa mới')) {
      return;
    }
    if (!mounted) return;
    await attempt(context, () async {
      final s = await BankRepository(context.read<FinanceProvider>()).createKey();
      if (mounted) setState(() => status = s);
    });
  }

  Future<void> revoke() async {
    if (!await confirmAction(context,
        title: 'Tắt webhook SePay?',
        content: status?.pollingEnabled == true
            ? 'Tiền về vẫn được tự ghi nhận, chỉ chậm hơn vài giây.'
            : 'Tiền chuyển vào sẽ không còn được tự ghi thành giao dịch.',
        confirm: 'Tắt webhook',
        danger: true)) {
      return;
    }
    if (!mounted) return;
    await attempt(context, () async {
      await BankRepository(context.read<FinanceProvider>()).revokeKey();
      await load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final linked = p.wallets.where((w) => w.hasBank).toList();
    final s = status;
    return FinancePage(
        title: 'Kết nối ngân hàng',
        child: RefreshIndicator(
            onRefresh: load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Tài khoản đã liên kết', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final w in linked)
                Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                        leading: const RoundIcon(Icons.account_balance_outlined),
                        title: Text(w.name),
                        subtitle: Text('${bankByBin(w.bankBin)?.name} • ${w.bankAccount}\n${w.bankHolder}'),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: () => openPage(context, CreateWalletScreen(wallet: w)))),
              if (linked.isEmpty)
                const Text(
                    'Chưa có ví nào liên kết ngân hàng. Mở một ví VND → Chỉnh sửa → "Liên kết tài khoản ngân hàng".',
                    style: TextStyle(height: 1.5)),
              const SizedBox(height: 20),
              const Text('Tự ghi giao dịch qua SePay', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (!p.signedIn)
                const Text(
                    'Đăng nhập để tự ghi giao dịch khi có tiền chuyển đến. Khi chưa đăng nhập bạn vẫn tạo được mã VietQR để nhận tiền.',
                    style: TextStyle(height: 1.5))
              else if (busy && s == null)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                Text(error!, style: const TextStyle(color: AppColors.accentRed))
              else if (s != null) ...[
                if (s.pollingEnabled) ...[
                  Panel(
                      color: AppColors.primaryGreenSurface,
                      child: Row(children: [
                        const Icon(Icons.sync, color: AppColors.primaryGreen),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(
                                'Đã bật tự ghi nhận tiền về: khi có mã QR đang chờ, app kiểm tra mỗi ${s.pollSeconds} giây. Không cần cài thêm webhook.',
                                style: const TextStyle(height: 1.4))),
                      ])),
                  const SizedBox(height: 12),
                  const Text('Webhook (tùy chọn, báo nhanh hơn)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      ListTile(
                          leading: Icon(s.connected ? Icons.link : Icons.link_off,
                              color: s.connected ? AppColors.primaryGreen : AppColors.textSecondary),
                          title: Text(s.connected ? 'Đã tạo khóa webhook' : 'Webhook chưa bật'),
                          subtitle: s.keyHint == null ? null : Text('Khóa kết thúc bằng …${s.keyHint}')),
                      ListTile(
                          title: const Text('URL webhook'),
                          subtitle: Text(s.webhookUrl),
                          trailing: IconButton(
                              tooltip: 'Sao chép',
                              onPressed: () => copyText(context, 'URL webhook', s.webhookUrl),
                              icon: const Icon(Icons.copy, size: 20))),
                      if (s.apiKey != null)
                        ListTile(
                            tileColor: AppColors.primaryGreenSurface,
                            title: const Text('API Key (chỉ hiện một lần)'),
                            subtitle: SelectableText(s.apiKey!),
                            trailing: IconButton(
                                tooltip: 'Sao chép',
                                onPressed: () => copyText(context, 'API Key', s.apiKey!),
                                icon: const Icon(Icons.copy, size: 20))),
                    ])),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: createKey, child: Text(s.connected ? 'Tạo khóa mới' : 'Tạo khóa webhook'))),
                  if (s.connected) ...[
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(onPressed: revoke, child: const Text('Tắt webhook'))),
                  ],
                ]),
                const SizedBox(height: 16),
                const Panel(
                    child: Text(
                        'Cách bật webhook:\n'
                        '1. Đăng ký tại my.sepay.vn và thêm tài khoản ngân hàng của bạn (giống số tài khoản đã liên kết với ví).\n'
                        '2. Vào Tích hợp → Webhooks → Thêm webhook: sự kiện "Có tiền vào", dán URL webhook ở trên.\n'
                        '3. Kiểu chứng thực: API Key, dán API Key ở trên.\n'
                        '\n'
                        'Khi khách quét mã VietQR của bạn và giữ nguyên nội dung chuyển khoản (có mã LTD…), giao dịch sẽ tự ghi vào ví.',
                        style: TextStyle(height: 1.5))),
                if (requests.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Yêu cầu nhận tiền gần đây', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final r in requests.take(20))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(switch (r.status) {
                          'paid' => Icons.check_circle_outline,
                          'pending' => Icons.schedule,
                          _ => Icons.block,
                        }),
                        title: Text('${r.code} • ${r.amount == null ? 'Tùy số tiền' : money(r.amount!)}'),
                        subtitle: Text([
                          switch (r.status) {
                            'paid' => 'Đã nhận ${money(r.paidAmount ?? 0)}',
                            'pending' => 'Đang chờ',
                            'cancelled' => 'Đã hủy',
                            _ => 'Hết hạn',
                          },
                          if (r.personId != null) p.personName(r.personId),
                          if (r.note.isNotEmpty) r.note,
                        ].join(' • '))),
                ],
              ],
            ])));
  }
}
