import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jumprope_core/jumprope_core.dart';

import 'camera_test_page.dart';
import 'data/pose/camera_pose_source.dart';
import 'skeleton_painter.dart';
import 'voice_service.dart';
import 'data/pose/mediapipe_landmarker.dart';

/// 构建标识，CI 用 --dart-define=BUILD_ID=xxxx 注入
const String kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');

/// 相机最小验证模式：只需 --dart-define=CAMERA_TEST=true
const bool kCameraTest = bool.fromEnvironment('CAMERA_TEST');

void main() => runApp(kCameraTest ? const _TestApp() : const JumpropeApp());

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraTestPage(),
    );
  }
}

class JumpropeApp extends StatelessWidget {
  const JumpropeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '跳绳计数',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _landmarker = MediaPipeLandmarker();

  SessionController? _controller;
  CameraPoseSource? _source;
  StreamSubscription<PoseFrame>? _lmSub;
  final ValueNotifier<PoseFrame?> _poseVN = ValueNotifier(null);
  final VoiceService _voice = VoiceService();
  Timer? _countdownTimer;
  StreamSubscription<SessionState>? _sub;

  SessionState _state = SessionState.idle;
  String? _error;
  int _textureId = -1;
  int _durationSec = 60;
  String _diag = '';
  bool _showDiag = false;
  String _previewDebug = '-';

  bool get _active =>
      _state.phase == SessionPhase.running ||
      _state.phase == SessionPhase.positioning ||
      _state.phase == SessionPhase.countdown ||
      _state.phase == SessionPhase.paused;

  /// 语音编排：相位切换、倒数、取景提示、报数
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
        _voice.resetCount();
        _voice.say('开始');
      } else if (s.phase == SessionPhase.paused) {
        _voice.say('已暂停');
      } else if (s.phase == SessionPhase.finished) {
        _voice.say('时间到，共 ${s.count} 次');
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

  Future<void> _loadDiag() async {
    final native = await _landmarker.getDiagnostics();
    final extra = StringBuffer()
      ..writeln('build=$kBuildId')
      ..writeln('dartFrames=${_source?.frameCount ?? 0}')
      ..writeln('dartPoses=${_source?.poseCount ?? 0}')
      ..writeln('phase=${_state.phase}')
      ..writeln('gate=${_state.gate} framing=${_state.framing.ok}'
          ' (${_state.framing.message})')
      ..writeln('textureId=$_textureId')
      ..writeln('voice=${_voice.status} enabled=${_voice.enabled} '
          'ready=${_voice.isReady}');
    if (mounted) {
      setState(() => _diag = '$native\n$extra');
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _state = SessionState.idle;
    });

    try {
      await _voice.init();
      await _landmarker.init();
      _textureId = await _landmarker.getPreviewTextureId();

      final source = CameraPoseSource(_landmarker);
      _source = source;

      final controller = SessionController(
        source: source,
        durationSec: _durationSec,
        countdownSec: 3,
      );
      _controller = controller;

      _sub = controller.state.listen(_onState);

      // 骨架叠加用：单独订阅关键点
      _lmSub = _landmarker.frames.listen((f) {
        _poseVN.value = f.hasPose ? f : null;
      });


      await controller.start();
      if (mounted) setState(() {});

      // 帧数持续刷新，肉眼可见相机有没有输出
      Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (!mounted || !_active) return t.cancel();
        setState(() {});
      });

      // 稍等一下再读预览请求次数，判断 SurfaceProvider 有没有被调用
      Future.delayed(const Duration(milliseconds: 1500), () async {
        final d = await _landmarker.getPreviewDebug();
        if (mounted) {
          setState(() {
            _previewDebug = d;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _state = SessionState.idle;
        });
      }
      await _loadDiag();
      if (mounted) setState(() => _showDiag = true);
    }
  }

  /// 暂停 / 继续
  Future<void> _togglePause() async {
    final c = _controller;
    if (c == null) return;
    if (_state.phase == SessionPhase.paused) {
      c.resume();
    } else if (_state.phase == SessionPhase.running) {
      c.pause();
    }
  }

  /// 重置：结束当前会话后重新开始（沿用当前时长）
  Future<void> _reset() async {
    final sec = _durationSec;
    await _stop();
    _durationSec = sec;
    await _start();
  }

  /// 前后摄像头切换
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
        return '点开始，让全身进入画面';
      case SessionPhase.positioning:
        return _state.framing.ok ? '就位了，准备开始' : _state.framing.message;
      case SessionPhase.countdown:
        return '准备…';
      case SessionPhase.running:
        return '跳吧！';
      case SessionPhase.paused:
        return '已暂停';
      case SessionPhase.finished:
        return '时间到';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 骨架叠加
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
                      _diag.isEmpty ? '（点「诊断信息」获取）' : _diag,
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

          // 顶部渐变压暗，保证文字可读
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
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 调试角标：一眼看出是哪个版本、纹理有没有拿到
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'v$kBuildId ${_previewDebug.isEmpty ? '' : _previewDebug} '
                    'f=${_source?.frameCount ?? 0} p=${_source?.poseCount ?? 0}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  '${_state.count}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 108,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Colors.white,
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
                _pill('剩余 ${(_state.remainingMs / 1000).ceil()} 秒'),
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
                ],
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                  child: _active
                      ? Row(
                          children: [
                            Expanded(
                              child: _ctrlBtn(
                                _state.phase == SessionPhase.paused ? '继续' : '暂停',
                                _togglePause,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: _ctrlBtn('重置', _reset)),
                            const SizedBox(width: 8),
                            Expanded(child: _ctrlBtn('翻转', _flip)),
                            const SizedBox(width: 8),
                            Expanded(child: _ctrlBtn('结束', _stop, primary: true)),
                          ],
                        )
                      : Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final s in const [30, 60, 120, 180])
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: _chip(
                                      s < 60 ? '$s秒' : '${s ~/ 60}分钟',
                                      _durationSec == s,
                                      () => setState(() => _durationSec = s),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() => _voice.enabled = !_voice.enabled);
                                    if (!_voice.enabled) _voice.stop();
                                  },
                                  child: Text(
                                    '语音：${_voice.enabled ? "开" : "关"}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await _voice.init();
                                    await _voice.say('测试语音');
                                  },
                                  child: const Text('试听',
                                      style: TextStyle(fontSize: 13)),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await _loadDiag();
                                    setState(() => _showDiag = !_showDiag);
                                  },
                                  child: Text(
                                    _showDiag ? '收起诊断' : '诊断信息',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _start,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  backgroundColor: Colors.blueAccent,
                                ),
                                child: const Text('开始',
                                    style: TextStyle(fontSize: 18)),
                              ),
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
          backgroundColor:
              primary ? Colors.blueAccent : Colors.white.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.white24,
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
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
