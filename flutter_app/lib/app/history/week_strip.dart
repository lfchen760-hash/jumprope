import 'package:flutter/material.dart';

import '../../data/date_utils.dart';
import '../../data/period.dart';
import '../theme.dart';
import '../ui.dart';
import 'calendar_header.dart';

/// 周视图：周一到周日 7 根柱，柱高 = 当日次数。
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.range,
    required this.today,
    required this.totals,
    required this.levels,
    required this.onSelectDay,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    this.showToday = false,
  });

  final PeriodRange range;
  final String today;
  final Map<String, int> totals;
  final Map<String, int> levels;
  final ValueChanged<String> onSelectDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) addDays(range.start, i)];
    var maxTotal = 0;
    for (final day in days) {
      final total = totals[day] ?? 0;
      if (total > maxTotal) maxTotal = total;
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          CalendarHeader(
            title: rangeTitle(range),
            onPrev: onPrev,
            onNext: onNext,
            onToday: onToday,
            showToday: showToday,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 158,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: _DayColumn(
                      date: day,
                      total: totals[day] ?? 0,
                      level: levels[day] ?? 0,
                      isToday: day == today,
                      ratio: maxTotal == 0 ? 0 : (totals[day] ?? 0) / maxTotal,
                      onTap: () => onSelectDay(day),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.date,
    required this.total,
    required this.level,
    required this.isToday,
    required this.ratio,
    required this.onTap,
  });

  final String date;
  final int total;
  final int level;
  final bool isToday;
  final double ratio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = weekdayCn(date).substring(1);
    final day = int.parse(date.substring(8));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            weekday,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? AppColors.ink : AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: total == 0
                  ? Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: AppColors.track,
                        shape: BoxShape.circle,
                      ),
                    )
                  : FractionallySizedBox(
                      heightFactor: ratio.clamp(0.06, 1.0).toDouble(),
                      child: Container(
                        width: 18,
                        decoration: BoxDecoration(
                          color: level == 4 || isToday
                              ? null
                              : heatColor(level),
                          gradient: level == 4 || isToday
                              ? AppColors.gradient
                              : null,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$day',
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? AppColors.ink : AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 14,
            child: total > 0
                ? Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
