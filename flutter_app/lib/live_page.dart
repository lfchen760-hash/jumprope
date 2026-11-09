import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jumprope_core/jumprope_core.dart';

import 'app/result_page.dart';
import 'build_info.dart';
import 'data/pose/camera_pose_source.dart';
import 'data/pose/mediapipe_landmarker.dart';
import 'data/session_record.dart';
import 'data/session_saver.dart';
import 'skeleton_painter.dart';
import 'voice_service.dart';

/// 计数页：相机预览 + 骨架 + 大数字 + 暂停/结束。
///
/// 从首页带着时长进来，进页面自动启动；结束后自动落库并跳到结果页。
class LivePage extends StatefulWidget {
  const LivePage({
    super.key,
    required this.durationSec,
    required this.nickname,
    this.previous,
    this.previousBest = 0,
  });

  /// 0 = 自由跳
  final int durationSec;
  final String nickname;
  final SessionRecord? previous;
  final int previousBest;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final _landmarker = MediaPipeLandmarker();
  final _saver = SessionSaver();
  final _voice = VoiceService();

  SessionController? _controller;
  CameraPoseSource? _source;
  StreamSubscription<PoseFrame>? _lmSub;
  final ValueNotifier<PoseFrame?> _poseVN = ValueNotifier(null);
  Timer? _countdownTimer;
  StreamSubscription<SessionState>? _sub;

  SessionState _state = SessionState.idle;
  String? _error;
  String _diag = '';
  bool _showDiag = false;

  DateTime? _sessionStartedAt;
  bool _handledFinish = false;

  int _textureId = -1;

  bool get _active =>
      _state.phase == SessionPhase.running ||
      _state.phase == SessionPhase.positioning ||
      _state.phase == SessionPhase.countdown ||
      _state.phase == SessionPhase.paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onState(SessionState s) {
    final prev = _state.phase;

    if (s.phase != prev) {
      _countdownTimer?.cancel();
      if (s.phase == SessionPhase.countdown) {
        _voice.say('准备');
        var n = 3;
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || _state.phase != SessionPhase.countdown) {
            t.cancel();
            return;
          }
          if (n > 0) {
            _voice.say('$n');
            n--;
          } else {
            t.cancel();
          }
        });
      } else if (s.phase == SessionPhase.running) {
        _sessionStartedAt = DateTime.now();
        _voice.resetCount();
        _voice.say('开始');
      } else if (s.phase == SessionPhase.paused) {
        _voice.say('已暂停');
      } else if (s.phase == SessionPhase.finished) {
        _voice.say('时间到，共 ${s.count} 次');
        unawaited(_finishAndShowResult());
      }
    }

    if (s.phase == SessionPhase.positioning && !s.framing.ok) {
      _voice.sayOnce(s.framing.message);
    }
    if (s.phase == SessionPhase.running) {
      _voice.announceCount(s.count);
    }

    if (mounted) setState(() => _state = s);
  }

  Future<void> _finishAndShowResult() async {
    if (_handledFinish) return;
    _handledFinish = true;

    final result = _controller?.result;
    final started = _sessionStartedAt;
    if (result == null || started == null || result.activeMs <= 0) {
      await _leave();
      return;
    }

    final ended = DateTime.now();
    SessionRecord? record;
    String? saveError;
    try {
      record = await _saver.save(
        result: result,
        startedAt: started,
        endedAt: ended,
        mode: sessionModeForDuration(widget.durationSec),
      );
    } catch (e) {
      saveError = '$e';
    }
    // 落库失败也让用户看到本次成绩，不白跳
    record ??= SessionRecord.fromResult(
      id:
          's-${started.millisecondsSinceEpoch}'
          '-${ended.millisecondsSinceEpoch}',
      result: result,
      startedAt: started,
      endedAt: ended,
      mode: sessionModeForDuration(widget.durationSec),
    );

    await _stop();
    if (!mounted) return;

    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ResultPage(
          record: record!,
          nickname: widget.nickname,
          previous: widget.previous,
          previousBest: widget.previousBest,
          saveError: saveError,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(action);
  }

  Future<void> _leave() async {
    await _stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmClose() async {
    if (_active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('结束本次训练？'),
          content: const Text('当前成绩不会保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续跳'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('结束'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _leave();
  }

  Future<void> _loadDiag() async {
    final native = await _landmarker.getDiagnostics();
    final extra = StringBuffer()
      ..writeln('build=$kBuildId')
      ..writeln('dartFrames=${_source?.frameCount ?? 0}')
      ..writeln('dartPoses=${_source?.poseCount ?? 0}')
      ..writeln('phase=${_state.phase}')
      ..writeln(
        'gate=${_state.gate} framing=${_state.framing.ok}'
        ' (${_state.framing.message})',
      )
      ..writeln('textureId=$_textureId')
      ..writeln(
        'voice=${_voice.status} enabled=${_voice.enabled} '
        'ready=${_voice.isReady}',
      );
    if (!mounted) return;
    setState(() {
      _diag = '$native\n$extra';
      _showDiag = true;
    });
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _state = SessionState.idle;
      _handledFinish = false;
    });

    try {
      await _voice.init();
      await _landmarker.init();
      _textureId = await _landmarker.getPreviewTextureId();

      final source = CameraPoseSource(_landmarker);
      _source = source;

      final controller = SessionController(
        source: source,
        durationSec: widget.durationSec,
        countdownSec: 3,
      );
      _controller = controller;

      _sub = controller.state.listen(_onState);

      _lmSub = _landmarker.frames.listen((f) {
        _poseVN.value = f.hasPose ? f : null;
      });

      await controller.start();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _state = SessionState.idle;
      });
      await _loadDiag();
      if (mounted) setState(() => _showDiag = true);
    }
  }

  Future<void> _togglePause() async {
    final c = _controller;
    if (c == null) return;
    if (_state.phase == SessionPhase.paused) {
      c.resume();
    } else if (_state.phase == SessionPhase.running) {
      c.pause();
    }
  }

  void _finishEarly() {
    final c = _controller;
    if (c == null) return;
    if (_state.phase == SessionPhase.running ||
        _state.phase == SessionPhase.paused) {
      c.finishEarly();
    } else {
      _confirmClose();
    }
  }

  Future<void> _flip() async {
    try {
      await _source?.flip();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '切换摄像头失败: $e');
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _lmSub?.cancel();
    _lmSub = null;
    _poseVN.value = null;
    _countdownTimer?.cancel();
    await _voice.stop();
    await _controller?.stop();
    _controller = null;
    if (mounted) setState(() => _state = SessionState.idle);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lmSub?.cancel();
    _poseVN.dispose();
    _countdownTimer?.cancel();
    _voice.dispose();
    _controller?.dispose();
    _landmarker.dispose();
    super.dispose();
  }

  String get _phaseText {
    switch (_state.phase) {
      case SessionPhase.idle:
        return _error == null ? '正在启动相机…' : '相机启动失败';
      case SessionPhase.positioning:
        return _state.framing.ok ? '就位了，准备开始' : _state.framing.message;
      case SessionPhase.countdown:
        return '准备…';
      case SessionPhase.running:
        return '跳吧！';
      case SessionPhase.paused:
        return '已暂停';
      case SessionPhase.finished:
        return '正在生成结果…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final idle = _state.phase == SessionPhase.idle;
    final finished = _state.phase == SessionPhase.finished;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<PoseFrame?>(
                valueListenable: _poseVN,
                builder: (_, frame, __) {
                  final lms = frame?.landmarks ?? const <Landmark>[];
                  return CustomPaint(
                    painter: SkeletonPainter(
                      lms,
                      mirrored: _source?.front ?? true,
                    ),
                  );
                },
              ),
            ),
          ),

          if (_showDiag)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showDiag = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.92),
                  padding: const EdgeInsets.fromLTRB(14, 44, 14, 14),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _diag.isEmpty ? '（点角标获取）' : _diag,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: 'monospace',
                        color: Color(0xFFB9F6CA),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _loadDiag,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v$kBuildId',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _confirmClose,
                      icon: Icon(
                        Icons.close,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                if (!idle && !finished) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_state.count}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 104,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                      shadows: [Shadow(blurRadius: 24, color: Colors.black87)],
                    ),
                  ),
                  Text(
                    '次',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pill(
                    widget.durationSec > 0
                        ? '剩余 ${(_state.remainingMs / 1000).ceil()} 秒'
                        : '自由跳',
                  ),
                  const SizedBox(height: 8),
                  _pill(_phaseText, warn: _active && !_state.framing.ok),
                  if (_active && (_source?.frameCount ?? 0) == 0) ...[
                    const SizedBox(height: 8),
                    _pill('相机没有输出画面（权限或初始化失败）', warn: true),
                  ],
                  if (_state.gate != 'ok') ...[
                    const SizedBox(height: 8),
                    _pill(
                      _state.gate == 'move' ? '检测到走动，暂停计数' : '检测到弯腰，暂停计数',
                      warn: true,
                    ),
                  ],
                ],
                if (idle && _error == null) ...[
                  const Spacer(),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    '正在启动相机…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                ],
                if (finished) ...[
                  const Spacer(),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    '正在生成结果…',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(onPressed: _start, child: const Text('重试')),
                      TextButton(
                        onPressed: _leave,
                        child: const Text(
                          '返回',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (!idle && !finished)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ctrlBtn(
                            _state.phase == SessionPhase.paused ? '继续' : '暂停',
                            _togglePause,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _ctrlBtn('翻转', _flip)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ctrlBtn('结束', _finishEarly, primary: true),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(String label, VoidCallback onTap, {bool primary = false}) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: primary
              ? Colors.blueAccent
              : Colors.white.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _pill(String text, {bool warn = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: warn ? Colors.amber.withValues(alpha: 0.7) : Colors.white24,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: warn ? Colors.amber : Colors.white,
        ),
      ),
    );
  }
}
