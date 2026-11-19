import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/finance/presentation/widgets/entity_icons.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/domain/services/quick_parser.dart';
import 'package:finance_app/features/ai/domain/services/receipt_split.dart';
import 'package:finance_app/features/ai/presentation/widgets/quick_entry_sheet.dart';

class ReceiptReviewCard extends StatefulWidget {
  const ReceiptReviewCard(
      {super.key, required this.receipt, required this.onSaved, this.imagePath, this.saved = false});
  final ReceiptResult receipt;
  final String? imagePath;
  final bool saved;
  final void Function(List<MoneyEntry> entries) onSaved;

  @override
  State<ReceiptReviewCard> createState() => _ReceiptReviewCardState();
}

class _ReceiptReviewCardState extends State<ReceiptReviewCard> {
  final total = TextEditingController();
  late List<ReceiptItem> items;
  late DateTime date;
  late EntryKind kind;
  String? fallback, walletId;

  bool get income => kind == EntryKind.income;
  String get entryWord => income ? 'khoản thu' : 'khoản chi';

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    final p = context.read<FinanceProvider>();
    _useCategories(r);
    walletId = p.wallets.firstOrNull?.id;
    total.text = r.total == null ? '' : formatAmountInput(r.total!);
    final now = DateTime.now();
    final d = r.date;
    date = d == null || d.isAfter(now) || DateUtils.isSameDay(d, now) && d.hour == 0
        ? now
        : d.hour == 0 && d.minute == 0
            ? DateTime(d.year, d.month, d.day, 12)
            : d;
  }

  void _useCategories(ReceiptResult r) {
    final p = context.read<FinanceProvider>();
    kind = r.kind;
    final sameKind = p.categories.where((c) => c.income == income);
    fallback = p.category(r.categoryId)?.income == income ? r.categoryId : sameKind.firstOrNull?.id;
    items = [for (final i in r.items) p.category(i.categoryId)?.income == income ? i : i.withCategory(fallback)];
  }

  void _switchKind(EntryKind k) {
    final r = AiRepository(context.read<FinanceProvider>()).categorize(widget.receipt, k);
    setState(() => _useCategories(r));
  }

  @override
  void dispose() {
    total.dispose();
    super.dispose();
  }

  Future<String?> _pickCategory(String? current) => showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final p = context.read<FinanceProvider>();
        return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 8), children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(income ? 'Chọn danh mục thu' : 'Chọn danh mục chi',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              for (final c in p.categories.where((c) => c.income == income))
                ListTile(
                    leading: RoundIcon(c.icon),
                    title: Text(c.name),
                    trailing: c.id == current ? const Icon(Icons.check, color: AppColors.primaryGreen) : null,
                    onTap: () => Navigator.pop(context, c.id)),
            ]));
      });

  Future<void> _pickDate() async {
    final day =
        await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
    if (!mounted) return;
    setState(() => date = DateTime(day.year, day.month, day.day, time?.hour ?? date.hour, time?.minute ?? date.minute));
  }

  List<ReceiptGroup> _groups() =>
      fallback == null ? const [] : splitReceipt(items, parseAmount(total.text) ?? 0, fallback!);

  Future<void> _save(FinanceProvider p) async {
    final groups = _groups();
    if (groups.isEmpty || walletId == null) {
      message(context, 'Nhập tổng tiền hợp lệ.');
      return;
    }
    final entries = [
      for (final g in groups)
        MoneyEntry(
            id: p.newId(),
            kind: kind,
            amount: g.amount,
            walletId: walletId!,
            date: date,
            categoryId: g.categoryId,
            note: g.note(widget.receipt.merchant),
            photo: widget.imagePath)
    ];
    if (!await attempt(context, () => entries.forEach(p.checkEntry))) return;
    entries.forEach(p.saveEntry);
    widget.onSaved(entries);
  }

  Future<void> _editManually(FinanceProvider p) => openParsedEntry(
      context,
      ParsedEntry(
          kind: kind,
          amount: parseAmount(total.text),
          date: date,
          note: widget.receipt.note.isEmpty ? 'Hóa đơn' : widget.receipt.note,
          categoryId: fallback,
          walletId: walletId,
          confidence: widget.receipt.confidence),
      photo: widget.imagePath);

  Widget _categoryChip(FinanceProvider p, String? id, ValueChanged<String> onPicked) {
    final c = p.category(id);
    return Material(
        color: AppColors.primaryGreenSurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.saved
                ? null
                : () async {
                    final picked = await _pickCategory(id);
                    if (picked != null) onPicked(picked);
                  },
            child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(c?.icon ?? Icons.category_outlined, size: 14, color: AppColors.primaryGreen),
                  const SizedBox(width: 4),
                  Text(c?.name ?? 'Chọn danh mục',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                  if (!widget.saved) const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.primaryGreen),
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final r = widget.receipt;
    final amount = parseAmount(total.text) ?? 0;
    final groups = _groups();
    final split = itemsMatchTotal(items, amount);
    final unit = p.findWallet(walletId)?.currency ?? p.currency;
    final level = r.confidence >= 0.8
        ? (AppColors.primaryGreen, 'Tin cậy cao')
        : r.confidence >= 0.55
            ? (AppColors.accentYellow, 'Nên kiểm tra')
            : (AppColors.accentRed, 'Kiểm tra kỹ');
    return Panel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const RoundIcon(Icons.receipt_long_outlined),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.merchant ?? 'Cửa hàng không rõ',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              InkWell(
                  onTap: widget.saved ? null : _pickDate,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${dayLabel(date)} lúc ${TimeOfDay.fromDateTime(date).format(context)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (!widget.saved) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined, size: 13, color: AppColors.textSecondary),
                    ],
                  ])),
            ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration:
                    BoxDecoration(color: level.$1.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                child: Text('${level.$2} ${(r.confidence * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: level.$1, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<EntryKind>(segments: const [
            ButtonSegment(value: EntryKind.expense, label: Text('Khoản chi'), icon: Icon(Icons.arrow_upward)),
            ButtonSegment(value: EntryKind.income, label: Text('Khoản thu'), icon: Icon(Icons.arrow_downward)),
          ], selected: {
            kind
          }, showSelectedIcon: false, onSelectionChanged: widget.saved ? null : (s) => _switchKind(s.first)),
          const SizedBox(height: 12),
          if (items.isEmpty) ...[
            Text('Không tách được từng món, sẽ ghi thành một $entryWord.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            _categoryChip(p, fallback, (id) => setState(() => fallback = id)),
          ],
          for (final (n, i) in items.indexed)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      if (i.quantity != null && i.unitPrice != null)
                        Text('${i.quantity!.round()} × ${money(i.unitPrice!, unit)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ])),
                    const SizedBox(width: 8),
                    Text(money(i.amount, unit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  _categoryChip(p, i.categoryId, (id) => setState(() => items[n] = i.withCategory(id))),
                ])),
          const Divider(height: 20),
          TextField(
              key: const ValueKey('chat-receipt-total'),
              controller: total,
              enabled: !widget.saved,
              keyboardType: TextInputType.number,
              inputFormatters: [AmountInputFormatter()],
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: income ? AppColors.primaryGreen : AppColors.accentRed),
              decoration: InputDecoration(
                  labelText: income ? 'Tổng nhận được' : 'Tổng phải trả', suffixText: unit, isDense: true)),
          if (p.wallets.length > 1) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                initialValue: walletId,
                isDense: true,
                decoration: InputDecoration(labelText: income ? 'Nhận vào ví' : 'Trả từ ví', isDense: true),
                items: [
                  for (final w in p.wallets) DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: widget.saved ? null : (v) => setState(() => walletId = v)),
          ],
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(groups.length > 1 ? 'Sẽ ghi ${groups.length} $entryWord' : 'Sẽ ghi một $entryWord',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final g in groups)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            '${p.category(g.categoryId)?.name ?? 'Khác'}${g.items.isEmpty ? '' : ' · ${g.items.length} món'}',
                            style: const TextStyle(fontSize: 13))),
                    Text(money(g.amount, unit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
            if (items.isNotEmpty && !split)
              const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Tổng các món lệch nhiều so với tổng hóa đơn nên chỉ ghi một khoản.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          ],
          const SizedBox(height: 12),
          if (widget.saved)
            const Row(children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.primaryGreen),
              SizedBox(width: 6),
              Text('Đã ghi vào sổ', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
            ])
          else
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed: groups.isEmpty ? null : () => _save(p),
                      icon: const Icon(Icons.check),
                      label: Text(groups.length > 1 ? 'Ghi ${groups.length} $entryWord' : 'Ghi $entryWord'))),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _editManually(p), child: const Text('Sửa tay')),
            ]),
        ]));
  }
}
