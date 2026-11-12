import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/session_video.dart';
import 'theme.dart';

/// 原始录像回放。特效导出是下一步，这里先放干净视频。
class SessionVideoPage extends StatefulWidget {
  const SessionVideoPage({super.key, required this.video});

  final SessionVideo video;

  @override
  State<SessionVideoPage> createState() => _SessionVideoPageState();
}

class _SessionVideoPageState extends State<SessionVideoPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = File(widget.video.rawPath);
      if (!await file.exists()) {
        throw '录像文件不在了（可能已超过 3 天）';
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('原始录像'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                '保留 3 天',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '播放失败：$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            : !_ready
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                  _controls(),
                ],
              ),
      ),
    );
  }

  Widget _controls() {
    final controller = _controller!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        final total = value.duration;
        final pos = value.position;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppColors.brandOrange,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_fmt(pos)} / ${_fmt(total)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  if (widget.video.width > 0)
                    Text(
                      '${widget.video.width}×${widget.video.height}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 打开原始录像页。
void openVideoPage(BuildContext context, SessionVideo video) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SessionVideoPage(video: video)));
}
