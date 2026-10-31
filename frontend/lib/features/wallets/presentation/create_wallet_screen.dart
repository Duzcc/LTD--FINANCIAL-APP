import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/currency_selection_screen.dart';

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen(
      {super.key,
      this.isFirstWallet = false,
      this.wallet,
      this.savings = false});
  final bool isFirstWallet, savings;
  final MoneyWallet? wallet;
  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.wallet?.name ?? '');
  late final opening = TextEditingController(
      text: formatAmountInput(widget.wallet?.opening ?? 0));
  late final target = TextEditingController(
      text: formatAmountInput(widget.wallet?.target ?? 0));
  late String currency = widget.wallet?.currency ?? 'VND';
  late bool savings = widget.wallet?.savings ?? widget.savings,
      excluded = widget.wallet?.excluded ?? false;
  late DateTime? deadline = widget.wallet?.deadline;
  late DateTime? startDate = widget.wallet?.startDate ??
      (widget.wallet == null ? DateUtilsDate.day(DateTime.now()) : null);
  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    target.dispose();
    super.dispose();
  }

  String? amountValidator(String? v) {
    final n = (v ?? '').trim().isEmpty ? 0 : parseAmount(v!);
    return n == null || !n.isFinite || n < 0 ? 'Nhập số hợp lệ, không âm' : null;
  }

  double amountOf(TextEditingController c) => parseAmount(c.text) ?? 0;
  void save() {
    if (!form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    try {
      p.saveWallet(MoneyWallet(
          id: widget.wallet?.id ?? p.newId(),
          name: name.text.trim(),
          opening: amountOf(opening),
          currency: currency,
          savings: savings,
          excluded: excluded,
          target: savings ? amountOf(target) : 0,
          startDate: savings ? startDate : null,
          deadline: savings ? deadline : null));
      Navigator.pop(context);
    } catch (e) {
      message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: widget.wallet == null ? 'Thêm ví' : 'Chỉnh sửa ví',
      bottom: FilledButton(
          onPressed: save,
          child: const Padding(
              padding: EdgeInsets.all(14), child: Text('Lưu ví'))),
      child: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              for (final type in [false, true])
                Expanded(
                    child: Padding(
                        padding: EdgeInsets.only(right: type ? 0 : 12),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => savings = type),
                            child: Panel(
                                color: savings == type
                                    ? (type
                                        ? const Color(0xFFBC956D)
                                        : const Color(0xFF7C9583))
                                    : Colors.white,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                          type
                                              ? Icons.savings_outlined
                                              : Icons
                                                  .account_balance_wallet_outlined,
                                          size: 36,
                                          color: savings == type
                                              ? Colors.white
                                              : AppColors.textSecondary),
                                      const SizedBox(height: 16),
                                      Text(type ? 'Ví tiết kiệm' : 'Ví cơ bản',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: savings == type
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                    ])))))
            ]),
            const SizedBox(height: 20),
            Panel(
                child: Column(children: [
              TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Tên ví',
                      prefixIcon: Icon(Icons.wallet_outlined)),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Nhập tên ví' : null),
              const SizedBox(height: 12),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('Đơn vị tiền tệ'),
                  subtitle:
                      Text(CurrencySelectionScreen.units[currency] ?? currency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final v = await openPage<String>(context,
                        CurrencySelectionScreen(selectedCurrency: currency));
                    if (v != null && mounted) setState(() => currency = v);
                  }),
              const SizedBox(height: 12),
              TextFormField(
                  controller: opening,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [AmountInputFormatter()],
                  decoration: InputDecoration(
                      labelText: savings ? 'Số tiền ban đầu' : 'Số dư hiện có',
                      hintText: '0',
                      suffixText: currency),
                  validator: amountValidator),
            ])),
            if (savings) ...[
              const SizedBox(height: 16),
              Panel(
                  child: Column(children: [
                TextFormField(
                    controller: target,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    decoration: InputDecoration(
                        labelText: 'Mục tiêu tiết kiệm',
                        hintText: 'Số tiền cần đạt (không bắt buộc)',
                        suffixText: currency),
                    validator: amountValidator),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('Ngày bắt đầu'),
                    subtitle: Text(startDate == null
                        ? 'Chưa chọn'
                        : dayLabel(startDate!)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100));
                      if (d != null && mounted) {
                        setState(() {
                          startDate = d;
                          if (deadline != null && deadline!.isBefore(d)) {
                            deadline = null;
                          }
                        });
                      }
                    }),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Ngày kết thúc'),
                    subtitle: Text(deadline == null
                        ? 'Chưa đặt thời hạn'
                        : dayLabel(deadline!)),
                    trailing: deadline == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            tooltip: 'Bỏ thời hạn',
                            onPressed: () => setState(() => deadline = null),
                            icon: const Icon(Icons.clear)),
                    onTap: () async {
                      final first = startDate ?? DateTime(2020);
                      final initial = deadline ?? DateTime.now();
                      final d = await showDatePicker(
                          context: context,
                          initialDate:
                              initial.isBefore(first) ? first : initial,
                          firstDate: first,
                          lastDate: DateTime(2100));
                      if (d != null && mounted) setState(() => deadline = d);
                    }),
              ]))
            ],
            const SizedBox(height: 16),
            SwitchListTile(
                title: const Text('Không tính vào tổng'),
                subtitle: const Text(
                    'Ví vẫn xuất hiện trong danh sách và giao dịch.'),
                value: excluded,
                onChanged: (v) => setState(() => excluded = v)),
            if (widget.wallet != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Xóa ví'),
                  onPressed: () async {
                    final p = context.read<FinanceProvider>();
                    final id = widget.wallet!.id;
                    final refs = p.walletReferences(id);
                    final ok = refs == 0
                        ? await confirmDelete(context, 'Xóa ví này?')
                        : await confirmAction(context,
                            title: 'Xóa ví và dữ liệu liên quan?',
                            content:
                                'Ví đang có $refs giao dịch/ngân sách liên quan. Xóa ví sẽ xóa luôn các dữ liệu này; giao dịch chuyển tiền với ví khác cũng bị xóa nên số dư ví kia sẽ thay đổi. Thao tác không thể hoàn tác.',
                            confirm: 'Xóa tất cả',
                            danger: true);
                    if (!ok || !context.mounted) return;
                    try {
                      p.deleteWallet(id, cascade: refs > 0);
                      message(context, 'Đã xóa ví.');
                      Navigator.pop(context, 'deleted');
                    } catch (e) {
                      message(context, e);
                    }
                  })
            ],
            const SizedBox(height: 24),
            const Text(
                'Số dư hiện tại được tính từ số dư ban đầu và tất cả giao dịch của ví. Các tiền tệ được thống kê riêng.'),
          ])));
}
