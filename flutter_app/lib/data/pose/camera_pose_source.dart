import 'package:jumprope_core/pose_frame.dart';
import 'package:jumprope_core/pose_source.dart';

import 'mediapipe_landmarker.dart';

/// 实时相机数据源。
class CameraPoseSource implements PoseSource {
  final MediaPipeLandmarker landmarker;
  final bool front;

  CameraPoseSource(this.landmarker, {this.front = true});

  @override
  Stream<PoseFrame> get frames => landmarker.frames;

  @override
  SourceKind get kind => SourceKind.camera;

  @override
  Future<void> start() async {
    if (!landmarker.isInitialized) {
      await landmarker.init();
    }
    final ok = await landmarker.startCamera(front: front);
    if (!ok) throw StateError('相机启动失败');
  }

  @override
  Future<void> stop() => landmarker.stopCamera();

  @override
  Future<void> dispose() => landmarker.dispose();
}
