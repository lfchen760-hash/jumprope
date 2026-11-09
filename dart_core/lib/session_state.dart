import 'framing.dart';

enum SessionPhase { idle, positioning, countdown, running, paused, finished }

/// 会话对外暴露的完整状态。
class SessionState {
  final SessionPhase phase;
  final int count;
  final int durationSec;
  final int remainingMs;
  final Framing framing;

  /// 计数闸门：ok / move / bend
  final String gate;
  final bool hasPose;

  /// 活动时长（毫秒，扣暂停）。running/paused 时实时更新。
  final int activeMs;

  /// 逐跳 offsetMs（活动时间）。**只读视图**，会话结束后用
  /// [SessionController.result] 里的不可变副本，别长期持有这个引用。
  final List<int> jumps;

  const SessionState({
    required this.phase,
    required this.count,
    required this.durationSec,
    required this.remainingMs,
    required this.framing,
    required this.gate,
    required this.hasPose,
    this.activeMs = 0,
    this.jumps = const [],
  });

  static const idle = SessionState(
    phase: SessionPhase.idle,
    count: 0,
    durationSec: 60,
    remainingMs: 60000,
    framing: Framing(true, ''),
    gate: 'ok',
    hasPose: false,
  );
}
