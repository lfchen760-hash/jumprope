import 'package:flutter/services.dart';
import 'package:jumprope_core/landmark.dart';
import 'package:jumprope_core/pose_frame.dart';

/// Flutter 侧对原生 PosePlugin 的封装。
///
/// 只做协议转换，**不做任何业务判断**。
class MediaPipeLandmarker {
  static const MethodChannel _method = MethodChannel('com.jumprope/pose');
  static const EventChannel _event = EventChannel('com.jumprope/pose_frames');

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<bool> init({
    String modelAsset = 'pose_landmarker_lite.task',
    bool useGpu = true,
  }) async {
    final ok = await _method.invokeMethod<bool>('init', {
      'modelAsset': modelAsset,
      'useGpu': useGpu,
    });
    _initialized = ok ?? false;
    return _initialized;
  }

  /// 关键点流。每个事件是一帧：[PoseFrame]，无人时 landmarks 为空。
  Stream<PoseFrame> get frames =>
      _event.receiveBroadcastStream().map(_parse).where((f) => f != null).cast<PoseFrame>();

  PoseFrame? _parse(dynamic event) {
    if (event is! Map) return null;
    final t = (event['t'] as num?)?.toDouble();
    if (t == null) return null;

    final raw = event['lm'];
    if (raw is! List) return PoseFrame(t, const []);

    final flat = raw.map((e) => (e as num).toDouble()).toList();
    if (flat.length < 33 * 4) return PoseFrame(t, const []);

    final lm = <Landmark>[];
    for (var i = 0; i < 33; i++) {
      lm.add(Landmark(
        flat[i * 4],
        flat[i * 4 + 1],
        flat[i * 4 + 2],
        flat[i * 4 + 3],
      ));
    }
    return PoseFrame(t, lm);
  }

  Future<bool> startCamera({bool front = true}) async =>
      await _method.invokeMethod<bool>('startCamera', {'front': front}) ?? false;

  Future<void> stopCamera() => _method.invokeMethod<void>('stopCamera');

  /// 调试：逐帧解码本地视频（很慢，只用于离线验证）
  Future<bool> processVideo(String path, {int fps = 30}) async =>
      await _method.invokeMethod<bool>('processVideo', {'path': path, 'fps': fps}) ?? false;

  Future<void> stopVideo() => _method.invokeMethod<void>('stopVideo');

  Future<void> dispose() async {
    _initialized = false;
    await _method.invokeMethod<void>('dispose');
  }
}
