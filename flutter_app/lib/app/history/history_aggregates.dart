import '../../data/child_profile.dart';
import '../../data/date_utils.dart';
import '../../data/jump_benchmark.dart';
import '../../data/session_record.dart';

/// 周期内单次最好（只算 valid）。
SessionRecord? bestSession(Iterable<SessionRecord> sessions) {
  SessionRecord? best;
  for (final session in sessions) {
    if (!session.valid) continue;
    if (best == null || session.count > best.count) best = session;
  }
  return best;
}

/// 周期内单次最多次数；没有有效会话返回 0。
int bestCount(Iterable<SessionRecord> sessions) {
  var best = 0;
  for (final session in sessions) {
    if (session.valid && session.count > best) best = session.count;
  }
  return best;
}

/// 某年 12 个月的有效总次数，下标 0 = 1 月。
List<int> monthlyTotals(List<SessionRecord> sessions, int year) {
  final out = List<int>.filled(12, 0);
  for (final session in sessions) {
    if (!session.valid) continue;
    final date = parseLocalDate(session.localDate);
    if (date.year == year) out[date.month - 1] += session.count;
  }
  return out;
}

/// 年份下拉：有记录的年份 + 当前/选中年的种子，降序。
List<int> availableYears(Iterable<SessionRecord> sessions, Iterable<int> seed) {
  final years = <int>{...seed};
  for (final session in sessions) {
    years.add(parseLocalDate(session.localDate).year);
  }
  return years.toList()..sort((a, b) => b.compareTo(a));
}

/// 只有 1 分钟模式且档案开了参考线时才返回国标结果。
BenchmarkResult? benchmarkFor(SessionRecord? session, ChildProfile? profile) {
  if (session == null) return null;
  if (session.mode != SessionMode.timed60) return null;
  if (profile?.showBenchmark != true) return null;
  return BenchmarkResult.forSession(
    count: session.count,
    grade: session.gradeAtSession,
    gender: session.genderAtSession,
  );
}
