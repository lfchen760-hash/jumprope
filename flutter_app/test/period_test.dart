import 'package:flutter_test/flutter_test.dart';
import 'package:jumprope_app/data/period.dart';
import 'package:jumprope_app/data/period_stats.dart';

void main() {
  group('周起点', () {
    test('周一从当天开始', () {
      expect(weekStartOf('2026-11-09'), '2026-11-09');
    });

    test('周日回到本周一', () {
      expect(weekStartOf('2026-11-08'), '2026-11-02');
    });

    test('跨年周', () {
      expect(weekStartOf('2026-01-01'), '2025-12-29');
    });
  });

  group('周期范围', () {
    test('月范围包含闰年 2 月 29 日', () {
      final range = rangeFor(PeriodKind.month, '2024-02-10');
      expect(range.start, '2024-02-01');
      expect(range.end, '2024-02-29');
    });

    test('年范围是 1 月 1 日到 12 月 31 日', () {
      final range = rangeFor(PeriodKind.year, '2026-07-15');
      expect(range.start, '2026-01-01');
      expect(range.end, '2026-12-31');
    });

    test('周范围周一到周日', () {
      final range = rangeFor(PeriodKind.week, '2026-11-08');
      expect(range.start, '2026-11-02');
      expect(range.end, '2026-11-08');
    });
  });

  group('周期平移', () {
    test('月平移跨年', () {
      final jan = rangeFor(PeriodKind.month, '2026-01-15');
      final dec = shiftRange(jan, -1);
      expect(dec.start, '2025-12-01');
      expect(dec.end, '2025-12-31');
    });

    test('年平移', () {
      final y = rangeFor(PeriodKind.year, '2026-05-01');
      final prev = shiftRange(y, -1);
      expect(prev.start, '2025-01-01');
      expect(prev.end, '2025-12-31');
    });

    test('周平移 7 天', () {
      final w = rangeFor(PeriodKind.week, '2026-11-09');
      final prev = shiftRange(w, -1);
      expect(prev.start, '2026-11-02');
      expect(prev.end, '2026-11-08');
    });

    test('日平移 1 天', () {
      final d = rangeFor(PeriodKind.day, '2026-03-01');
      expect(shiftRange(d, -1).start, '2026-02-28');
    });

    test('月末加一个月会落到月末', () {
      expect(addMonths('2026-01-31', 1), '2026-02-28');
    });
  });

  group('月历格子', () {
    test('周一开头，前面补空格', () {
      final cells = monthCells('2026-11-01');
      expect(cells.length, 36); // 6 个空格 + 30 天
      expect(cells.take(6).every((c) => c == null), isTrue);
      expect(cells[6], '2026-11-01'); // 2026-11-01 是周日
      expect(cells.whereType<String>().length, 30);
    });

    test('2 月天数正确', () {
      expect(monthCells('2024-02-01').whereType<String>().length, 29);
      expect(monthCells('2026-02-01').whereType<String>().length, 28);
    });
  });

  group('文案', () {
    test('四种周期的标题', () {
      expect(rangeTitle(rangeFor(PeriodKind.day, '2026-11-09')), '2026年11月9日');
      expect(rangeTitle(rangeFor(PeriodKind.week, '2026-11-09')), '11月9–15日');
      expect(rangeTitle(rangeFor(PeriodKind.month, '2026-11-09')), '2026年11月');
      expect(rangeTitle(rangeFor(PeriodKind.year, '2026-11-09')), '2026年');
    });

    test('周跨月', () {
      final range = rangeFor(PeriodKind.week, '2026-11-01');
      expect(rangeTitle(range), '10月26日–11月1日');
    });

    test('当前月只写到今天', () {
      final range = rangeFor(PeriodKind.month, '2026-11-01');
      expect(rangeSpan(range, '2026-11-12'), '11月1–12日');
    });

    test('过去月写完整区间', () {
      final range = rangeFor(PeriodKind.month, '2026-10-01');
      expect(rangeSpan(range, '2026-11-12'), '10月1–31日');
    });

    test('今天 / 昨天', () {
      final today = rangeFor(PeriodKind.day, '2026-11-12');
      expect(rangeSpan(today, '2026-11-12'), startsWith('今天'));
      final yesterday = rangeFor(PeriodKind.day, '2026-11-11');
      expect(rangeSpan(yesterday, '2026-11-12'), startsWith('昨天'));
    });
  });

  group('环比', () {
    test('上期为 0 返回 null', () {
      expect(percentChange(300, 0), isNull);
    });

    test('增长和下降', () {
      expect(percentChange(948, 846), 12);
      expect(percentChange(800, 1000), -20);
    });
  });

  group('完成度分档', () {
    test('0 / 低于 50% / 50% / 100% / 150%', () {
      expect(calendarLevel(0, 300), 0);
      expect(calendarLevel(149, 300), 1);
      expect(calendarLevel(150, 300), 2);
      expect(calendarLevel(299, 300), 2);
      expect(calendarLevel(300, 300), 3);
      expect(calendarLevel(449, 300), 3);
      expect(calendarLevel(450, 300), 4);
    });
  });
}
