import 'package:jumprope_core/pose_frame.dart';
import 'package:jumprope_core/pose_source.dart';

import 'mediapipe_landmarker.dart';

/// 实时相机数据源。（触发 CI 编译验证 · 3）
class CameraPoseSource implements PoseSource {
  final MediaPipeLandmarker landmarker;
  bool front;

  CameraPoseSource(this.landmarker, {this.front = true});

  /// 前后摄像头切换：解绑后按新的朝向重新绑定
  Future<void> flip() async {
    front = !front;
    await landmarker.stopCamera();
    final ok = await landmarker.startCamera(front: front);
    if (!ok) {
      front = !front; // 失败则回滚
      throw StateError('切换摄像头失败');
    }
  }

  /// 已收到的帧数（用于判断相机到底有没有输出）
  int frameCount = 0;

  /// 收到过有姿态的帧数
  int poseCount = 0;

  @override
  Stream<PoseFrame> get frames => landmarker.frames.map((f) {
        frameCount++;
        if (f.hasPose) poseCount++;
        return f;
      });

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
