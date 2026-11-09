import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 圆角白卡片（设计稿圆角 24，轻阴影）。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141C335F),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: card,
      ),
    );
  }
}

/// 主按钮：橙→粉渐变，白字。
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.actionGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33F26A0A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: AppColors.actionPink),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度环 / 结果表盘。`progress` 0–1。
class GradientRing extends StatelessWidget {
  const GradientRing({
    super.key,
    required this.size,
    this.progress = 1,
    this.stroke = 11,
    this.ticks = 24,
    this.child,
  });

  final double size;
  final double progress;
  final double stroke;
  final int ticks;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress.clamp(0.0, 1.0).toDouble(),
                stroke: stroke,
                ticks: ticks,
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.stroke,
    required this.ticks,
  });

  final double progress;
  final double stroke;
  final int ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final arcRadius = size.width / 2 - 18 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);

    // 刻度
    if (ticks > 0) {
      final tickPaint = Paint()
        ..color = const Color(0xFFE0D7C6)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final outer = size.width / 2 - 3;
      for (var i = 0; i < ticks; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / ticks;
        final p1 = center + Offset(math.cos(a), math.sin(a)) * outer;
        final p2 = center + Offset(math.cos(a), math.sin(a)) * (outer - 5);
        canvas.drawLine(p1, p2, tickPaint);
      }
    }

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.track;
    canvas.drawCircle(center, arcRadius, track);

    if (progress > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [AppColors.brandOrange, AppColors.brandPink],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.stroke != stroke || old.ticks != ticks;
}

String two(int n) => n.toString().padLeft(2, '0');

/// 毫秒 → mm:ss。
String formatClock(int ms) {
  final total = (ms / 1000).round().clamp(0, 24 * 3600).toInt();
  return '${two(total ~/ 60)}:${two(total % 60)}';
}

String durationLabel(int activeMs) {
  final m = (activeMs / 60000).round();
  return m <= 0 ? '不足 1 分钟' : '$m 分钟';
}

/// 今天 08:10 / 11-09 08:10
String formatSessionTime(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final today = now ?? DateTime.now();
  final hm = '${two(local.hour)}:${two(local.minute)}';
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return '今天 $hm';
  }
  return '${two(local.month)}-${two(local.day)} $hm';
}

String greetingForHour(int hour) {
  if (hour < 12) return '早上好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

String invalidReasonLabel(String reason) => switch (reason) {
  'unfinished' => '提前结束，未计入',
  'not_camera' => '非相机模式，未计入',
  'out_of_frame' => '出框过多，未计入',
  'no_jumps' => '没有跳到，未计入',
  _ => reason,
};
