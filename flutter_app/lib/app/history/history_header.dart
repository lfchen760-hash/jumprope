import 'package:flutter/material.dart';

import '../../data/child_profile.dart';
import '../theme.dart';

/// 记录页标题、孩子摘要、年份选择。
class HistoryHeader extends StatelessWidget {
  const HistoryHeader({
    super.key,
    required this.profile,
    required this.year,
    required this.years,
    required this.onYearSelected,
  });

  final ChildProfile? profile;
  final int year;
  final List<int> years;
  final ValueChanged<int> onYearSelected;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final subtitle = p == null
        ? '每一跳都算数'
        : p.grade == null
        ? p.nickname
        : '${p.nickname} · ${p.displayGrade}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('记录', style: inkTitle(28)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<int>(
          tooltip: '选择年份',
          initialValue: year,
          onSelected: onYearSelected,
          itemBuilder: (context) => [
            for (final y in years)
              PopupMenuItem<int>(value: y, child: Text('$y 年')),
          ],
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            decoration: BoxDecoration(
              color: AppColors.track,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$year 年',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
