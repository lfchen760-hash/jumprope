import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jumprope_core/jumprope_core.dart';

import 'data/pose/camera_pose_source.dart';
import 'data/pose/mediapipe_landmarker.dart';

/// 构建标识，CI 用 --dart-define=BUILD_ID=xxxx 注入
const String kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');

void main() => runApp(const JumpropeApp());

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
  StreamSubscription<SessionState>? _sub;

  SessionState _state = SessionState.idle;
  String? _error;
  int _textureId = -1;
  bool _cameraStarted = false;
  int _previewReq = -1;
  String _previewDebug = '-';

  bool get _active =>
      _state.phase == SessionPhase.running ||
      _state.phase == SessionPhase.positioning ||
      _state.phase == SessionPhase.countdown ||
      _state.phase == SessionPhase.paused;

  Future<void> _start() async {
    setState(() {
      _error = null;
      _state = SessionState.idle;
    });

    try {
      await _landmarker.init();
      _textureId = await _landmarker.getPreviewTextureId();

      final source = CameraPoseSource(_landmarker);
      _source = source;

      final controller = SessionController(
        source: source,
        durationSec: 60,
        countdownSec: 3,
      );
      _controller = controller;

      _sub = controller.state.listen((s) {
        if (mounted) setState(() => _state = s);
      });


      await controller.start();
      _cameraStarted = true;
      if (mounted) setState(() {});

      // 帧数持续刷新，肉眼可见相机有没有输出
      Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (!mounted || !_active) return t.cancel();
        setState(() {});
      });

      // 稍等一下再读预览请求次数，判断 SurfaceProvider 有没有被调用
      Future.delayed(const Duration(milliseconds: 1500), () async {
        final n = await _landmarker.getPreviewRequests();
        final d = await _landmarker.getPreviewDebug();
        if (mounted) {
          setState(() {
            _previewReq = n;
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
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.stop();
    _controller = null;
    if (mounted) setState(() => _state = SessionState.idle);
  }

  @override
  void dispose() {
    _sub?.cancel();
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _active ? _stop : _start,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor:
                            _active ? Colors.white24 : Colors.blueAccent,
                      ),
                      child: Text(
                        _active ? '停止' : '开始',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
