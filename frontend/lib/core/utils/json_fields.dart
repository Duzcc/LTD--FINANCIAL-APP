String? isoUtc(DateTime? d) => d?.toUtc().toIso8601String();

double parseNumber(Object? v) => v is num
    ? v.toDouble()
    : v is String
        ? double.tryParse(v) ?? 0
        : 0;

DateTime? parseLocalDate(Object? v) {
  if (v == null || v == '') return null;
  final d = DateTime.tryParse(v.toString());
  return d?.isUtc == true ? d!.toLocal() : d;
}
