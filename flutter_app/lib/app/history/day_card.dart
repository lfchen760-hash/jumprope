import 'package:flutter/material.dart';

import '../../data/period.dart';
import '../theme.dart';
import '../ui.dart';
import 'calendar_header.dart';

/// 日视图：当日完成度圆环 + 关键数字。
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.date,
    required this.total,
    required this.goal,
    required this.sessionCount,
    required this.best,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    this.showToday = false,
  });

  final String date;
  final int total;
  final int goal;
  final int sessionCount;
  final int best;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : total / goal;
    final done = goal > 0 && total >= goal;
    final left = goal - total;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          CalendarHeader(
            title: rangeTitle(rangeFor(PeriodKind.day, date)),
            onPrev: onPrev,
            onNext: onNext,
            onToday: onToday,
            showToday: showToday,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GradientRing(
                size: 132,
                progress: progress,
                stroke: 11,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '个',
                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(label: '训练', value: '$sessionCount 次'),
                    _Line(label: '最好', value: best > 0 ? '$best 个' : '—'),
                    _Line(label: '目标', value: '$goal 个'),
                    const SizedBox(height: 8),
                    Text(
                      total == 0
                          ? (sessionCount == 0 ? '这天还没有记录' : '没有计入统计的记录')
                          : done
                          ? '目标已完成'
                          : '还差 $left 个',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: total == 0
                            ? AppColors.muted
                            : done
                            ? AppColors.success
                            : AppColors.inkSoft,
                      ),
                    ),
                    if (goal > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '完成 ${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
