import 'package:finance_app/features/ai/domain/entities/ai_models.dart';

class ReceiptGroup {
  const ReceiptGroup(this.categoryId, this.amount, this.items);
  final String categoryId;
  final double amount;
  final List<ReceiptItem> items;

  String note(String? merchant) {
    final names = items.take(3).map((i) => i.name).join(', ');
    final more = items.length > 3 ? ' và ${items.length - 3} món khác' : '';
    if (names.isEmpty) return merchant ?? 'Hóa đơn';
    return merchant == null ? '$names$more' : '$merchant: $names$more';
  }
}

bool itemsMatchTotal(List<ReceiptItem> items, double total) {
  final sum = items.fold(0.0, (s, i) => s + i.amount);
  return sum > 0 && sum >= total * .5 && sum <= total * 1.5;
}

List<ReceiptGroup> splitReceipt(List<ReceiptItem> items, double total, String fallbackCategoryId) {
  if (total <= 0) return const [];
  if (!itemsMatchTotal(items, total)) return [ReceiptGroup(fallbackCategoryId, total, items)];
  final byCategory = <String, List<ReceiptItem>>{};
  for (final i in items) {
    byCategory.putIfAbsent(i.categoryId ?? fallbackCategoryId, () => []).add(i);
  }
  final sum = items.fold(0.0, (s, i) => s + i.amount);
  final groups = [
    for (final e in byCategory.entries)
      ReceiptGroup(e.key, (e.value.fold(0.0, (s, i) => s + i.amount) * total / sum).roundToDouble(), e.value)
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  final residue = total - groups.fold(0.0, (s, g) => s + g.amount);
  if (residue != 0) {
    final first = groups.first;
    groups[0] = ReceiptGroup(first.categoryId, first.amount + residue, first.items);
  }
  return groups.where((g) => g.amount > 0).toList();
}
