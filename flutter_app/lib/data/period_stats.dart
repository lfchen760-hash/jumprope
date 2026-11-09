import 'date_utils.dart';
import 'goal_entry.dart';
import 'session_record.dart';

/// 日/周/月/年都从会话算，不单独落库。
class PeriodStats {
  final int total;
  final int activeDays;
  final int best;
  final double avgPerActiveDay;
  final int streak;
  final Map<String, int> dailyTotals;

  const PeriodStats({
    required this.total,
    required this.activeDays,
    required this.best,
    required this.avgPerActiveDay,
    required this.streak,
    required this.dailyTotals,
  });
}

PeriodStats computePeriodStats(
  List<SessionRecord> sessions, {
  required DateTime today,
  String? from,
  String? to,
}) {
  final daily = <String, int>{};
  var total = 0;
  var best = 0;

  for (final s in sessions) {
    if (!s.valid) continue;
    if (from != null && s.localDate.compareTo(from) < 0) continue;
    if (to != null && s.localDate.compareTo(to) > 0) continue;
    total += s.count;
    if (s.count > best) best = s.count;
    daily[s.localDate] = (daily[s.localDate] ?? 0) + s.count;
  }

  final dates = sessions.where((s) => s.valid).map((s) => s.localDate).toSet();

  return PeriodStats(
    total: total,
    activeDays: daily.length,
    best: best,
    avgPerActiveDay: daily.isEmpty ? 0 : total / daily.length,
    streak: computeStreak(dates, today),
    dailyTotals: Map.unmodifiable(daily),
  );
}

/// 连续天数：今天有记录就从今天算，否则从昨天算（今天还没跳不算断）。
int computeStreak(Set<String> dates, DateTime today) {
  var d = DateTime(today.year, today.month, today.day);
  if (!dates.contains(localDateOf(d))) {
    d = d.subtract(const Duration(days: 1));
  }
  var n = 0;
  while (dates.contains(localDateOf(d))) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

/// 某天生效的目标；没有历史时默认 300。
int goalForDate(List<GoalEntry> goals, String date) {
  GoalEntry? best;
  for (final g in goals) {
    if (g.effectiveFrom.compareTo(date) > 0) continue;
    if (best == null || g.effectiveFrom.compareTo(best.effectiveFrom) > 0) {
      best = g;
    }
  }
  return best?.dailyGoal ?? 300;
}

/// 0=无记录，1=<50%，2=50–99%，3=100–149%，4=>=150%。
int calendarLevel(int total, int goal) {
  if (total <= 0 || goal <= 0) return 0;
  final r = total / goal;
  if (r < 0.5) return 1;
  if (r < 1.0) return 2;
  if (r < 1.5) return 3;
  return 4;
}
