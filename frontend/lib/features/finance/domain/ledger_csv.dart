import 'package:finance_app/features/finance/domain/ledger_queries.dart';

const _header = ['Ngày', 'Loại', 'Số tiền', 'Tiền tệ', 'Ví', 'Ví nhận', 'Danh mục', 'Đối tượng', 'Ghi chú'];

String ledgerCsv(LedgerQueries ledger) {
  String quote(Object? s) => '"${(s ?? '').toString().replaceAll('"', '""')}"';
  final rows = [
    _header,
    for (final e in ledger.entries)
      [
        e.date.toIso8601String(),
        e.kind.label,
        e.amount,
        ledger.findWallet(e.walletId)?.currency ?? '',
        ledger.findWallet(e.walletId)?.name ?? '',
        ledger.findWallet(e.destinationId)?.name ?? '',
        ledger.category(e.categoryId)?.name ?? '',
        ledger.personName(e.personId),
        e.note,
      ],
  ];
  return '\u{FEFF}${rows.map((row) => row.map(quote).join(',')).join('\r\n')}';
}
