import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui.dart';
import 'calendar_header.dart';

/// 年视图：12 个月柱状图，点柱子进月视图。
class YearBars extends StatelessWidget {
  const YearBars({
    super.key,
    required this.year,
    required this.monthlyTotals,
    required this.currentMonth,
    required this.onSelectMonth,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    this.showToday = false,
  });

  final int year;

  /// 长度 12，下标 0 = 1 月。
  final List<int> monthlyTotals;
  final int? currentMonth;
  final ValueChanged<int> onSelectMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    var maxTotal = 0;
    for (final total in monthlyTotals) {
      if (total > maxTotal) maxTotal = total;
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          CalendarHeader(
            title: '$year年',
            onPrev: onPrev,
            onNext: onNext,
            onToday: onToday,
            showToday: showToday,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 12; i++)
                  Expanded(
                    child: _MonthBar(
                      month: i + 1,
                      total: i < monthlyTotals.length ? monthlyTotals[i] : 0,
                      ratio: maxTotal == 0
                          ? 0
                          : (i < monthlyTotals.length ? monthlyTotals[i] : 0) /
                                maxTotal,
                      isCurrent: currentMonth == i + 1,
                      onTap: () => onSelectMonth(i + 1),
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

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.total,
    required this.ratio,
    required this.isCurrent,
    required this.onTap,
  });

  final int month;
  final int total;
  final double ratio;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            height: 12,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                total > 0 ? '$total' : '',
                style: const TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: total == 0
                  ? Container(
                      width: 14,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.track,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )
                  : FractionallySizedBox(
                      heightFactor: ratio.clamp(0.08, 1.0).toDouble(),
                      child: Container(
                        width: 14,
                        decoration: BoxDecoration(
                          color: isCurrent ? null : AppColors.heat3,
                          gradient: isCurrent ? AppColors.gradient : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$month',
            style: TextStyle(
              fontSize: 9,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent ? AppColors.ink : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
