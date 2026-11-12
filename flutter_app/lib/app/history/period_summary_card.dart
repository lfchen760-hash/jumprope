import 'package:flutter/material.dart';

import '../../data/period_stats.dart';
import '../theme.dart';
import '../ui.dart';

/// 周期汇总：总次数、活跃天数、最好、连续、活跃日均。
class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({
    super.key,
    required this.spanLabel,
    required this.stats,
    this.compareText,
    this.comparePositive,
  });

  final String spanLabel;
  final PeriodStats stats;

  /// 例如「+12% 较上期」「本周期进行中」。
  final String? compareText;

  /// null = 中性灰；true = 绿色；false = 橙色。
  final bool? comparePositive;

  @override
  Widget build(BuildContext context) {
    final color = comparePositive == null
        ? AppColors.muted
        : comparePositive!
        ? AppColors.success
        : AppColors.warn;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spanLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              '${stats.total}',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4, left: 4),
                          child: Text(
                            '个',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (compareText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        compareText!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Metric(label: '活跃', value: '${stats.activeDays} 天'),
                  _Metric(label: '最好', value: '${stats.best} 个'),
                  _Metric(label: '连续', value: '${stats.streak} 天'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          Text(
            '活跃日均 ${stats.avgPerActiveDay.round()} 个',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 6),
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
