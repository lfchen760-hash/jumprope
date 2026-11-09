import 'child_profile.dart';

enum BenchmarkLevel { belowPass, pass, good, excellent, full, bonusFull }

/// 教育部《国家学生体质健康标准（2014 年修订）》一分钟跳绳单项。
/// 60/80/90 分 = 及格/良好/优秀；100 分 = 单项满分；
/// 120 分 = 100 分 + 20 分附加分（再多 40 次）。
class JumpBenchmark {
  static const String version = 'cn-2014';
  static const String source = '国家学生体质健康标准（2014年修订）';

  final int grade;
  final Gender gender;
  final int pass;
  final int good;
  final int excellent;
  final int full;
  final int bonusFull;

  const JumpBenchmark({
    required this.grade,
    required this.gender,
    required this.pass,
    required this.good,
    required this.excellent,
    required this.full,
    required this.bonusFull,
  });

  static const List<JumpBenchmark> all = [
    JumpBenchmark(
      grade: 1,
      gender: Gender.male,
      pass: 17,
      good: 87,
      excellent: 99,
      full: 109,
      bonusFull: 149,
    ),
    JumpBenchmark(
      grade: 2,
      gender: Gender.male,
      pass: 25,
      good: 95,
      excellent: 107,
      full: 117,
      bonusFull: 157,
    ),
    JumpBenchmark(
      grade: 3,
      gender: Gender.male,
      pass: 34,
      good: 104,
      excellent: 116,
      full: 126,
      bonusFull: 166,
    ),
    JumpBenchmark(
      grade: 4,
      gender: Gender.male,
      pass: 45,
      good: 115,
      excellent: 127,
      full: 137,
      bonusFull: 177,
    ),
    JumpBenchmark(
      grade: 5,
      gender: Gender.male,
      pass: 56,
      good: 126,
      excellent: 138,
      full: 148,
      bonusFull: 188,
    ),
    JumpBenchmark(
      grade: 6,
      gender: Gender.male,
      pass: 65,
      good: 135,
      excellent: 147,
      full: 157,
      bonusFull: 197,
    ),
    JumpBenchmark(
      grade: 1,
      gender: Gender.female,
      pass: 17,
      good: 87,
      excellent: 103,
      full: 117,
      bonusFull: 157,
    ),
    JumpBenchmark(
      grade: 2,
      gender: Gender.female,
      pass: 27,
      good: 97,
      excellent: 113,
      full: 127,
      bonusFull: 167,
    ),
    JumpBenchmark(
      grade: 3,
      gender: Gender.female,
      pass: 39,
      good: 109,
      excellent: 125,
      full: 139,
      bonusFull: 179,
    ),
    JumpBenchmark(
      grade: 4,
      gender: Gender.female,
      pass: 49,
      good: 119,
      excellent: 135,
      full: 149,
      bonusFull: 189,
    ),
    JumpBenchmark(
      grade: 5,
      gender: Gender.female,
      pass: 58,
      good: 128,
      excellent: 144,
      full: 158,
      bonusFull: 198,
    ),
    JumpBenchmark(
      grade: 6,
      gender: Gender.female,
      pass: 66,
      good: 136,
      excellent: 152,
      full: 166,
      bonusFull: 206,
    ),
  ];

  static JumpBenchmark? lookup(int? grade, Gender? gender) {
    if (grade == null || gender == null || gender == Gender.unspecified) {
      return null;
    }
    for (final b in all) {
      if (b.grade == grade && b.gender == gender) return b;
    }
    return null;
  }

  String get gradeLabel => '$grade 年级';

  BenchmarkLevel levelOf(int count) {
    if (count >= bonusFull) return BenchmarkLevel.bonusFull;
    if (count >= full) return BenchmarkLevel.full;
    if (count >= excellent) return BenchmarkLevel.excellent;
    if (count >= good) return BenchmarkLevel.good;
    if (count >= pass) return BenchmarkLevel.pass;
    return BenchmarkLevel.belowPass;
  }

  String messageOf(int count) {
    final level = levelOf(count);
    return switch (level) {
      BenchmarkLevel.bonusFull => '达到 120 分线（$bonusFull 个）',
      BenchmarkLevel.full => '超过 100 分线 ${count - full} 个',
      BenchmarkLevel.excellent => '超过优秀线 ${count - excellent} 个',
      BenchmarkLevel.good => '超过良好线 ${count - good} 个',
      BenchmarkLevel.pass => '距良好线还差 ${good - count} 个',
      BenchmarkLevel.belowPass => '继续积累，先和自己比',
    };
  }
}

class BenchmarkResult {
  final JumpBenchmark table;
  final int count;

  const BenchmarkResult({required this.table, required this.count});

  BenchmarkLevel get level => table.levelOf(count);

  int get diffToGood => table.good - count;

  String get message => table.messageOf(count);

  static BenchmarkResult? forSession({
    required int count,
    required int? grade,
    required Gender? gender,
  }) {
    final table = JumpBenchmark.lookup(grade, gender);
    if (table == null) return null;
    return BenchmarkResult(table: table, count: count);
  }
}
