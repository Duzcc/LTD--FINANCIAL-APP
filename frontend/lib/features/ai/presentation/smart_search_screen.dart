import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/entry_tile.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';

/// Tìm giao dịch bằng câu tự nhiên: "cafe tháng trước trên 50k", "grab tuần này".
/// Máy chủ hiểu bộ lọc thời gian/số tiền và xếp hạng theo ngữ nghĩa; khi ngoại
/// tuyến thì tìm theo từ khóa không dấu trên thiết bị.
class SmartSearchScreen extends StatefulWidget {
  const SmartSearchScreen({super.key});
  @override
  State<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends State<SmartSearchScreen> {
  final query = TextEditingController();
  List<MoneyEntry>? results;
  String? info;
  bool busy = false;
  static const examples = ['cafe tháng này', 'grab tuần trước', 'chi trên 1tr', 'tiền điện năm nay'];

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search(String q) async {
    if (q.trim().isEmpty) return;
    final p = context.read<FinanceProvider>();
    setState(() => busy = true);
    List<MoneyEntry> found;
    String note;
    try {
      if (!p.signedIn) throw const ApiException(0, 'OFFLINE', '');
      final (ids, filters) = await AiRepository(p).search(q.trim());
      final byId = {for (final e in p.entries) e.id: e};
      found = [for (final id in ids) if (byId[id] != null) byId[id]!];
      const labels = {
        'start': 'thời gian',
        'end': 'thời gian',
        'min_amount': 'số tiền',
        'max_amount': 'số tiền',
        'kinds': 'loại giao dịch',
        'text': 'từ khóa',
      };
      final used = {for (final k in filters.keys) labels[k] ?? k};
      note = 'AI máy chủ${used.isEmpty ? '' : ' • hiểu theo ${used.join(', ')}'}';
    } on ApiException {
      final words = foldVietnamese(q).split(' ').where((w) => w.length > 1).toList();
      found = p.entries.where((e) {
        final hay = foldVietnamese('${e.note} ${p.category(e.categoryId)?.name ?? ''} ${p.personName(e.personId)}');
        return words.every(hay.contains);
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      note = 'Tìm theo từ khóa trên thiết bị';
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      results = found.take(100).toList();
      info = note;
    });
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Tìm kiếm bằng AI',
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: search,
            decoration: InputDecoration(
                hintText: 'Ví dụ: cafe tháng trước trên 50k',
                prefixIcon: const Icon(Icons.manage_search),
                suffixIcon: IconButton(onPressed: () => search(query.text), icon: const Icon(Icons.arrow_forward)))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in examples)
            ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  query.text = e;
                  search(e);
                }),
        ]),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${results!.length} kết quả • $info', style: const TextStyle(fontSize: 12))),
        for (final e in results ?? const <MoneyEntry>[]) EntryTile(e),
        if (results != null && results!.isEmpty)
          const EmptyView(title: 'Không tìm thấy', subtitle: 'Thử diễn đạt khác hoặc mở rộng khoảng thời gian.', icon: Icons.search_off),
      ]));
}
