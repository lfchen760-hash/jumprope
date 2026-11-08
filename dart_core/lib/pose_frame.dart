import 'landmark.dart';

/// 一帧姿态数据。
class PoseFrame {
  /// 时间戳（毫秒，单调递增）
  final double t;

  /// 33 个关键点；没检测到人时为空
  final List<Landmark> landmarks;

  const PoseFrame(this.t, this.landmarks);

  bool get hasPose => landmarks.length >= 33;

  /// 关键点包围盒高度（归一化）。无人时返回 0。
  double get boxHeight {
    if (!hasPose) return 0;
    var lo = 1.0, hi = 0.0;
    for (final p in landmarks) {
      if (lo > p.y) lo = p.y;
      if (hi < p.y) hi = p.y;
    }
    return (hi - lo).clamp(0.0, 1.0);
  }

  /// 髋部中点的 x（横移判定用）
  double get hipX => (landmarks[23].x + landmarks[24].x) / 2;
}
