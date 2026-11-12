import 'date_utils.dart';

/// 记录页的四个周期。
enum PeriodKind { day, week, month, year }

extension PeriodKindLabel on PeriodKind {
  String get label => switch (this) {
    PeriodKind.day => '日',
    PeriodKind.week => '周',
    PeriodKind.month => '月',
    PeriodKind.year => '年',
  };
}

/// 一个闭区间的本地日期范围，`start` / `end` 都是 `YYYY-MM-DD`。
class PeriodRange {
  final PeriodKind kind;
  final String start;
  final String end;

  const PeriodRange({
    required this.kind,
    required this.start,
    required this.end,
  });

  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;

  @override
  String toString() => '${kind.name} $start..$end';
}

String monthStartOf(String date) => '${date.substring(0, 7)}-01';

String monthEndOf(String date) {
  final d = parseLocalDate(date);
  return localDateOf(DateTime(d.year, d.month + 1, 0));
}

String yearStartOf(int year) => '$year-01-01';

String yearEndOf(int year) => '$year-12-31';

/// 周一为一周的第一天。
String weekStartOf(String date) {
  final weekday = parseLocalDate(date).weekday; // 1 = 周一
  return addDays(date, -(weekday - 1));
}

/// 平移月份；目标月没有这一天时落在月末（例如 1/31 → 2/28）。
String addMonths(String date, int delta) {
  final d = parseLocalDate(date);
  final target = DateTime(d.year, d.month + delta, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  final day = d.day <= lastDay ? d.day : lastDay;
  return localDateOf(DateTime(target.year, target.month, day));
}

PeriodRange rangeFor(PeriodKind kind, String anchor) => switch (kind) {
  PeriodKind.day => PeriodRange(kind: kind, start: anchor, end: anchor),
  PeriodKind.week => _weekRange(anchor),
  PeriodKind.month => _monthRange(anchor),
  PeriodKind.year => _yearRange(anchor),
};

PeriodRange _weekRange(String anchor) {
  final start = weekStartOf(anchor);
  return PeriodRange(
    kind: PeriodKind.week,
    start: start,
    end: addDays(start, 6),
  );
}

PeriodRange _monthRange(String anchor) => PeriodRange(
  kind: PeriodKind.month,
  start: monthStartOf(anchor),
  end: monthEndOf(anchor),
);

PeriodRange _yearRange(String anchor) {
  final year = parseLocalDate(anchor).year;
  return PeriodRange(
    kind: PeriodKind.year,
    start: yearStartOf(year),
    end: yearEndOf(year),
  );
}

/// 按周期平移：日 ±1 天、周 ±7 天、月 ±1 月、年 ±1 年。
PeriodRange shiftRange(PeriodRange range, int delta) {
  if (delta == 0) return range;
  return switch (range.kind) {
    PeriodKind.day => rangeFor(range.kind, addDays(range.start, delta)),
    PeriodKind.week => rangeFor(range.kind, addDays(range.start, 7 * delta)),
    PeriodKind.month => rangeFor(range.kind, addMonths(range.start, delta)),
    PeriodKind.year => rangeFor(
      range.kind,
      yearStartOf(parseLocalDate(range.start).year + delta),
    ),
  };
}

PeriodRange previousRange(PeriodRange range) => shiftRange(range, -1);

/// 月历格子：周一开头，前面补 null；只返回当月的日期。
List<String?> monthCells(String anyDateInMonth) {
  final first = parseLocalDate(monthStartOf(anyDateInMonth));
  final leading = first.weekday - 1;
  final days = DateTime(first.year, first.month + 1, 0).day;
  return [
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= days; d++)
      localDateOf(DateTime(first.year, first.month, d)),
  ];
}

String weekdayCn(String date) =>
    '周${'一二三四五六日'[parseLocalDate(date).weekday - 1]}';

String shortMonthDay(String date) {
  final d = parseLocalDate(date);
  return '${d.month}月${d.day}日';
}

String fullDate(String date) {
  final d = parseLocalDate(date);
  return '${d.year}年${d.month}月${d.day}日';
}

String _weekSpan(String start, String end) {
  final s = parseLocalDate(start);
  final e = parseLocalDate(end);
  if (s.year == e.year && s.month == e.month) {
    return '${s.month}月${s.day}–${e.day}日';
  }
  if (s.year == e.year) {
    return '${s.month}月${s.day}日–${e.month}月${e.day}日';
  }
  return '${s.year}年${s.month}月${s.day}日–'
      '${e.year}年${e.month}月${e.day}日';
}

/// 日历卡标题：日 / 周 / 月 / 年各一种写法。
String rangeTitle(PeriodRange range) => switch (range.kind) {
  PeriodKind.day => fullDate(range.start),
  PeriodKind.week => _weekSpan(range.start, range.end),
  PeriodKind.month =>
    '${parseLocalDate(range.start).year}年'
        '${parseLocalDate(range.start).month}月',
  PeriodKind.year => '${parseLocalDate(range.start).year}年',
};

/// 汇总卡上的区间说明，当前周期只写到今天。
String rangeSpan(PeriodRange range, String today) => switch (range.kind) {
  PeriodKind.day => _daySpan(range.start, today),
  PeriodKind.week => _weekSpanLabel(range, today),
  PeriodKind.month => _monthSpan(range, today),
  PeriodKind.year => _yearSpan(range, today),
};

String _daySpan(String date, String today) {
  if (date == today) return '今天 · ${weekdayCn(date)}';
  if (date == addDays(today, -1)) return '昨天 · ${weekdayCn(date)}';
  return '${shortMonthDay(date)} · ${weekdayCn(date)}';
}

String _weekSpanLabel(PeriodRange range, String today) {
  final span = _weekSpan(range.start, range.end);
  return range.contains(today) ? '本周 · $span' : span;
}

String _monthSpan(PeriodRange range, String today) {
  final month = parseLocalDate(range.start).month;
  final day = range.contains(today)
      ? parseLocalDate(today).day
      : parseLocalDate(range.end).day;
  return '$month月1–$day日';
}

String _yearSpan(PeriodRange range, String today) {
  if (!range.contains(today)) return '1月1日–12月31日';
  final t = parseLocalDate(today);
  return '1月1日–${t.month}月${t.day}日';
}

/// 最佳卡片标题。
String bestLabel(PeriodKind kind) => switch (kind) {
  PeriodKind.day => '当日最佳',
  PeriodKind.week => '本周最佳',
  PeriodKind.month => '本月最佳',
  PeriodKind.year => '本年最佳',
};

/// 环比百分比；上期为 0 时无法计算（不显示 +∞）。
int? percentChange(int current, int previous) {
  if (previous <= 0) return null;
  return ((current - previous) * 100 / previous).round();
}
