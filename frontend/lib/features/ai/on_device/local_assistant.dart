import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';
import 'package:finance_app/features/ai/on_device/insights.dart';

/// Trợ lý tài chính chạy trên thiết bị (không cần mạng): nhận diện ý định của
/// câu hỏi tiếng Việt và trả lời bằng dữ liệu thật của người dùng.
/// Khi đăng nhập và máy chủ có cấu hình mô hình ngôn ngữ, ứng dụng dùng AI ở
/// backend; trợ lý này là phương án dự phòng.
class LocalAssistant {
  LocalAssistant(this.p, {DateTime? now}) : now = now ?? DateTime.now();
  final FinanceProvider p;
  final DateTime now;

  String _m(double v, [String? unit]) {
    final u = unit ?? p.currency;
    final s = v.abs().round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    return '${v < 0 ? '-' : ''}$s ${u == 'VND' ? '₫' : u}';
  }

  static const suggestions = [
    'Tháng này tôi đã chi bao nhiêu?',
    'Tôi chi nhiều nhất cho việc gì?',
    'Dự báo chi tiêu cuối tháng',
    'Ngân sách của tôi thế nào?',
    'Ai đang nợ tôi?',
    'Làm sao để tiết kiệm hơn?',
  ];

  bool _has(String f, List<String> words) =>
      words.any((w) => RegExp('\\b$w\\b').hasMatch(f));

  String answer(String question) {
    final f = foldVietnamese(question);
    final insights = FinanceInsights(p, now: now);
    final today = DateTime(now.year, now.month, now.day);

    // Câu hỏi về một danh mục cụ thể.
    for (final c in p.categories) {
      final n = foldVietnamese(c.name);
      if (n.isNotEmpty && f.contains(n) && !_has(f, ['ngan sach'])) {
        final month = p.total(now, income: c.income, categoryId: c.id);
        final prev = p.total(DateTime(now.year, now.month - 1), income: c.income, categoryId: c.id);
        return '${c.income ? 'Thu từ' : 'Chi cho'} ${c.name} tháng này: ${_m(month)}'
            '${prev > 0 ? ' (tháng trước ${_m(prev)}, ${month >= prev ? 'tăng' : 'giảm'} ${((month - prev).abs() / prev * 100).round()}%)' : ''}.';
      }
    }
    if (_has(f, ['du bao', 'cuoi thang', 'du kien'])) {
      final fc = insights.forecast();
      return 'Đến nay bạn đã chi ${_m(fc.spent)}. Với mức trung bình ${_m(fc.dailyAverage)}/ngày, dự kiến cả tháng khoảng ${_m(fc.projected)}'
          '${fc.target == null ? '.' : fc.overBudget ? ', vượt mục tiêu ${_m(fc.target!)} khoảng ${_m(fc.projected - fc.target!)}. Hãy giảm khoảng ${_m((fc.projected - fc.target!) / (fc.daysLeft == 0 ? 1 : fc.daysLeft))}/ngày trong ${fc.daysLeft} ngày còn lại.' : ', trong mục tiêu ${_m(fc.target!)}.'}';
    }
    if (_has(f, ['ngan sach', 'muc tieu', 'han muc'])) {
      final list = p.budgets
          .where((b) => b.month.year == now.year && b.month.month == now.month && b.currency == p.currency)
          .toList();
      if (list.isEmpty) return 'Bạn chưa đặt ngân sách cho tháng này. Vào mục Ngân sách để đặt mục tiêu tổng và theo từng danh mục.';
      return [
        'Tình hình ngân sách tháng ${now.month}:',
        for (final b in list)
          '• ${b.categoryId == null ? (b.income ? 'Mục tiêu thu' : 'Tổng chi') : p.category(b.categoryId)?.name}: ${_m(p.used(b))} / ${_m(b.amount)}'
              '${!p.budgetIncome(b) && p.used(b) > b.amount ? ' – đã vượt!' : ''}',
      ].join('\n');
    }
    if (_has(f, ['no', 'vay', 'muon'])) {
      final debtors = <String>[];
      for (final person in p.people) {
        final r = p.debt(borrowed: false, personId: person.id);
        final pay = p.debt(borrowed: true, personId: person.id);
        if (r > 0) debtors.add('• ${person.name} nợ bạn ${_m(r)}');
        if (pay > 0) debtors.add('• Bạn nợ ${person.name} ${_m(pay)}');
      }
      if (debtors.isEmpty) return 'Hiện không có khoản vay/nợ nào chưa tất toán.';
      return ['Công nợ hiện tại:', ...debtors].join('\n');
    }
    if (_has(f, ['so du', 'con bao nhieu', 'tai san', 'tong tien'])) {
      return [
        'Tổng số dư: ${_m(p.totalBalance(p.currency))}.',
        for (final w in p.wallets) '• ${w.name}: ${_m(p.balance(w.id), w.currency)}',
        if (p.hasManyCurrencies) 'Quy đổi mọi tiền tệ ≈ ${_m(p.convertedTotal(p.currency))}.',
      ].join('\n');
    }
    if (_has(f, ['nhieu nhat', 'lon nhat', 'ton nhat', 'top'])) {
      final s = insights.summary()['topCategories'] as List;
      if (s.isEmpty) return 'Tháng này chưa có khoản chi nào.';
      return 'Các nhóm chi lớn nhất tháng này:\n${s.map((e) => '• $e').join('\n')}';
    }
    if (_has(f, ['hom nay', 'tuan nay', 'hom qua'])) {
      final DateTime from;
      final String label;
      if (_has(f, ['tuan nay'])) {
        from = today.subtract(Duration(days: today.weekday - 1));
        label = 'Tuần này';
      } else if (_has(f, ['hom qua'])) {
        from = today.subtract(const Duration(days: 1));
        label = 'Hôm qua';
      } else {
        from = today;
        label = 'Hôm nay';
      }
      final to = label == 'Hôm qua' ? today : today.add(const Duration(days: 1));
      return '$label bạn đã chi ${_m(p.sumBetween(from, to, income: false))} và thu ${_m(p.sumBetween(from, to, income: true))}.';
    }
    if (_has(f, ['tiet kiem', 'loi khuyen', 'lam sao', 'goi y', 'nen', 'cat giam'])) {
      final tips = insights.all().where((i) => i.level != InsightLevel.good).take(3).toList();
      final income = p.total(now, income: true);
      return [
        if (income > 0)
          'Theo quy tắc 50/30/20, với thu nhập ${_m(income)} bạn nên để dành ít nhất ${_m(income * .2)} mỗi tháng.',
        for (final t in tips) '• ${t.title}: ${t.detail}',
        if (tips.isEmpty) '• Chi tiêu của bạn đang ổn định. Hãy duy trì và đặt ngân sách cho các nhóm chi lớn.',
        '• Tạo giao dịch định kỳ "Nạp tiết kiệm" để tự động để dành ngay khi nhận lương.',
      ].join('\n');
    }
    if (_has(f, ['thu nhap', 'thu', 'luong'])) {
      return 'Thu nhập tháng này: ${_m(p.total(now, income: true))} (tháng trước ${_m(p.total(DateTime(now.year, now.month - 1), income: true))}).';
    }
    if (_has(f, ['chi', 'tieu', 'xai', 'het'])) {
      final spent = p.total(now, income: false);
      final prev = p.total(DateTime(now.year, now.month - 1), income: false);
      return 'Tháng này bạn đã chi ${_m(spent)}'
          '${prev > 0 ? ', tháng trước ${_m(prev)}' : ''}. Thu nhập ${_m(p.total(now, income: true))}.';
    }
    final top = insights.all().take(2).map((i) => '• ${i.title}').join('\n');
    return 'Mình có thể trả lời về chi tiêu, thu nhập, số dư, ngân sách, công nợ và dự báo. Ví dụ: "Tháng này tôi chi bao nhiêu cho ăn uống?"'
        '${top.isEmpty ? '' : '\n\nĐiểm đáng chú ý:\n$top'}';
  }
}
