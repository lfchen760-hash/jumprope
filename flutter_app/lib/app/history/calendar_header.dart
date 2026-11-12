import 'package:flutter/material.dart';

import '../theme.dart';

/// 日历卡片的标题 + 上一页 / 下一页 / 回到今天。
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.title,
    required this.onPrev,
    required this.onNext,
    this.onToday,
    this.showToday = false,
  });

  final String title;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onToday;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        if (showToday && onToday != null)
          TextButton(
            onPressed: onToday,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: AppColors.brandOrange,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('今天'),
          ),
        _Arrow(icon: Icons.chevron_left, onTap: onPrev),
        _Arrow(icon: Icons.chevron_right, onTap: onNext),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(icon, size: 22, color: AppColors.inkSoft),
      ),
    );
  }
}
