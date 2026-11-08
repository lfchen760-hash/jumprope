import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:jumprope_core/landmark.dart';
import 'package:jumprope_core/pose_frame.dart';

/// Flutter 侧对原生 PosePlugin 的封装。
///
/// 只做协议转换，**不做任何业务判断**。
class MediaPipeLandmarker {
  static const MethodChannel _method = MethodChannel('com.jumprope/pose');
  static const EventChannel _event = EventChannel('com.jumprope/pose_frames');
  static const EventChannel _preview = EventChannel('com.jumprope/preview');

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
    if (!_initialized) {
      final detail = await _method.invokeMethod<String>('getInitError') ?? '';
      throw StateError('MediaPipe 初始化失败\n$detail');
    }
    return _initialized;
  }

  /// 关键点流（**只订阅一次**）。
  ///
  /// 注意：`receiveBroadcastStream()` 每次调用都会重新向原生端发 listen，
  /// 后一次会顶掉前一次的 sink，导致先订阅的那一方收不到数据。
  /// 所以必须缓存成同一个 broadcast 流，允许多个监听者。
  late final Stream<PoseFrame> _frames = _event
      .receiveBroadcastStream()
      .map(_parse)
      .where((f) => f != null)
      .cast<PoseFrame>();

  Stream<PoseFrame> get frames => _frames;

  /// 预览小图流（JPEG，约 8fps），用于手机端对准镜头
  Stream<Uint8List> get previewFrames => _preview
      .receiveBroadcastStream()
      .where((e) => e is Uint8List)
      .cast<Uint8List>();

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

  /// 相机预览纹理 id（给 Flutter 的 Texture 组件用），-1 表示不可用
  Future<int> getPreviewTextureId() async =>
      await _method.invokeMethod<int>('getPreviewTextureId') ?? -1;

  /// 完整诊断信息（设备、模型、权限、MediaPipe、相机）
  Future<String> getDiagnostics() async =>
      await _method.invokeMethod<String>('getDiagnostics') ?? '';

  /// 预览诊断信息（平台视图创建数 / 绑定 / 挂载 / 尝试次数）
  Future<String> getPreviewDebug() async =>
      await _method.invokeMethod<String>('getPreviewDebug') ?? 'n/a';

  /// 预览请求次数（诊断用），-1 表示相机未创建
  Future<int> getPreviewRequests() async =>
      await _method.invokeMethod<int>('getPreviewRequests') ?? -1;

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
