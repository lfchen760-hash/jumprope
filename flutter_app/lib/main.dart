import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jumprope_core/jumprope_core.dart';

import 'data/pose/camera_pose_source.dart';
import 'data/pose/mediapipe_landmarker.dart';

void main() => runApp(const JumpropeApp());

class JumpropeApp extends StatelessWidget {
  const JumpropeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '跳绳计数',
      theme: ThemeData.dark(useMaterial3: true),
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
  StreamSubscription<SessionState>? _sub;
  SessionState _state = SessionState.idle;
  String? _error;

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await _landmarker.init();
      final source = CameraPoseSource(_landmarker);
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
    } catch (e) {
      setState(() => _error = '$e');
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
        return '准备就绪';
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
    final running = _state.phase == SessionPhase.running ||
        _state.phase == SessionPhase.positioning ||
        _state.phase == SessionPhase.countdown;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                '${_state.count}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 120,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text('次', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white54)),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  '剩余 ${(_state.remainingMs / 1000).ceil()} 秒',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _phaseText,
                  style: TextStyle(
                    fontSize: 15,
                    color: _state.framing.ok ? Colors.white70 : Colors.amber,
                  ),
                ),
              ),
              if (_state.gate != 'ok')
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _state.gate == 'move' ? '检测到走动，暂停计数' : '检测到弯腰，暂停计数',
                      style: const TextStyle(fontSize: 13, color: Colors.orange),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              const Spacer(),
              FilledButton(
                onPressed: running ? _stop : _start,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: Text(running ? '停止' : '开始',
                    style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
