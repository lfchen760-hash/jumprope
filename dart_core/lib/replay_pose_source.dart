import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'landmark.dart';
import 'pose_frame.dart';
import 'pose_source.dart';

/// 日志回放数据源：从导出的 JSON 读关键点序列。
///
/// 用途：
///   1. 单元测试（不依赖相机）
///   2. 复现线上问题（用户导出的日志）
///   3. 真机离线验证（手机录的日志拿回桌面跑）
class ReplayPoseSource implements PoseSource {
  /// 每帧之间的真实等待倍率。0 = 不等待（测试用最快速度）。
  final double speed;

  final _controller = StreamController<PoseFrame>.broadcast();
  List<PoseFrame> _frames = const [];
  Timer? _timer;
  int _index = 0;

  ReplayPoseSource({this.speed = 0});

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  SourceKind get kind => SourceKind.replay;

  /// 从文件加载。返回帧数。
  Future<int> loadFile(String path) async =>
      loadJson(await File(path).readAsString());

  /// 从 JSON 字符串加载。返回帧数。
  int loadJson(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    final list = data['frames'] as List;
    _frames = list.map((fr) {
      final f = fr as Map<String, dynamic>;
      final lm = (f['lm'] as List?)?.map((p) {
        final a = p as List;
        return Landmark(
          (a[0] as num).toDouble(),
          (a[1] as num).toDouble(),
          (a[2] as num).toDouble(),
          (a[3] as num).toDouble(),
        );
      }).toList() ??
          const <Landmark>[];
      return PoseFrame((f['t'] as num).toDouble(), lm);
    }).toList();
    return _frames.length;
  }

  /// 直接注入帧（测试用）。
  void loadFrames(List<PoseFrame> frames) => _frames = List.of(frames);

  int get length => _frames.length;

  @override
  Future<void> start() async {
    _index = 0;
    _emitNext();
  }

  void _emitNext() {
    if (_index >= _frames.length) {
      _controller.close();
      return;
    }
    final frame = _frames[_index++];
    _controller.add(frame);

    if (speed <= 0) {
      scheduleMicrotask(_emitNext);
      return;
    }
    final gapMs = _index < _frames.length
        ? (_frames[_index].t - frame.t).clamp(0.0, 2000.0)
        : 0.0;
    _timer = Timer(Duration(microseconds: (gapMs * 1000 / speed).round()), _emitNext);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
