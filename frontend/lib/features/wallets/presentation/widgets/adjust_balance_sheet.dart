import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';

Future<void> showAdjustBalance(BuildContext context, MoneyWallet wallet) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => AdjustBalanceSheet(wallet: wallet));

class AdjustBalanceSheet extends StatefulWidget {
  const AdjustBalanceSheet({super.key, required this.wallet});
  final MoneyWallet wallet;
  @override
  State<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends State<AdjustBalanceSheet> {
  final form = GlobalKey<FormState>();
  late final actual =
      TextEditingController(text: formatAmountInput(context.read<FinanceProvider>().balance(widget.wallet.id)));
  final picked = <bool, String>{};
  bool excluded = true;

  @override
  void dispose() {
    actual.dispose();
    super.dispose();
  }

  String? validate(String? v) {
    final n = parseAmount(v ?? '');
    return n == null || !n.isFinite || n < 0 ? 'Nhập số dư hợp lệ, không âm' : null;
  }

  void save(double diff, String? categoryId) {
    if (!form.currentState!.validate() || categoryId == null) return;
    final p = context.read<FinanceProvider>();
    attempt(context, () {
      p.adjustBalance(widget.wallet.id, parseAmount(actual.text)!, categoryId: categoryId, excluded: excluded);
      Navigator.pop(context);
      message(context, 'Đã điều chỉnh số dư ví ${widget.wallet.name}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final w = widget.wallet;
    final current = p.balance(w.id);
    final diff = (parseAmount(actual.text) ?? current) - current;
    final income = diff > 0;
    final options = p.categories.where((c) => c.income == income).toList();
    final fallback = income && options.any((c) => c.id == 'other_income') ? 'other_income' : options.firstOrNull?.id;
    final categoryId = options.any((c) => c.id == picked[income]) ? picked[income] : fallback;
    return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Form(
                key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Điều chỉnh số dư', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Số dư trên app: ${money(current, w.currency)}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 16),
                  TextFormField(
                      key: const ValueKey('adjust-actual'),
                      controller: actual,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [AmountInputFormatter()],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: 'Số dư thực tế', suffixText: w.currency),
                      validator: validate,
                      onChanged: (_) => setState(() {})),
                  const SizedBox(height: 12),
                  Text(
                      diff.abs() < 0.5
                          ? 'Số dư đang khớp, không cần điều chỉnh.'
                          : 'Sẽ ghi một khoản ${income ? 'thu' : 'chi'} ${money(diff.abs(), w.currency)} '
                              'với ghi chú “Điều chỉnh số dư”.',
                      style: TextStyle(
                          fontSize: 13,
                          color: diff.abs() < 0.5
                              ? AppColors.textSecondary
                              : income
                                  ? AppColors.primaryGreen
                                  : AppColors.accentRed)),
                  if (diff.abs() >= 0.5) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        key: ValueKey('adjust-category-$income'),
                        initialValue: categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Danh mục'),
                        items: [for (final c in options) DropdownMenuItem(value: c.id, child: Text(c.name))],
                        onChanged: (v) => setState(() => picked[income] = v!)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        tileColor: Colors.transparent,
                        title: const Text('Không tính vào báo cáo'),
                        subtitle: const Text('Khoản điều chỉnh không làm sai số liệu thu chi trong tháng'),
                        value: excluded,
                        onChanged: (v) => setState(() => excluded = v)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: diff.abs() < 0.5 ? null : () => save(diff, categoryId),
                      child: const Padding(padding: EdgeInsets.all(14), child: Text('Lưu điều chỉnh'))),
                ]))));
  }
}
