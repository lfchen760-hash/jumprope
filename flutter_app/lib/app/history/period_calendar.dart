import 'package:flutter/material.dart';

import '../../data/date_utils.dart';
import '../../data/period.dart';
import 'day_card.dart';
import 'month_calendar.dart';
import 'week_strip.dart';
import 'year_bars.dart';

/// 按周期选择日卡 / 周条 / 月历 / 年柱。
class PeriodCalendar extends StatelessWidget {
  const PeriodCalendar({
    super.key,
    required this.kind,
    required this.range,
    required this.today,
    required this.totals,
    required this.levels,
    required this.hasAny,
    required this.daySessionCount,
    required this.dayGoal,
    required this.dayBest,
    required this.monthlyTotals,
    required this.currentMonth,
    required this.onSelectDay,
    required this.onSelectMonth,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.showToday,
  });

  final PeriodKind kind;
  final PeriodRange range;
  final String today;
  final Map<String, int> totals;
  final Map<String, int> levels;
  final Set<String> hasAny;
  final int daySessionCount;
  final int dayGoal;
  final int dayBest;
  final List<int> monthlyTotals;
  final int? currentMonth;
  final ValueChanged<String> onSelectDay;
  final ValueChanged<int> onSelectMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      PeriodKind.day => DayCard(
        date: range.start,
        total: totals[range.start] ?? 0,
        goal: dayGoal,
        sessionCount: daySessionCount,
        best: dayBest,
        onPrev: onPrev,
        onNext: onNext,
        onToday: onToday,
        showToday: showToday,
      ),
      PeriodKind.week => WeekStrip(
        range: range,
        today: today,
        totals: totals,
        levels: levels,
        onSelectDay: onSelectDay,
        onPrev: onPrev,
        onNext: onNext,
        onToday: onToday,
        showToday: showToday,
      ),
      PeriodKind.month => MonthCalendar(
        month: range.start,
        today: today,
        totals: totals,
        levels: levels,
        hasAny: hasAny,
        onSelectDay: onSelectDay,
        onPrev: onPrev,
        onNext: onNext,
        onToday: onToday,
        showToday: showToday,
      ),
      PeriodKind.year => YearBars(
        year: parseLocalDate(range.start).year,
        monthlyTotals: monthlyTotals,
        currentMonth: currentMonth,
        onSelectMonth: onSelectMonth,
        onPrev: onPrev,
        onNext: onNext,
        onToday: onToday,
        showToday: showToday,
      ),
    };
  }
}
