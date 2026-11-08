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
    final running = _state.phase == SessionPhase.running ||
        _state.phase == SessionPhase.positioning ||
        _state.phase == SessionPhase.countdown;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 相机预览
          if (_textureId > 0)
            Positioned.fill(child: Texture(textureId: _textureId))
          else
            const ColoredBox(color: Color(0xFF0B1020)),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  '${_state.count}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 110,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 24, color: Colors.black54)],
                  ),
                ),
                Text('次',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 14),
                _pill('剩余 ${(_state.remainingMs / 1000).ceil()} 秒'),
                const SizedBox(height: 8),
                _pill(
                  _phaseText,
                  warn: !_state.framing.ok,
                ),
                if (_state.gate != 'ok') ...[
                  const SizedBox(height: 8),
                  _pill(
                    _state.gate == 'move' ? '检测到走动，暂停计数' : '检测到弯腰，暂停计数',
                    warn: true,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: running ? _stop : _start,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor:
                            running ? Colors.white24 : Colors.blueAccent,
                      ),
                      child: Text(running ? '停止' : '开始',
                          style: const TextStyle(fontSize: 18)),
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
          color: warn ? Colors.amber.withValues(alpha: 0.6) : Colors.white24,
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
