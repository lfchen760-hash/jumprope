/// 每日目标变更历史：日历颜色要按「当天生效的目标」算，不能被新目标改写。
class GoalEntry {
  final String effectiveFrom; // YYYY-MM-DD
  final int dailyGoal;
  final int createdAtMs;

  const GoalEntry({
    required this.effectiveFrom,
    required this.dailyGoal,
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
    'effective_from': effectiveFrom,
    'daily_goal': dailyGoal,
    'created_at': createdAtMs,
  };

  factory GoalEntry.fromMap(Map<String, dynamic> map) => GoalEntry(
    effectiveFrom: map['effective_from'] as String,
    dailyGoal: (map['daily_goal'] as num).toInt(),
    createdAtMs:
        (map['created_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch,
  );
}
