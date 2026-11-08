import 'package:flutter/material.dart';
import 'package:jumprope_core/landmark.dart';

/// 在相机预览上叠加 MediaPipe 骨架。
///
/// 坐标换算说明：
///   - 关键点是归一化的 (0..1)，参照的是「分析图」，即旋转成竖屏后的画面
///   - 预览用 FILL_CENTER：等比放大到铺满，超出部分被裁掉
///   - 前置摄像头预览是镜像的，关键点不是，所以要翻 x
class SkeletonPainter extends CustomPainter {
  final List<Landmark> landmarks;
  final bool mirrored;

  /// 分析图的宽高比（旋转成竖屏后）。640x480 旋转 90° → 480/640
  static const double imageAspect = 480 / 640;

  SkeletonPainter(this.landmarks, {this.mirrored = true});

  static const List<List<int>> _bones = [
    [0, 1], [1, 2], [2, 3], [3, 7],
    [0, 4], [4, 5], [5, 6], [6, 8],
    [9, 10],
    [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
    [11, 23], [12, 24], [23, 24],
    [23, 25], [25, 27], [24, 26], [26, 28],
    [27, 31], [28, 32],
    [15, 17], [16, 18], [17, 19], [18, 20], [19, 21], [20, 22],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final screenAspect = w / h;

    // FILL_CENTER：等比放大到铺满，超出部分裁掉
    final drawW = imageAspect > screenAspect ? h * imageAspect : w;
    final drawH = imageAspect > screenAspect ? h : w / imageAspect;
    final dx = (w - drawW) / 2;
    final dy = (h - drawH) / 2;

    Offset toScreen(Landmark lm) {
      final nx = mirrored ? 1 - lm.x : lm.x;
      return Offset(dx + nx * drawW, dy + lm.y * drawH);
    }

    final bone = Paint()
      ..color = const Color(0xFF3DDC84)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final joint = Paint()..color = const Color(0xFFFFD54F);

    for (final b in _bones) {
      if (b[0] >= landmarks.length || b[1] >= landmarks.length) continue;
      final a = landmarks[b[0]];
      final c = landmarks[b[1]];
      if (a.visibility < 0.4 || c.visibility < 0.4) continue;
      canvas.drawLine(toScreen(a), toScreen(c), bone);
    }

    for (final lm in landmarks) {
      if (lm.visibility < 0.4) continue;
      canvas.drawCircle(toScreen(lm), 3.2, joint);
    }
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter old) =>
      old.landmarks != landmarks || old.mirrored != mirrored;
}
