import 'package:flutter/material.dart';

import '../../data/child_profile.dart';
import '../../data/jump_benchmark.dart';
import '../../data/session_record.dart';
import '../theme.dart';
import '../ui.dart';

/// 周期内单次最好成绩，附带 2014 国标参考线。
class PeriodBestCard extends StatelessWidget {
  const PeriodBestCard({
    super.key,
    required this.label,
    required this.best,
    required this.benchmark,
  });

  final String label;
  final SessionRecord? best;
  final BenchmarkResult? benchmark;

  @override
  Widget build(BuildContext context) {
    final session = best;
    final avg = session?.avgPerMinute;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          if (session == null)
            const Text(
              '这段时间还没有有效记录',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${session.count}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: AppColors.ink,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2, left: 3),
                  child: Text(
                    '个',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
                const Spacer(),
                Text(
                  '${sessionModeLabel(session.mode)}'
                  '${avg == null ? '' : ' · $avg 次/分'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
            if (benchmark != null) ...[
              const SizedBox(height: 6),
              Text(
                _benchmarkLine(benchmark!),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _benchmarkGood(benchmark!.level)
                      ? AppColors.success
                      : AppColors.muted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _benchmarkLine(BenchmarkResult result) {
    final table = result.table;
    final who = '${table.grade} 年级${table.gender == Gender.male ? '男生' : '女生'}';
    return '$who · ${result.message}';
  }

  bool _benchmarkGood(BenchmarkLevel level) => switch (level) {
    BenchmarkLevel.good ||
    BenchmarkLevel.excellent ||
    BenchmarkLevel.full ||
    BenchmarkLevel.bonusFull => true,
    BenchmarkLevel.pass || BenchmarkLevel.belowPass => false,
  };
}
