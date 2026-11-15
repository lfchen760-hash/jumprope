import 'package:flutter/services.dart';

/// 原生 Media3 导出：把计数/倒计时烧进原始录像。
class VideoExporter {
  static const MethodChannel _channel = MethodChannel('com.jumprope/video');
  static const EventChannel _events = EventChannel('com.jumprope/video_export');

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  Future<void> export({
    required String rawPath,
    required List<int> jumps,
    required int startOffsetMs,
    required int durationSec,
  }) async {
    await _channel.invokeMethod<void>('exportOverlay', {
      'rawPath': rawPath,
      'jumps': jumps,
      'startOffsetMs': startOffsetMs,
      'durationSec': durationSec,
    });
  }

  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancelExport');
  }

  Future<void> share(String uri) async {
    await _channel.invokeMethod<void>('shareVideo', {'uri': uri});
  }
}
