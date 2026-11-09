/// 本地日期工具：日期一律用 `YYYY-MM-DD` 字符串做分组键。
String two(int n) => n.toString().padLeft(2, '0');

String localDateOf(DateTime dt) => '${dt.year}-${two(dt.month)}-${two(dt.day)}';

String todayLocalDate() => localDateOf(DateTime.now());

DateTime parseLocalDate(String s) => DateTime.parse(s);

String addDays(String date, int days) {
  final d = parseLocalDate(date).add(Duration(days: days));
  return localDateOf(d);
}
