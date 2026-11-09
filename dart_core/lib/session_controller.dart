import 'dart:async';
import 'dart:collection';

import 'counter.dart';
import 'framing.dart';
import 'pose_frame.dart';
import 'pose_sample.dart';
import 'posture.dart';
import 'pose_source.dart';
import 'session_result.dart';
import 'session_state.dart';

/// 会话编排：帧 → 派生特征 → 计数 → 状态 → 结果。
///
/// 所有时间判断都以**帧时间戳**为准，不用系统时钟。
/// 这样回放（speed=0）和实时相机走的是同一条代码路径，测试才有意义。
///
/// 结束时产出一个 [SessionResult]（`result` getter），带逐跳 offset、
/// 活动时长和有效性。落库由上层（`flutter_app/lib/data/`）负责，
/// 核心层不碰 SQLite / 系统时钟。
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
  final List<int> _jumps = [];

  double _goodSince = -1;
  double _countdownEnd = 0;
  double _sessionEnd = 0;

  /// 会话开始（running）时的帧时间
  double _startT = 0;

  /// 累计暂停时长 / 本次暂停开始时间
  double _pausedTotalMs = 0;
  double _pauseStartT = 0;

  /// running 期间没有姿态的累计时长（用于有效性判定）
  double _outOfFrameMs = 0;
  double? _prevFrameT;

  int _remainingMs = 0;
  // 初始必须是「未就位」：一帧都没收到时不能显示「就位了」
  Framing _framing = const Framing(false, '等待画面…');
  String _gate = 'ok';
  bool _hasPose = false;

  double _lastT = 0;

  SessionResult? _result;

  SessionController({
    required this.source,
    Counter? counter,
    this.durationSec = 60,
    this.countdownSec = 3,
    this.stableMs = 500,
  })  : counter = counter ?? Counter(),
        _remainingMs = durationSec > 0 ? durationSec * 1000 : 0;

  Stream<SessionState> get state => _stateCtrl.stream;

  /// 结束后的结果；未结束时为 null。
  SessionResult? get result => _result;

  SessionState get current {
    final ended = _phase == SessionPhase.finished;
    return SessionState(
      phase: _phase,
      count: _count,
      durationSec: durationSec,
      remainingMs: _remainingMs,
      framing: _framing,
      gate: _gate,
      hasPose: _hasPose,
      activeMs: ended ? (_result?.activeMs ?? 0) : _activeMsAt(_lastT).round(),
      // 只读视图，不复制；running 时随会话增长
      jumps: UnmodifiableListView(_jumps),
    );
  }

  Future<void> start() async {
    counter.reset();
    _count = 0;
    _jumps.clear();
    _result = null;
    _phase = SessionPhase.positioning;
    _goodSince = -1;
    _pausedTotalMs = 0;
    _outOfFrameMs = 0;
    _prevFrameT = null;
    _lastT = 0;
    _remainingMs = durationSec > 0 ? durationSec * 1000 : 0;
    _emit();

    _sub = source.frames.listen(_onFrame, onDone: _onDone);
    await source.start();
  }

  void pause() {
    if (_phase != SessionPhase.running) return;
    _pauseStartT = _lastT;
    _phase = SessionPhase.paused;
    _emit();
  }

  void resume() {
    if (_phase != SessionPhase.paused) return;
    final paused = _lastT - _pauseStartT;
    _pausedTotalMs += paused;
    _sessionEnd += paused;
    _phase = SessionPhase.running;
    _emit();
  }

  /// 提前结束（自由跳 / 用户点「结束」）：立即生成结果并进入 finished。
  void finishEarly() {
    if (_phase == SessionPhase.running || _phase == SessionPhase.paused) {
      _finish();
    }
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

  /// 处理一帧。公开是为了单元测试可以手动驱动。
  void ingest(PoseFrame frame) => _onFrame(frame);

  void _onFrame(PoseFrame frame) {
    final prevT = _prevFrameT;
    _prevFrameT = frame.t;
    _lastT = frame.t;

    // 出框统计只算 running 段；暂停期间本来就不计时
    if (_phase == SessionPhase.running && prevT != null && !frame.hasPose) {
      final dt = frame.t - prevT;
      if (dt > 0) _outOfFrameMs += dt;
    }

    _hasPose = frame.hasPose;
    _gate = counter.gate;

    if (!frame.hasPose) {
      _goodSince = -1;
      _framing = const Framing(false, '请站到画面中间');
      if (_phase == SessionPhase.running) {
        _remainingMs = _remainingAt(frame.t);
        if (_ended(frame.t)) {
          _finish();
        } else {
          _emit();
        }
      } else if (_phase == SessionPhase.paused ||
          _phase == SessionPhase.positioning) {
        _emit();
      }
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
        if (counted) {
          _count = counter.count;
          final cap = durationSec > 0 ? durationSec * 1000 : null;
          final off = _activeMsAt(frame.t).round();
          _jumps.add(cap == null ? off : off.clamp(0, cap));
        }
        _gate = counter.gate;
        _remainingMs = _remainingAt(frame.t);
        if (_ended(frame.t)) _finish();
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
    _jumps.clear();
    _startT = t;
    _pausedTotalMs = 0;
    _outOfFrameMs = 0;
    _phase = SessionPhase.running;
    // durationSec <= 0 = 自由跳，不自动结束
    _sessionEnd = durationSec > 0 ? t + durationSec * 1000 : double.infinity;
    _remainingMs = durationSec > 0 ? durationSec * 1000 : 0;
  }

  bool _ended(double t) => durationSec > 0 && t >= _sessionEnd;

  int _remainingAt(double t) {
    if (durationSec <= 0) return 0;
    return (_sessionEnd - t).clamp(0, durationSec * 1000).round();
  }

  /// 从会话开始到 t 的活动时长（扣暂停，含当前暂停段）。
  double _activeMsAt(double t) {
    if (_phase == SessionPhase.idle ||
        _phase == SessionPhase.positioning ||
        _phase == SessionPhase.countdown) {
      return 0;
    }
    var active = t - _startT - _pausedTotalMs;
    if (_phase == SessionPhase.paused) active -= (t - _pauseStartT);
    return active < 0 ? 0 : active;
  }

  void _finish() {
    if (_phase == SessionPhase.finished) return;
    // 必须在改 phase 前算活动时长：pause 状态下要扣掉当前暂停段
    final activeRaw = _activeMsAt(_lastT).round();
    _phase = SessionPhase.finished;
    _remainingMs = 0;
    _result = _buildResult(activeRaw);
    _sub?.cancel();
    _sub = null;
    _emit();
  }

  SessionResult _buildResult(int activeRaw) {
    final plannedMs = durationSec > 0 ? durationSec * 1000 : 0;
    var active = activeRaw;
    if (active < 0) active = 0;
    if (plannedMs > 0 && active > plannedMs) active = plannedMs;

    final reasons = <String>[];
    final completed = plannedMs == 0 || active >= (plannedMs * 0.9).round();
    if (!completed) reasons.add(SessionResult.reasonUnfinished);

    // 一次都没跳：存下来但标无效，别把「站着不动」算成活跃天
    if (_count <= 0) reasons.add(SessionResult.reasonNoJumps);

    if (source.kind != SourceKind.camera) {
      reasons.add(SessionResult.reasonNotCamera);
    }

    // 出框累计 ≤ 5% 且 ≤ 3s 才有效
    if (plannedMs > 0 &&
        (_outOfFrameMs > plannedMs * 0.05 || _outOfFrameMs > 3000)) {
      reasons.add(SessionResult.reasonOutOfFrame);
    }

    final jumps = [
      for (final j in _jumps) j < 0 ? 0 : (j > active ? active : j),
    ];

    return SessionResult(
      count: _count,
      jumps: jumps,
      activeMs: active,
      plannedMs: plannedMs,
      completed: completed,
      valid: reasons.isEmpty,
      invalidReasons: reasons,
      source: source.kind,
    );
  }

  void _onDone() {
    if (_phase == SessionPhase.finished) return;
    _finish();
  }

  void _emit() {
    if (!_stateCtrl.isClosed) _stateCtrl.add(current);
  }

  Future<void> dispose() async {
    await stop();
    await _stateCtrl.close();
  }
}
