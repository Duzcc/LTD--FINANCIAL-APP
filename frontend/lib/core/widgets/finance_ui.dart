import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:finance_app/core/theme/app_colors.dart';
export 'package:finance_app/core/theme/app_colors.dart';

String money(num value, [String unit = 'VND']) =>
    '${NumberFormat('#,##0.##', 'vi_VN').format(value)} ${unit == 'VND' ? '₫' : unit}';

/// Số tiền hiển thị, được che khi người dùng bật "Ẩn số dư".
String secret(bool hidden, num value, [String unit = 'VND']) =>
    hidden ? '••••••' : money(value, unit);

/// Rút gọn số lớn cho trục biểu đồ: 1.500.000 → 1,5tr.
String compactMoney(num value) {
  final v = value.abs();
  if (v >= 1e9) return '${NumberFormat('#,##0.#', 'vi_VN').format(value / 1e9)}tỷ';
  if (v >= 1e6) return '${NumberFormat('#,##0.#', 'vi_VN').format(value / 1e6)}tr';
  if (v >= 1e3) return '${NumberFormat('#,##0', 'vi_VN').format(value / 1e3)}k';
  return NumberFormat('#,##0', 'vi_VN').format(value);
}

String dayLabel(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
void message(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is ArgumentError
            ? error.message.toString()
            : error.toString())));

/// Màu trạng thái mục tiêu (Bảng 29): xanh – đúng kế hoạch, vàng – sắp chạm
/// hạn mức (≥ 80%), đỏ – vượt kế hoạch.
Color budgetColor(double used, double target, {bool income = false}) {
  if (target <= 0) return AppColors.textGrey;
  final ratio = used / target;
  if (income) return ratio >= 1 ? AppColors.onPlan : AppColors.remaining;
  if (ratio > 1) return AppColors.overPlan;
  if (ratio >= .8) return AppColors.remaining;
  return AppColors.onPlan;
}

/// Đọc số tiền đã định dạng ("1.250.000" hoặc "12,5") thành số.
double? parseAmount(String text) {
  final t = text.replaceAll('.', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Định dạng số để hiển thị trong ô nhập: phân tách hàng nghìn bằng dấu chấm,
/// phần thập phân sau dấu phẩy.
String formatAmountInput(num value) {
  if (value == 0) return '';
  final whole = value.truncate();
  final fraction = value - whole;
  final head = NumberFormat('#,##0', 'vi_VN').format(whole);
  if (fraction.abs() < 1e-9) return head;
  final tail = value.toStringAsFixed(2).split('.').last.replaceAll(RegExp(r'0+$'), '');
  return '$head,$tail';
}

/// Tự chèn dấu phân tách hàng nghìn khi người dùng gõ số tiền.
class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var input = newValue.text;
    // Bàn phím dùng dấu chấm thập phân: dấu chấm vừa gõ ở cuối được hiểu là dấu phẩy.
    if (input.length == oldValue.text.length + 1 &&
        input.endsWith('.') &&
        !input.contains(',')) {
      input = '${input.substring(0, input.length - 1)},';
    }
    var raw = input.replaceAll(RegExp(r'[^0-9,]'), '');
    final comma = raw.indexOf(',');
    var intPart = comma < 0 ? raw : raw.substring(0, comma);
    var decPart = comma < 0 ? null : raw.substring(comma + 1).replaceAll(',', '');
    if (decPart != null && decPart.length > 2) decPart = decPart.substring(0, 2);
    intPart = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (intPart.length > 15) intPart = intPart.substring(0, 15);
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    var text = buffer.toString();
    if (decPart != null) text = '${text.isEmpty ? '0' : text},$decPart';
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Hộp thoại xác nhận chung. [danger] tô đỏ nút xác nhận.
Future<bool> confirmAction(BuildContext context,
        {required String title,
        required String content,
        String confirm = 'Đồng ý',
        String cancel = 'Hủy',
        bool danger = false}) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: Text(content),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(cancel)),
                  FilledButton(
                      style: danger
                          ? FilledButton.styleFrom(
                              backgroundColor: AppColors.accentRed)
                          : null,
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(confirm)),
                ])) ??
    false;
Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

class FinancePage extends StatelessWidget {
  const FinancePage(
      {super.key,
      required this.title,
      required this.child,
      this.actions,
      this.bottom});
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(
            top: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: child))),
        bottomNavigationBar: bottom == null
            ? null
            : Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.all(16),
                    child: bottom!)),
      );
}

class Panel extends StatelessWidget {
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
      color: color ?? Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.divider)),
      child: Padding(padding: padding, child: child));
}

class RoundIcon extends StatelessWidget {
  const RoundIcon(this.icon, {super.key, this.color = const Color(0xFF8D7564)});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: .12),
      child: Icon(icon, color: color, size: 21));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15))),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ]));
}

class EmptyView extends StatelessWidget {
  const EmptyView(
      {super.key,
      required this.title,
      required this.subtitle,
      this.icon = Icons.receipt_long_outlined,
      this.action,
      this.onTap});
  final String title, subtitle;
  final IconData icon;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: Column(children: [
        CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.cardBeige,
            child: Icon(icon, size: 38, color: const Color(0xFFA58A76))),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
        if (action != null) ...[
          const SizedBox(height: 18),
          FilledButton.tonal(onPressed: onTap, child: Text(action!))
        ],
      ]));
}

class MonthPicker extends StatelessWidget {
  const MonthPicker({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            tooltip: 'Tháng trước',
            onPressed: () => onChanged(DateTime(value.year, value.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: Text('Tháng ${DateFormat('MM/yyyy').format(value)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
            tooltip: 'Tháng sau',
            onPressed: () => onChanged(DateTime(value.year, value.month + 1)),
            icon: const Icon(Icons.chevron_right)),
      ]);
}

Future<bool> confirmDelete(BuildContext context, String title) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: const Text('Thao tác này không thể hoàn tác.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Hủy')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Xóa',
                          style: TextStyle(color: AppColors.accentRed))),
                ])) ??
    false;

Future<String?> editText(BuildContext context, String title,
    {String initial = '',
    bool numeric = false,
    bool obscure = false,
    String? Function(String?)? validator}) async {
  final controller = TextEditingController(text: initial);
  final key = GlobalKey<FormState>();
  final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Form(
                  key: key,
                  child: TextFormField(
                      controller: controller,
                      autofocus: true,
                      obscureText: obscure,
                      inputFormatters:
                          numeric ? [AmountInputFormatter()] : null,
                      keyboardType: numeric
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      validator: validator ??
                          (v) => v == null || v.trim().isEmpty
                              ? 'Vui lòng nhập thông tin'
                              : null)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy')),
                FilledButton(
                    onPressed: () {
                      if (key.currentState!.validate()) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
                    child: const Text('Lưu'))
              ]));
  // The dialog may still be animating out; keep its controller alive until then.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return value;
}
