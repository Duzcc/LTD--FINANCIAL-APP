import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/banking/vietqr.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/banking/data/bank_repository.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';

/// Kết nối ngân hàng: các ví đã liên kết tài khoản và cấu hình webhook SePay
/// để tiền chuyển vào qua VietQR được tự ghi thành giao dịch.
class SepayScreen extends StatefulWidget {
  const SepayScreen({super.key});
  @override
  State<SepayScreen> createState() => _SepayScreenState();
}

class _SepayScreenState extends State<SepayScreen> {
  SepayStatus? status;
  List<PaymentRequestInfo> requests = [];
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = context.read<FinanceProvider>();
    if (!p.signedIn) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = BankRepository(p);
      final s = await repo.sepay();
      final list = await repo.list();
      if (mounted) {
        setState(() {
          status = s;
          requests = list;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> createKey() async {
    if (status?.connected == true &&
        !await confirmAction(context,
            title: 'Tạo khóa mới?',
            content:
                'Khóa cũ sẽ ngừng hoạt động. Bạn cần dán khóa mới vào cấu hình webhook trên SePay.',
            confirm: 'Tạo khóa mới')) {
      return;
    }
    if (!mounted) return;
    try {
      final s = await BankRepository(context.read<FinanceProvider>()).createKey();
      if (mounted) setState(() => status = s);
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> revoke() async {
    if (!await confirmAction(context,
        title: 'Ngắt kết nối SePay?',
        content: 'Tiền chuyển vào sẽ không còn được tự ghi thành giao dịch.',
        confirm: 'Ngắt kết nối',
        danger: true)) {
      return;
    }
    if (!mounted) return;
    try {
      await BankRepository(context.read<FinanceProvider>()).revokeKey();
      await load();
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  void copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    message(context, 'Đã sao chép $label');
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
              const Text('Tài khoản đã liên kết',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final w in linked)
                Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                        leading: const RoundIcon(Icons.account_balance_outlined),
                        title: Text(w.name),
                        subtitle: Text(
                            '${bankByBin(w.bankBin)?.name} • ${w.bankAccount}\n${w.bankHolder}'),
                        trailing: const Icon(Icons.edit_outlined, size: 18),
                        onTap: () =>
                            openPage(context, CreateWalletScreen(wallet: w)))),
              if (linked.isEmpty)
                const Text(
                    'Chưa có ví nào liên kết ngân hàng. Mở một ví VND → Chỉnh sửa → "Liên kết tài khoản ngân hàng".',
                    style: TextStyle(height: 1.5)),
              const SizedBox(height: 20),
              const Text('Tự ghi giao dịch qua SePay',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (!p.signedIn)
                const Text(
                    'Cần đăng nhập tài khoản để máy chủ nhận thông báo tiền về từ SePay. Khi dùng ngoại tuyến bạn vẫn tạo được mã VietQR để nhận tiền.',
                    style: TextStyle(height: 1.5))
              else if (loading && s == null)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                Text(error!, style: const TextStyle(color: AppColors.accentRed))
              else if (s != null) ...[
                Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      ListTile(
                          leading: Icon(
                              s.connected ? Icons.link : Icons.link_off,
                              color: s.connected
                                  ? AppColors.primaryGreen
                                  : AppColors.textSecondary),
                          title: Text(s.connected ? 'Đã tạo khóa webhook' : 'Chưa kết nối'),
                          subtitle: s.keyHint == null
                              ? null
                              : Text('Khóa kết thúc bằng …${s.keyHint}')),
                      ListTile(
                          title: const Text('URL webhook'),
                          subtitle: Text(s.webhookUrl),
                          trailing: IconButton(
                              tooltip: 'Sao chép',
                              onPressed: () => copy('URL webhook', s.webhookUrl),
                              icon: const Icon(Icons.copy, size: 20))),
                      if (s.apiKey != null)
                        ListTile(
                            tileColor: AppColors.primaryGreenSurface,
                            title: const Text('API Key (chỉ hiện một lần)'),
                            subtitle: SelectableText(s.apiKey!),
                            trailing: IconButton(
                                tooltip: 'Sao chép',
                                onPressed: () => copy('API Key', s.apiKey!),
                                icon: const Icon(Icons.copy, size: 20))),
                    ])),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: createKey,
                          child: Text(s.connected ? 'Tạo khóa mới' : 'Tạo khóa kết nối'))),
                  if (s.connected) ...[
                    const SizedBox(width: 10),
                    Expanded(
                        child: OutlinedButton(
                            onPressed: revoke, child: const Text('Ngắt kết nối'))),
                  ],
                ]),
                const SizedBox(height: 16),
                const Panel(
                    child: Text(
                        'Cách kết nối:\n'
                        '1. Đăng ký tại my.sepay.vn và thêm tài khoản ngân hàng của bạn (giống số tài khoản đã liên kết với ví).\n'
                        '2. Vào Tích hợp → Webhooks → Thêm webhook: sự kiện "Có tiền vào", dán URL webhook ở trên.\n'
                        '3. Kiểu chứng thực: API Key, dán API Key ở trên.\n'
                        '4. Máy chủ phải truy cập được từ Internet (tên miền thật, hoặc ngrok/cloudflared khi chạy trên máy).\n\n'
                        'Khi khách quét mã VietQR của bạn và giữ nguyên nội dung chuyển khoản (có mã LTD…), giao dịch sẽ tự ghi vào ví.',
                        style: TextStyle(height: 1.5))),
                if (requests.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Yêu cầu nhận tiền gần đây',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final r in requests.take(20))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(switch (r.status) {
                          'paid' => Icons.check_circle_outline,
                          'pending' => Icons.schedule,
                          _ => Icons.block,
                        }),
                        title: Text(
                            '${r.code} • ${r.amount == null ? 'Tùy số tiền' : money(r.amount!)}'),
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
