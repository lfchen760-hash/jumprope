import 'package:jumprope_core/pose_frame.dart';
import 'package:jumprope_core/pose_source.dart';

import 'mediapipe_landmarker.dart';

/// 离线视频数据源（调试用）。
///
/// 和相机走**同一条原生管线**，只是帧从文件来而不是从摄像头来。
class VideoPoseSource implements PoseSource {
  final MediaPipeLandmarker landmarker;
  final String path;
  final int fps;

  VideoPoseSource(this.landmarker, this.path, {this.fps = 30});

  @override
  Stream<PoseFrame> get frames => landmarker.frames;

  @override
  SourceKind get kind => SourceKind.videoFile;

  @override
  Future<void> start() async {
    if (!landmarker.isInitialized) {
      await landmarker.init();
    }
    final ok = await landmarker.processVideo(path, fps: fps);
    if (!ok) throw StateError('视频解码启动失败: $path');
  }

  @override
  Future<void> stop() => landmarker.stopVideo();

  @override
  Future<void> dispose() => landmarker.dispose();
}
