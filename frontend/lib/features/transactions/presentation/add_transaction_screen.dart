import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/select_wallet_sheet.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_person_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen(
      {super.key,
      this.entry,
      this.initialKind = EntryKind.expense,
      this.initialWalletId,
      this.initialPersonId,
      this.initialAmount,
      this.initialCategoryId,
      this.initialNote,
      this.initialDate,
      this.initialPhoto});
  final MoneyEntry? entry;
  final EntryKind initialKind;
  final String? initialWalletId, initialPersonId, initialCategoryId, initialNote;
  final double? initialAmount;
  final DateTime? initialDate;

  /// Ảnh hóa đơn đính kèm sẵn (ví dụ từ màn Quét hóa đơn).
  final String? initialPhoto;
  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
      text: formatAmountInput(widget.entry?.amount ?? widget.initialAmount ?? 0));
  late final note =
      TextEditingController(text: widget.entry?.note ?? widget.initialNote ?? '');
  late EntryKind kind = widget.entry?.kind ?? widget.initialKind;
  late String? walletId = widget.entry?.walletId ?? widget.initialWalletId,
      destinationId = widget.entry?.destinationId,
      categoryId = widget.entry?.categoryId ?? widget.initialCategoryId,
      personId = widget.entry?.personId ?? widget.initialPersonId;
  late DateTime date = widget.entry?.date ?? widget.initialDate ?? DateTime.now();
  late String? photo = widget.entry?.photo ?? widget.initialPhoto;
  late final String entryId =
      widget.entry?.id ?? context.read<FinanceProvider>().newId();
  RepeatFrequency? repeat;
  late bool categoryTouched =
      widget.entry != null || widget.initialCategoryId != null;
  String? suggestedCategory;
  late DateTime? dueDate = widget.entry?.dueDate;
  late bool excluded = widget.entry?.excluded ?? false;
  late final String initialSignature;
  bool saving = false;
  int get tab => kind.isDebt ? 3 : kind.index;

  static const _notes = {
    EntryKind.expense: ['Ăn sáng', 'Cà phê', 'Ăn trưa', 'Đồ uống', 'Đổ xăng'],
    EntryKind.income: ['Lương tháng', 'Thưởng', 'Bán đồ', 'Làm thêm'],
    EntryKind.transfer: ['Nạp tiết kiệm', 'Rút tiền mặt', 'Chuyển khoản'],
  };

  @override
  void initState() {
    super.initState();
    final p = context.read<FinanceProvider>();
    if (p.findWallet(walletId) == null) walletId = p.wallets.firstOrNull?.id;
    categoryId ??=
        p.categories.where((c) => c.income == kind.isIncome).firstOrNull?.id;
    initialSignature = signature;
  }

  String get signature =>
      '$kind|${amount.text}|$walletId|$destinationId|$categoryId|$personId|$date|$dueDate|${note.text}|$excluded|$photo|$repeat';

  /// Mô hình học trên thiết bị gợi ý danh mục từ ghi chú.
  void suggestCategory(String text) {
    if (!(kind.isExpense || kind.isIncome) || text.trim().length < 2) {
      setState(() => suggestedCategory = null);
      return;
    }
    final p = context.read<FinanceProvider>();
    final model = p.cached(() => CategoryModel.train(p.categories, p.entries));
    final s = model.suggest(text, income: kind.isIncome);
    setState(() {
      suggestedCategory = s;
      if (s != null && !categoryTouched) categoryId = s;
    });
  }

  Future<void> pickPhoto(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/receipts');
      await folder.create(recursive: true);
      final saved = await File(x.path)
          .copy('${folder.path}/${entryId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      if (mounted) setState(() => photo = saved.path);
    } catch (e) {
      if (mounted) message(context, 'Không lấy được ảnh: $e');
    }
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void changeKind(EntryKind next) {
    final p = context.read<FinanceProvider>();
    setState(() {
      final incomeChanged = next.isIncome != kind.isIncome;
      kind = next;
      final current = p.category(categoryId);
      if (incomeChanged || current == null || current.income != kind.isIncome) {
        categoryId = p.categories
            .where((c) => c.income == kind.isIncome)
            .firstOrNull
            ?.id;
      }
    });
  }

  Future<void> pickWallet({bool destination = false}) async {
    final p = context.read<FinanceProvider>();
    final id = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SelectWalletSheet(
            selectedWallet: destination ? destinationId : walletId,
            excludeId: destination ? walletId : null,
            currency: destination && walletId != null
                ? p.wallet(walletId!).currency
                : null));
    if (id == null || !mounted) return;
    setState(() {
      if (destination) {
        destinationId = id;
      } else {
        walletId = id;
        if (destinationId != null &&
            p.findWallet(destinationId)?.currency != p.wallet(id).currency) {
          destinationId = null;
        }
        if (destinationId == id) destinationId = null;
      }
    });
  }

  /// Số dư ví nếu chưa tính giao dịch đang sửa.
  double available(FinanceProvider p, String id) {
    var value = p.balance(id);
    final old = widget.entry;
    if (old != null) {
      if (old.walletId == id) value -= old.amount * old.kind.sign;
      if (old.kind == EntryKind.transfer && old.destinationId == id) {
        value -= old.amount;
      }
    }
    return value;
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    if (walletId == null) {
      message(context, 'Vui lòng tạo và chọn ví.');
      return;
    }
    final p = context.read<FinanceProvider>();
    final value = parseAmount(amount.text)!;
    final w = p.wallet(walletId!);
    if (kind.sign < 0) {
      final left = available(p, w.id);
      if (value > left + 1e-9) {
        final go = await confirmAction(context,
            title: 'Số tiền vượt số dư ví',
            content:
                'Số dư hiện có của ví ${w.name} là ${money(left, w.currency)}. Sau giao dịch, ví sẽ âm ${money(value - left, w.currency)}. Bạn vẫn muốn lưu?',
            confirm: 'Vẫn lưu');
        if (!go || !mounted) return;
      }
    }
    try {
      setState(() => saving = true);
      p.saveEntry(MoneyEntry(
          id: entryId,
          kind: kind,
          amount: value,
          walletId: walletId!,
          destinationId: kind == EntryKind.transfer ? destinationId : null,
          categoryId: kind.isExpense || kind.isIncome ? categoryId : null,
          personId: personId,
          date: date,
          dueDate: kind.isDebt ? dueDate : null,
          note: note.text.trim(),
          excluded: excluded,
          photo: photo,
          recurringId: widget.entry?.recurringId));
      if (repeat != null && widget.entry == null) {
        // Giao dịch vừa lưu là lần đầu tiên của quy tắc định kỳ.
        final rule = RecurringRule(
            id: p.newId(),
            kind: kind,
            amount: value,
            walletId: walletId!,
            destinationId: kind == EntryKind.transfer ? destinationId : null,
            categoryId: kind.isExpense || kind.isIncome ? categoryId : null,
            personId: personId,
            note: note.text.trim(),
            frequency: repeat!,
            startDate: date);
        p.saveRecurring(rule.copyWith(nextDate: rule.nextAfter(date)));
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.entry == null
              ? 'Đã lưu giao dịch ${kind.label.toLowerCase()}.'
              : 'Đã cập nhật giao dịch.')));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => saving = false);
      message(context, e);
    }
  }

  Future<void> leave() async {
    final go = await confirmAction(context,
        title: 'Bỏ thay đổi?',
        content: 'Thông tin bạn vừa nhập sẽ không được lưu.',
        confirm: 'Bỏ thay đổi',
        cancel: 'Tiếp tục nhập',
        danger: true);
    if (go && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final wallet = p.findWallet(walletId);
    final unit = wallet?.currency ?? 'VND';
    final categories =
        p.categories.where((c) => c.income == kind.isIncome).toList();
    final settle = kind == EntryKind.collect || kind == EntryKind.repay;
    final remaining = personId == null || !settle
        ? null
        : p.debt(
            borrowed: kind == EntryKind.repay,
            personId: personId,
            unit: unit,
            excludeId: widget.entry?.id);
    return PopScope(
        canPop: saving || signature == initialSignature,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) leave();
        },
        child: FinancePage(
            title: widget.entry == null
                ? 'Thêm giao dịch mới'
                : 'Chỉnh sửa giao dịch',
            actions: [
              IconButton(
                  tooltip: 'Đính kèm ảnh hóa đơn',
                  onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (ctx) => SafeArea(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(
                                leading: const Icon(Icons.photo_camera_outlined),
                                title: const Text('Chụp ảnh hóa đơn'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  pickPhoto(ImageSource.camera);
                                }),
                            ListTile(
                                leading: const Icon(Icons.photo_library_outlined),
                                title: const Text('Chọn từ thư viện'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  pickPhoto(ImageSource.gallery);
                                }),
                          ]))),
                  icon: const Icon(Icons.receipt_long_outlined)),
            ],
            bottom: FilledButton(
                onPressed: saving ? null : save,
                child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Lưu giao dịch'))),
            child: Form(
                key: form,
                onChanged: () => setState(() {}),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final (i, label) in [
                              'Chi tiêu',
                              'Thu nhập',
                              'Chuyển tiền',
                              'Vay / Nợ'
                            ].indexed)
                              Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                      label: Text(label),
                                      selected: tab == i,
                                      onSelected: (_) => changeKind([
                                            EntryKind.expense,
                                            EntryKind.income,
                                            EntryKind.transfer,
                                            EntryKind.borrow
                                          ][i]))),
                          ])),
                      if (kind.isDebt) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final k
                              in EntryKind.values.where((k) => k.isDebt))
                            ChoiceChip(
                                label: Text(k.label),
                                selected: kind == k,
                                onSelected: (_) => changeKind(k)),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(
                              kind.sign > 0
                                  ? Icons.south_west
                                  : Icons.north_east,
                              size: 16,
                              color: kind.sign > 0
                                  ? AppColors.primaryGreen
                                  : AppColors.accentRed),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  '${kind.sign > 0 ? 'Tiền vào ví' : 'Tiền ra khỏi ví'}${kind == EntryKind.interestIncome || kind == EntryKind.interestExpense ? ' • tính vào báo cáo thu chi' : ' • không tính vào thu chi'}',
                                  style: const TextStyle(fontSize: 12))),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      Panel(
                          child: TextFormField(
                        key: const ValueKey('transaction-amount'),
                        controller: amount,
                        inputFormatters: [AmountInputFormatter()],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: kind == EntryKind.transfer
                                ? AppColors.textPrimary
                                : kind.sign < 0
                                    ? AppColors.accentRed
                                    : AppColors.primaryGreen),
                        decoration: InputDecoration(
                            labelText: 'Số tiền giao dịch',
                            hintText: '0',
                            suffixText: unit,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            filled: false),
                        validator: (v) {
                          final n = parseAmount(v ?? '');
                          return n == null || !n.isFinite || n <= 0
                              ? 'Nhập số tiền lớn hơn 0'
                              : null;
                        },
                      )),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        for (final n in [20000, 50000, 100000, 200000, 500000])
                          ActionChip(
                              label: Text('+${n ~/ 1000}k'),
                              onPressed: () => setState(() => amount.text =
                                  formatAmountInput(
                                      (parseAmount(amount.text) ?? 0) + n)))
                      ]),
                      if (kind.isExpense || kind.isIncome) ...[
                        SectionTitle(
                            'Danh mục${p.category(categoryId) == null ? '' : ' • ${p.category(categoryId)!.name}'}',
                            action: 'Xem tất cả', onTap: () async {
                          final c = await openPage<MoneyCategory>(
                              context,
                              SelectCategoryScreen(
                                  selectedCategoryId: categoryId,
                                  income: kind.isIncome));
                          if (c != null && mounted) {
                            setState(() {
                              categoryId = c.id;
                              categoryTouched = true;
                            });
                          }
                        }),
                        SizedBox(
                            height:
                                68 + MediaQuery.textScalerOf(context).scale(32),
                            child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: categories.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final c = categories[i];
                                  final selected = c.id == categoryId;
                                  return SizedBox(
                                      width: 76,
                                      child: InkWell(
                                          onTap: () => setState(() {
                                                categoryId = c.id;
                                                categoryTouched = true;
                                              }),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Column(children: [
                                            Container(
                                                padding:
                                                    const EdgeInsets.all(11),
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: selected
                                                        ? const Color(
                                                            0xFFE8D8CB)
                                                        : Colors.white,
                                                    border: Border.all(
                                                        width: selected ? 2 : 1,
                                                        color: selected
                                                            ? const Color(
                                                                0xFFAD8D76)
                                                            : AppColors
                                                                .divider)),
                                                child: Icon(c.icon,
                                                    color: const Color(
                                                        0xFF8D7564))),
                                            const SizedBox(height: 7),
                                            Text(c.name,
                                                maxLines: 2,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontSize: 12))
                                          ])));
                                })),
                      ],
                      if ((kind.isExpense || kind.isIncome) &&
                          suggestedCategory != null &&
                          p.category(suggestedCategory) != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: ActionChip(
                                    avatar: const Icon(Icons.auto_awesome,
                                        size: 16, color: AppColors.primaryGreen),
                                    label: Text(suggestedCategory == categoryId
                                        ? 'AI đã chọn: ${p.category(suggestedCategory)!.name}'
                                        : 'AI gợi ý: ${p.category(suggestedCategory)!.name}'),
                                    onPressed: () => setState(() {
                                          categoryId = suggestedCategory;
                                          categoryTouched = true;
                                        })))),
                      const SizedBox(height: 12),
                      ListTile(
                          leading: const RoundIcon(
                              Icons.account_balance_wallet_outlined),
                          title: Text(kind == EntryKind.transfer
                              ? 'Từ ví'
                              : 'Ví thanh toán'),
                          subtitle: Text(wallet == null
                              ? 'Chưa chọn ví'
                              : '${wallet.name} • ${money(p.balance(wallet.id), wallet.currency)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: pickWallet),
                      if (p.wallets.isEmpty)
                        TextButton.icon(
                            onPressed: () async {
                              await openPage(
                                  context, const CreateWalletScreen());
                              if (mounted) {
                                setState(
                                    () => walletId = p.wallets.firstOrNull?.id);
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo ví đầu tiên')),
                      if (kind == EntryKind.transfer) ...[
                        const SizedBox(height: 10),
                        ListTile(
                            leading:
                                const RoundIcon(Icons.move_to_inbox_outlined),
                            title: const Text('Đến ví'),
                            subtitle: Text(p.findWallet(destinationId) == null
                                ? 'Chọn ví nhận cùng tiền tệ'
                                : p.wallet(destinationId!).name),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => pickWallet(destination: true)),
                        const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                                'Chuyển tiền nội bộ chỉ thay đổi số dư hai ví, không tính vào thu nhập hoặc chi tiêu.'))
                      ],
                      const SizedBox(height: 10),
                      ListTile(
                          leading: const RoundIcon(Icons.person_outline),
                          title: Text(kind.isDebt
                              ? 'Đối tượng (người vay / cho vay)'
                              : 'Đối tượng'),
                          subtitle: Text(personId == null
                              ? (kind.isDebt
                                  ? 'Bắt buộc với vay / nợ'
                                  : 'Chọn người hoặc cửa hàng')
                              : '${p.personName(personId)}${remaining == null ? '' : ' • ${kind == EntryKind.repay ? 'còn phải trả' : 'còn phải thu'} ${money(remaining, unit)}'}'),
                          trailing: personId == null
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: 'Bỏ đối tượng',
                                  onPressed: () =>
                                      setState(() => personId = null),
                                  icon: const Icon(Icons.clear)),
                          onTap: () async {
                            final person = await openPage<MoneyPerson>(context,
                                SelectPersonScreen(selectedPerson: personId));
                            if (person != null && mounted) {
                              setState(() => personId = person.id);
                            }
                          }),
                      if (remaining != null && remaining > 0)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                onPressed: () => setState(() =>
                                    amount.text = formatAmountInput(remaining)),
                                child: Text(
                                    'Điền toàn bộ ${money(remaining, unit)}'))),
                      const SizedBox(height: 10),
                      ListTile(
                          leading: const RoundIcon(Icons.event_outlined),
                          title: const Text('Thời gian'),
                          subtitle: Text(
                              '${dayLabel(date)} • ${TimeOfDay.fromDateTime(date).format(context)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100));
                            if (d == null || !context.mounted) return;
                            final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(date));
                            if (!mounted) return;
                            setState(() {
                              date = DateTime(d.year, d.month, d.day,
                                  t?.hour ?? date.hour, t?.minute ?? date.minute);
                              if (dueDate != null &&
                                  DateUtilsDate.day(dueDate!)
                                      .isBefore(DateUtilsDate.day(date))) {
                                dueDate = null;
                              }
                            });
                          }),
                      if (kind.isDebt) ...[
                        const SizedBox(height: 10),
                        ListTile(
                            leading: const RoundIcon(Icons.event_available),
                            title: const Text('Ngày đến hạn'),
                            subtitle: Text(dueDate == null
                                ? 'Chưa đặt thời hạn'
                                : dayLabel(dueDate!)),
                            trailing: dueDate == null
                                ? const Icon(Icons.chevron_right)
                                : IconButton(
                                    tooltip: 'Bỏ thời hạn',
                                    onPressed: () =>
                                        setState(() => dueDate = null),
                                    icon: const Icon(Icons.clear)),
                            onTap: () async {
                              final first =
                                  DateTime(date.year, date.month, date.day);
                              final d = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      dueDate != null && !dueDate!.isBefore(first)
                                          ? dueDate
                                          : first,
                                  firstDate: first,
                                  lastDate: DateTime(2100));
                              if (d != null && mounted) {
                                setState(() => dueDate = d);
                              }
                            })
                      ],
                      const SizedBox(height: 12),
                      Panel(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            TextFormField(
                                key: const ValueKey('transaction-note'),
                                controller: note,
                                onChanged: suggestCategory,
                                maxLines: 3,
                                maxLength: 500,
                                decoration: const InputDecoration(
                                    labelText: 'Ghi chú',
                                    hintText: 'Bạn đã chi tiêu cho điều gì?')),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, children: [
                              for (final s in _notes[kind] ??
                                  const ['Hẹn trả', 'Trả một phần', 'Tiền lãi'])
                                ActionChip(
                                    label: Text(s),
                                    onPressed: () {
                                      note.text = s;
                                      suggestCategory(s);
                                    })
                            ]),
                          ])),
                      if (photo != null) ...[
                        const SizedBox(height: 12),
                        Panel(
                            padding: const EdgeInsets.all(8),
                            child: Row(children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: GestureDetector(
                                      onTap: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => Dialog(
                                              child: InteractiveViewer(
                                                  child: Image.file(File(photo!))))),
                                      child: Image.file(File(photo!),
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const SizedBox.square(
                                              dimension: 64,
                                              child: Icon(Icons.broken_image_outlined))))),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('Ảnh hóa đơn đính kèm (lưu trên thiết bị)')),
                              IconButton(
                                  tooltip: 'Bỏ ảnh',
                                  onPressed: () => setState(() => photo = null),
                                  icon: const Icon(Icons.close)),
                            ])),
                      ],
                      if (widget.entry == null) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<RepeatFrequency?>(
                            initialValue: repeat,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Lặp lại định kỳ',
                                prefixIcon: Icon(Icons.event_repeat)),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Không lặp lại')),
                              for (final f in RepeatFrequency.values)
                                DropdownMenuItem(value: f, child: Text(f.label)),
                            ],
                            onChanged: (v) => setState(() => repeat = v)),
                      ] else if (widget.entry!.recurringId != null)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Row(children: [
                              Icon(Icons.event_repeat, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      'Giao dịch được tạo tự động từ một giao dịch định kỳ.',
                                      style: TextStyle(fontSize: 12))),
                            ])),
                      const SizedBox(height: 12),
                      SwitchListTile(
                          title: const Text('Không tính vào báo cáo'),
                          subtitle: const Text(
                              'Số dư ví vẫn cập nhật theo giao dịch.'),
                          value: excluded,
                          onChanged: (v) => setState(() => excluded = v)),
                      if (widget.entry != null) ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.accentRed),
                            label: const Text('Xóa giao dịch',
                                style: TextStyle(color: AppColors.accentRed)),
                            onPressed: () async {
                              if (await confirmDelete(
                                      context, 'Xóa giao dịch này?') &&
                                  context.mounted) {
                                setState(() => saving = true);
                                p.deleteEntry(widget.entry!.id);
                                message(context, 'Đã xóa giao dịch.');
                                Navigator.pop(context, true);
                              }
                            })
                      ],
                    ]))));
  }
}
