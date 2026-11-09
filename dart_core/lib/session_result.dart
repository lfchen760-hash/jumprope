import 'pose_source.dart';

/// 一次会话结束后的结果快照。
///
/// 只在 `finished` 时生成一次；`jumps` 是逐跳 offset（毫秒，**活动时间**，
/// 不含暂停），数据层的 `SessionRecord.jumps` 直接用它。
///
/// 有效性规则见 `design/data-logic.md` §5.2。当前能自动判定的只有：
/// 非相机模式、完成度 < 90%、出框累计超限。多人检测还没接。
class SessionResult {
  static const String reasonUnfinished = 'unfinished';
  static const String reasonNotCamera = 'not_camera';
  static const String reasonOutOfFrame = 'out_of_frame';
  static const String reasonNoJumps = 'no_jumps';

  /// 计数（== jumps.length）
  final int count;

  /// 逐跳 offsetMs，活动时间，升序
  final List<int> jumps;

  /// 活动时长（扣暂停）
  final int activeMs;

  /// 计划时长；自由跳为 0
  final int plannedMs;

  /// 完成度是否达标（自由跳恒为 true）
  final bool completed;

  /// 是否计入统计
  final bool valid;

  /// 无效原因（SessionResult.reason* 常量）
  final List<String> invalidReasons;

  /// 数据来源（相机 / 视频 / 回放）
  final SourceKind source;

  SessionResult({
    required this.count,
    required List<int> jumps,
    required this.activeMs,
    required this.plannedMs,
    required this.completed,
    required this.valid,
    required List<String> invalidReasons,
    required this.source,
  })  : jumps = List.unmodifiable(jumps),
        invalidReasons = List.unmodifiable(invalidReasons);

  bool get isFree => plannedMs <= 0;

  @override
  String toString() =>
      'SessionResult(count=$count, activeMs=$activeMs, valid=$valid, '
      'reasons=$invalidReasons, source=${source.name})';
}
