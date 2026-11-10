import 'package:finance_app/core/utils/json_fields.dart';
import 'package:finance_app/features/finance/domain/entities/entry_kind.dart';

class MoneyEntry {
  const MoneyEntry(
      {required this.id,
      required this.kind,
      required this.amount,
      required this.walletId,
      required this.date,
      this.destinationId,
      this.categoryId,
      this.personId,
      this.note = '',
      this.dueDate,
      this.excluded = false,
      this.photo,
      this.recurringId});
  final String id, walletId, note;
  final String? destinationId, categoryId, personId;

  final String? photo;

  final String? recurringId;
  MoneyEntry copyWith({String? photo, bool clearPhoto = false}) => MoneyEntry(
      id: id,
      kind: kind,
      amount: amount,
      walletId: walletId,
      date: date,
      destinationId: destinationId,
      categoryId: categoryId,
      personId: personId,
      note: note,
      dueDate: dueDate,
      excluded: excluded,
      photo: clearPhoto ? null : photo ?? this.photo,
      recurringId: recurringId);
  final EntryKind kind;
  final double amount;
  final DateTime date;
  final DateTime? dueDate;
  final bool excluded;
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'walletId': walletId,
        'date': isoUtc(date),
        'destinationId': destinationId,
        'categoryId': categoryId,
        'personId': personId,
        'note': note,
        'dueDate': isoUtc(dueDate),
        'excluded': excluded,
        'photo': photo,
        'recurringId': recurringId
      };
  factory MoneyEntry.fromJson(Map<String, dynamic> j) => MoneyEntry(
      id: j['id'],
      kind: EntryKind.values.byName(j['kind']),
      amount: parseNumber(j['amount']),
      walletId: j['walletId'],
      date: parseLocalDate(j['date'])!,
      destinationId: j['destinationId'],
      categoryId: j['categoryId'],
      personId: j['personId'],
      note: j['note'] ?? '',
      dueDate: parseLocalDate(j['dueDate']),
      excluded: j['excluded'] == true,
      photo: j['photo'],
      recurringId: j['recurringId']);
}
