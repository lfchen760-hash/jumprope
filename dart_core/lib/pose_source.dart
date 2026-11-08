import 'pose_frame.dart';

enum SourceKind { camera, videoFile, replay }

/// 姿态数据源。
///
/// 相机 / 视频文件 / 日志回放三种实现共用这一接口，
/// 上层 SessionController 完全不知道数据从哪来。
abstract class PoseSource {
  /// 帧流，t 单调递增（毫秒）
  Stream<PoseFrame> get frames;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  SourceKind get kind;
}
