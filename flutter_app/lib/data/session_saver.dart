import 'package:jumprope_core/session_result.dart';

import 'data_repository.dart';
import 'export_bundle.dart';
import 'jump_benchmark.dart';
import 'session_record.dart';

/// 计数算法版本，写进会话快照。改算法行为时一起改，方便回溯。
const String kAlgoVersion = String.fromEnvironment(
  'ALGO_VERSION',
  defaultValue: 'counter-v1',
);

/// 把一次 [SessionResult] 变成 [SessionRecord] 并落库。
///
/// 只做「结束 → 一条记录」这一件事；统计/展示仍然读库实时算。
class SessionSaver {
  SessionSaver({DataRepository? repo}) : _repo = repo ?? DataRepository();

  final DataRepository _repo;

  /// 返回落库后的记录；活动时长为 0（没真正开始）则跳过，返回 null。
  Future<SessionRecord?> save({
    required SessionResult result,
    required DateTime startedAt,
    required DateTime endedAt,
    required SessionMode mode,
  }) async {
    if (result.activeMs <= 0) return null;

    final profile = await _repo.loadProfile();
    final record = SessionRecord.fromResult(
      id:
          's-${startedAt.millisecondsSinceEpoch}'
          '-${endedAt.millisecondsSinceEpoch}',
      result: result,
      startedAt: startedAt,
      endedAt: endedAt,
      mode: mode,
      profile: profile,
      standardVersion: profile != null && profile.hasBenchmark
          ? JumpBenchmark.version
          : null,
      algoVersion: kAlgoVersion,
      appVersion: kAppVersion,
    );
    await _repo.saveSession(record);
    return record;
  }
}
