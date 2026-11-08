import 'landmark.dart';
import 'posture.dart';

/// 计数核心需要的派生特征。
///
/// 与 JS 版 `counter.feed(hipY, torso, now, ctx)` 的参数一一对应。
class PoseSample {
  final double t;
  final double hipY;
  final double torso;
  final double hipX;
  final double tilt;
  final double kneeL;
  final double kneeR;

  const PoseSample({
    required this.t,
    required this.hipY,
    required this.torso,
    required this.hipX,
    required this.tilt,
    required this.kneeL,
    required this.kneeR,
  });

  /// 从 33 个关键点派生。调用前请确认 [lm] 长度 >= 33。
  factory PoseSample.fromLandmarks(double t, List<Landmark> lm) {
    final hipY = (lm[23].y + lm[24].y) / 2;
    final shY = (lm[11].y + lm[12].y) / 2;
    final hipX = (lm[23].x + lm[24].x) / 2;
    final post = postureOf(lm);
    return PoseSample(
      t: t,
      hipY: hipY,
      torso: ((hipY - shY).abs() < 0.03 ? 0.03 : (hipY - shY).abs()),
      hipX: hipX,
      tilt: post.tilt,
      kneeL: post.kneeL,
      kneeR: post.kneeR,
    );
  }

  PoseContextOf get counterContext =>
      PoseContextOf(hipX: hipX, tilt: tilt, kneeL: kneeL, kneeR: kneeR);
}

/// 计数核心的上下文参数（避免直接依赖 Counter 的内部类型）。
class PoseContextOf {
  final double hipX;
  final double tilt;
  final double kneeL;
  final double kneeR;
  const PoseContextOf({
    required this.hipX,
    required this.tilt,
    required this.kneeL,
    required this.kneeR,
  });
}
