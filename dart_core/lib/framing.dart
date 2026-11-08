import 'pose_frame.dart';
import 'posture.dart';

/// 取景判定结果。
class Framing {
  final bool ok;
  final String message;

  const Framing(this.ok, this.message);

  static const Framing ready = Framing(true, '');
}

/// 判定画面里的人和位置是否适合开始。
///
/// 与 Web 版 `evalFraming()` 的规则一致，顺序也一致。
Framing evaluateFraming({
  required PoseFrame frame,
  required Posture posture,
  int personCount = 1,
}) {
  if (personCount > 1) return const Framing(false, '画面里只能有一个人');
  if (!frame.hasPose) return const Framing(false, '请站到画面中间');

  final h = frame.boxHeight;
  if (h > 0.96) return const Framing(false, '请退后一点，要拍到全身');
  if (h < 0.30) return const Framing(false, '请靠近一点');
  if (!posture.fullBody) return const Framing(false, '请把脚也放进画面');
  if (!posture.standing) return const Framing(false, '请站直一点');

  return Framing.ready;
}

/// 便捷判定（测试与 UI 都用这个）。
bool evaluateFramingForTest(PoseFrame frame) {
  if (!frame.hasPose) return false;
  return evaluateFraming(frame: frame, posture: postureOf(frame.landmarks)).ok;
}
