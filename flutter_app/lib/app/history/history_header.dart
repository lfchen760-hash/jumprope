import 'package:flutter/material.dart';

import '../../data/child_profile.dart';
import '../theme.dart';

/// 记录页标题、孩子摘要、列表/日历切换、年份选择。
class HistoryHeader extends StatelessWidget {
  const HistoryHeader({
    super.key,
    required this.profile,
    required this.year,
    required this.years,
    required this.onYearSelected,
    required this.calendarMode,
    required this.onToggleMode,
  });

  final ChildProfile? profile;
  final int year;
  final List<int> years;
  final ValueChanged<int> onYearSelected;
  final bool calendarMode;
  final VoidCallback onToggleMode;

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
        const SizedBox(width: 8),
        _ModePill(calendarMode: calendarMode, onTap: onToggleMode),
        if (calendarMode) ...[
          const SizedBox(width: 6),
          PopupMenuButton<int>(
            tooltip: '选择年份',
            initialValue: year,
            onSelected: onYearSelected,
            itemBuilder: (context) => [
              for (final y in years)
                PopupMenuItem<int>(value: y, child: Text('$y 年')),
            ],
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 7, 7),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 1),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 15,
                    color: AppColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.calendarMode, required this.onTap});

  final bool calendarMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          color: AppColors.track,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              calendarMode
                  ? Icons.view_list_outlined
                  : Icons.calendar_month_outlined,
              size: 14,
              color: AppColors.inkSoft,
            ),
            const SizedBox(width: 4),
            Text(
              calendarMode ? '列表' : '日历',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
