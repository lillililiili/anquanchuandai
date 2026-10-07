typedef JsonMap = Map<String, dynamic>;

JsonMap jsonMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
List<JsonMap> jsonList(Object? value) =>
    value is List ? value.whereType<Map>().map(jsonMap).toList() : <JsonMap>[];
String idOf(Object? value) => value == null ? '' : value.toString();
String textOf(Object? value, [String fallback = '—']) =>
    value == null || value.toString().trim().isEmpty
    ? fallback
    : value.toString();
int intOf(Object? value, [int fallback = 0]) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
String formatTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '时间未知';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

class WearPage {
  final List<JsonMap> records;
  final int total;
  final int current;
  final int size;
  const WearPage({
    required this.records,
    required this.total,
    required this.current,
    required this.size,
  });
  bool get hasMore => current * size < total;
  factory WearPage.fromJson(Object? value) {
    final data = jsonMap(value);
    if (data['records'] is! List || data['total'] == null) {
      throw const FormatException('分页响应缺少 records 或 total');
    }
    return WearPage(
      records: jsonList(data['records']),
      total: intOf(data['total']),
      current: intOf(data['current'], 1),
      size: intOf(data['size'], 20),
    );
  }
}
