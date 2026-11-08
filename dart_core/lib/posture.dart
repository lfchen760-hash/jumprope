/// 姿态判定 —— `public/posture.mjs` 的 Dart 移植版。
///
/// 行为必须与 JS 完全一致：同一批关键点输入，输出相同的 tilt / knee / label。
library;

import 'dart:math' as math;

import 'landmark.dart';

/// 姿态判定结果。
class Posture {
  /// 躯干相对竖直方向的倾角（度）
  final double tilt;

  /// 膝关节角度，取左右较大值（度，伸直≈180）
  final double knee;
  final double kneeL;
  final double kneeR;

  /// 鼻子 + 两只脚踝是否都可见
  final bool fullBody;

  /// 站立 / 倾斜 / 蹲坐 / 躺卧
  final String label;

  /// 站直且全身入镜
  final bool standing;

  const Posture({
    required this.tilt,
    required this.knee,
    required this.kneeL,
    required this.kneeR,
    required this.fullBody,
    required this.label,
    required this.standing,
  });
}

/// 以 [b] 为顶点的夹角（度）。
double angleAt(Landmark a, Landmark b, Landmark c) {
  final v1x = a.x - b.x, v1y = a.y - b.y;
  final v2x = c.x - b.x, v2y = c.y - b.y;
  final m1 = math.sqrt(v1x * v1x + v1y * v1y);
  final m2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (m1 < 1e-6 || m2 < 1e-6) return 180;

  var cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
  if (cos < -1) cos = -1;
  if (cos > 1) cos = 1;
  return math.acos(cos) * 180 / math.pi;
}

/// 判定姿态。[lm] 必须是 33 个关键点。
Posture postureOf(List<Landmark> lm) {
  double vis(int i) => i < lm.length ? lm[i].visibility : 1;

  final shMidX = (lm[11].x + lm[12].x) / 2;
  final shMidY = (lm[11].y + lm[12].y) / 2;
  final hipMidX = (lm[23].x + lm[24].x) / 2;
  final hipMidY = (lm[23].y + lm[24].y) / 2;

  final dx = shMidX - hipMidX;
  final dy = shMidY - hipMidY;
  final tilt = (math.atan2(dx, -dy) * 180 / math.pi).abs();

  final kneeL = angleAt(lm[23], lm[25], lm[27]);
  final kneeR = angleAt(lm[24], lm[26], lm[28]);

  final fullBody = vis(0) > 0.4 && vis(27) > 0.4 && vis(28) > 0.4;

  final safeTilt = tilt.isFinite ? tilt : 0.0;
  final safeKneeL = kneeL.isFinite ? kneeL : 180.0;
  final safeKneeR = kneeR.isFinite ? kneeR : 180.0;
  final safeKnee = math.max(safeKneeL, safeKneeR);

  String label;
  if (safeTilt > 55) {
    label = '躺卧';
  } else if (safeTilt > 30) {
    label = '倾斜';
  } else if (safeKneeL < 120 && safeKneeR < 120) {
    label = '蹲坐';
  } else {
    label = '站立';
  }

  return Posture(
    tilt: safeTilt,
    knee: safeKnee,
    kneeL: safeKneeL,
    kneeR: safeKneeR,
    fullBody: fullBody,
    label: label,
    standing: label == '站立' && fullBody,
  );
}
