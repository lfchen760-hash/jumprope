import 'package:flutter/services.dart';

/// 原生录像完成后返回的元数据。
class RecordedVideo {
  final String path;
  final int durationMs;
  final int width;
  final int height;
  final int rotation;
  final bool hasAudio;
  final int sizeBytes;

  const RecordedVideo({
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
    required this.hasAudio,
    required this.sizeBytes,
  });

  factory RecordedVideo.fromMap(Map<String, dynamic> map) => RecordedVideo(
    path: (map['path'] as String?) ?? '',
    durationMs: _int(map['durationMs']),
    width: _int(map['width']),
    height: _int(map['height']),
    rotation: _int(map['rotation']),
    hasAudio: map['hasAudio'] == true,
    sizeBytes: _int(map['sizeBytes']),
  );
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// 原生 CameraX 录像通道。只负责开/停/暂停；时间轴由 Dart 记录。
class VideoRecorder {
  static const MethodChannel _channel = MethodChannel('com.jumprope/video');

  Future<String?> start() async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'startRecording',
    );
    return map?['path'] as String?;
  }

  Future<RecordedVideo?> stop() async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'stopRecording',
    );
    return map == null ? null : RecordedVideo.fromMap(map);
  }

  Future<void> pause() async {
    await _channel.invokeMethod<void>('pauseRecording');
  }

  Future<void> resume() async {
    await _channel.invokeMethod<void>('resumeRecording');
  }

  Future<bool> isRecording() async =>
      await _channel.invokeMethod<bool>('isRecording') ?? false;
}
