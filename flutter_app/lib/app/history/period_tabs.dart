import 'package:flutter/material.dart';

import '../../data/period.dart';
import '../theme.dart';

/// 日 / 周 / 月 / 年 分段控件。
class PeriodTabs extends StatelessWidget {
  const PeriodTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final PeriodKind selected;
  final ValueChanged<PeriodKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final kind in PeriodKind.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(kind),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: kind == selected
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: kind == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x141C335F),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    kind.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: kind == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: kind == selected ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
