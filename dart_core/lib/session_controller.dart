import 'dart:async';

import 'counter.dart';
import 'framing.dart';
import 'pose_frame.dart';
import 'pose_sample.dart';
import 'posture.dart';
import 'pose_source.dart';
import 'session_state.dart';

/// 会话编排：帧 → 派生特征 → 计数 → 状态。
///
/// 所有时间判断都以**帧时间戳**为准，不用系统时钟。
/// 这样回放（speed=0）和实时相机走的是同一条代码路径，测试才有意义。
class SessionController {
  final PoseSource source;
  final Counter counter;
  final int durationSec;
  final int countdownSec;

  /// 取景合格需要持续的时间（毫秒）
  final int stableMs;

  final _stateCtrl = StreamController<SessionState>.broadcast();
  StreamSubscription<PoseFrame>? _sub;

  SessionPhase _phase = SessionPhase.idle;
  int _count = 0;

  double _goodSince = -1;
  double _countdownEnd = 0;
  double _sessionEnd = 0;
  double _pausedRemain = 0;

  int _remainingMs = 0;
  // 初始必须是「未就位」：一帧都没收到时不能显示「就位了」
  Framing _framing = const Framing(false, '等待画面…');
  String _gate = 'ok';
  bool _hasPose = false;

  SessionController({
    required this.source,
    Counter? counter,
    this.durationSec = 60,
    this.countdownSec = 3,
    this.stableMs = 500,
  })  : counter = counter ?? Counter(),
        _remainingMs = durationSec * 1000;

  Stream<SessionState> get state => _stateCtrl.stream;

  SessionState get current => SessionState(
        phase: _phase,
        count: _count,
        durationSec: durationSec,
        remainingMs: _remainingMs,
        framing: _framing,
        gate: _gate,
        hasPose: _hasPose,
      );

  Future<void> start() async {
    counter.reset();
    _count = 0;
    _phase = SessionPhase.positioning;
    _goodSince = -1;
    _remainingMs = durationSec * 1000;
    _emit();

    _sub = source.frames.listen(_onFrame, onDone: _onDone);
    await source.start();
  }

  void pause() {
    if (_phase != SessionPhase.running) return;
    _pausedRemain = _sessionEnd - _lastT;
    _phase = SessionPhase.paused;
    _emit();
  }

  void resume() {
    if (_phase != SessionPhase.paused) return;
    _sessionEnd = _lastT + _pausedRemain;
    _phase = SessionPhase.running;
    _emit();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await source.stop();
    if (_phase != SessionPhase.finished) {
      _phase = SessionPhase.idle;
      _emit();
    }
  }

  double _lastT = 0;

  /// 处理一帧。公开是为了单元测试可以手动驱动。
  void ingest(PoseFrame frame) => _onFrame(frame);

  void _onFrame(PoseFrame frame) {
    _lastT = frame.t;
    _hasPose = frame.hasPose;
    _gate = counter.gate;

    if (!frame.hasPose) {
      _goodSince = -1;
      _framing = const Framing(false, '请站到画面中间');
      if (_phase == SessionPhase.positioning) _emit();
      return;
    }

    final sample = PoseSample.fromLandmarks(frame.t, frame.landmarks);
    final posture = postureOf(frame.landmarks);
    _framing = evaluateFraming(frame: frame, posture: posture);

    switch (_phase) {
      case SessionPhase.positioning:
        if (_framing.ok) {
          if (_goodSince < 0) _goodSince = frame.t;
          if (frame.t - _goodSince >= stableMs) _beginCountdown(frame.t);
        } else {
          _goodSince = -1;
        }
        break;

      case SessionPhase.countdown:
        if (frame.t >= _countdownEnd) _beginSession(frame.t);
        break;

      case SessionPhase.running:
        final counted = counter.feed(
          sample.hipY,
          sample.torso,
          frame.t,
          PoseContext(
            hipX: sample.hipX,
            tilt: sample.tilt,
            kneeL: sample.kneeL,
            kneeR: sample.kneeR,
          ),
        );
        if (counted) _count = counter.count;
        _gate = counter.gate;
        _remainingMs = (_sessionEnd - frame.t).clamp(0, durationSec * 1000).round();
        if (frame.t >= _sessionEnd) _finish();
        break;

      default:
        break;
    }

    _emit();
  }

  void _beginCountdown(double t) {
    _goodSince = -1;
    if (countdownSec <= 0) {
      _beginSession(t);
      return;
    }
    _phase = SessionPhase.countdown;
    _countdownEnd = t + countdownSec * 1000;
  }

  void _beginSession(double t) {
    counter.reset();
    _count = 0;
    _phase = SessionPhase.running;
    _sessionEnd = t + durationSec * 1000;
    _remainingMs = durationSec * 1000;
  }

  void _finish() {
    _phase = SessionPhase.finished;
    _remainingMs = 0;
    _sub?.cancel();
    _sub = null;
  }

  void _onDone() {
    if (_phase != SessionPhase.finished) {
      _phase = SessionPhase.finished;
      _emit();
    }
  }

  void _emit() {
    if (!_stateCtrl.isClosed) _stateCtrl.add(current);
  }

  Future<void> dispose() async {
    await stop();
    await _stateCtrl.close();
  }
}
