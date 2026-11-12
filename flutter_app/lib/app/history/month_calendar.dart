import 'package:flutter/material.dart';

import '../../data/period.dart';
import '../theme.dart';
import '../ui.dart';
import 'calendar_header.dart';

/// 月历热力：每格一天，颜色 = 当日完成度。
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.totals,
    required this.levels,
    required this.hasAny,
    required this.onSelectDay,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    this.showToday = false,
  });

  final String month;
  final String today;
  final Map<String, int> totals;
  final Map<String, int> levels;
  final Set<String> hasAny;
  final ValueChanged<String> onSelectDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final cells = monthCells(month);
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 7; j++)
              Expanded(child: _buildCell(cells[i + j])),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          CalendarHeader(
            title: rangeTitle(rangeFor(PeriodKind.month, month)),
            onPrev: onPrev,
            onNext: onNext,
            onToday: onToday,
            showToday: showToday,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          ...rows,
          const SizedBox(height: 8),
          Row(
            children: [
              for (var level = 1; level <= 4; level++)
                Container(
                  width: 12,
                  height: 8,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: level == 4 ? null : heatColor(level),
                    gradient: level == 4 ? AppColors.gradient : null,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 4),
              const Text(
                '颜色 = 当日完成度',
                style: TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCell(String? date) {
    if (date == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox());
    }
    final isFuture = date.compareTo(today) > 0;
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _DayCell(
          date: date,
          total: totals[date] ?? 0,
          level: levels[date] ?? 0,
          rest: (levels[date] ?? 0) == 0 && hasAny.contains(date),
          isToday: date == today,
          isFuture: isFuture,
          onTap: isFuture ? null : () => onSelectDay(date),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.total,
    required this.level,
    required this.rest,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  final String date;
  final int total;
  final int level;
  final bool rest;
  final bool isToday;
  final bool isFuture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = level <= 1;
    final day = int.parse(date.substring(8));
    final background = level == 0 && !rest
        ? AppColors.track.withOpacity(0.35)
        : heatColor(level);
    final textColor = isFuture
        ? AppColors.muted.withOpacity(0.35)
        : light
        ? AppColors.inkSoft
        : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isFuture ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: level == 4 ? null : background,
            gradient: level == 4 ? AppColors.gradient : null,
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(
                    color: light ? AppColors.ink : Colors.white,
                    width: 2,
                  )
                : null,
            boxShadow: isToday
                ? const [
                    BoxShadow(
                      color: Color(0x261C335F),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$day', style: TextStyle(fontSize: 9, color: textColor)),
              const Spacer(),
              if (total > 0)
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: textColor,
                      ),
                    ),
                  ),
                )
              else if (rest)
                Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.muted.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
