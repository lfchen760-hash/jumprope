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

  const SessionState({
    required this.phase,
    required this.count,
    required this.durationSec,
    required this.remainingMs,
    required this.framing,
    required this.gate,
    required this.hasPose,
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
