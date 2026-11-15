import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/session_record.dart';
import '../data/session_video.dart';
import '../data/video_exporter.dart';
import 'theme.dart';
import 'video_export_panel.dart';

/// 原始录像回放。特效导出是下一步，这里先放干净视频。
class SessionVideoPage extends StatefulWidget {
  const SessionVideoPage({
    super.key,
    required this.video,
    required this.record,
  });

  final SessionVideo video;
  final SessionRecord record;

  @override
  State<SessionVideoPage> createState() => _SessionVideoPageState();
}

class _SessionVideoPageState extends State<SessionVideoPage> {
  VideoPlayerController? _controller;
  final VideoExporter _exporter = VideoExporter();
  StreamSubscription<Map<String, dynamic>>? _exportSub;
  String? _error;
  bool _ready = false;
  bool _exporting = false;
  double _progress = 0;
  String? _exportUri;
  String? _exportPath;
  String? _exportError;

  @override
  void initState() {
    super.initState();
    _exportSub = _exporter.events.listen(_onExportEvent);
    _init();
  }

  void _onExportEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['event'];
    if (type == 'progress') {
      setState(() {
        _progress = (event['progress'] as num?)?.toDouble() ?? 0;
      });
    } else if (type == 'completed') {
      setState(() {
        _exporting = false;
        _progress = 1;
        _exportPath = event['path'] as String?;
        final uri = event['uri'] as String? ?? '';
        _exportUri = uri.isEmpty ? null : uri;
      });
    } else if (type == 'error') {
      setState(() {
        _exporting = false;
        _exportError = event['message'] as String? ?? '导出失败';
      });
    }
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _progress = 0;
      _exportError = null;
      _exportUri = null;
      _exportPath = null;
    });
    try {
      await _exporter.export(
        rawPath: widget.video.rawPath,
        jumps: widget.record.jumps,
        startOffsetMs: widget.video.startOffsetMs,
        durationSec: widget.record.fixedDurationSec ?? 0,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportError = '$e';
      });
    }
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
    _exportSub?.cancel();
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
                  _exportPanel(),
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

  Widget _exportPanel() {
    return VideoExportPanel(
      exporting: _exporting,
      progress: _progress,
      uri: _exportUri,
      path: _exportPath,
      error: _exportError,
      onExport: _export,
      onCancel: () async {
        await _exporter.cancel();
        if (mounted) setState(() => _exporting = false);
      },
      onShare: () {
        if (_exportUri != null) _exporter.share(_exportUri!);
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
void openVideoPage(
  BuildContext context,
  SessionVideo video,
  SessionRecord record,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SessionVideoPage(video: video, record: record),
    ),
  );
}
