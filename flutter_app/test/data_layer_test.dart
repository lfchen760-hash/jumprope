import 'package:flutter_test/flutter_test.dart';
import 'package:jumprope_core/pose_source.dart';
import 'package:jumprope_core/session_result.dart';
import 'package:jumprope_app/data/app_settings.dart';
import 'package:jumprope_app/data/child_profile.dart';
import 'package:jumprope_app/data/date_utils.dart';
import 'package:jumprope_app/data/export_bundle.dart';
import 'package:jumprope_app/data/goal_entry.dart';
import 'package:jumprope_app/data/jump_benchmark.dart';
import 'package:jumprope_app/data/period_stats.dart';
import 'package:jumprope_app/data/session_record.dart';

SessionRecord session({
  required String id,
  required String date,
  required int count,
  int activeMs = 60000,
  List<int>? jumps,
  bool valid = true,
  int? grade = 3,
  Gender gender = Gender.male,
}) {
  final start = DateTime.utc(2026, 11, 9, 1, 0);
  return SessionRecord(
    id: id,
    startedAtUtc: start,
    endedAtUtc: null,
    localDate: date,
    tzOffsetMin: 480,
    mode: SessionMode.timed60,
    source: SessionSource.camera,
    count: count,
    activeMs: activeMs,
    jumps: jumps ?? List.generate(count, (i) => i * 350),
    valid: valid,
    invalidReasons: const [],
    gradeAtSession: grade,
    genderAtSession: gender,
    standardVersion: JumpBenchmark.version,
    algoVersion: 'test',
    appVersion: '0.1.0',
    createdAt: start,
  );
}

void main() {
  test('ChildProfile map roundtrip', () {
    const p = ChildProfile(
      nickname: '小宇',
      birthYear: 2018,
      grade: 3,
      gender: Gender.male,
      showBenchmark: true,
    );
    final copy = ChildProfile.fromMap(p.toMap());
    expect(copy.nickname, '小宇');
    expect(copy.grade, 3);
    expect(copy.gender, Gender.male);
    expect(copy.showBenchmark, isTrue);
    expect(copy.hasBenchmark, isTrue);
  });

  test('2014 benchmark grade 3 male', () {
    final b = JumpBenchmark.lookup(3, Gender.male);
    expect(b, isNotNull);
    expect(b!.pass, 34);
    expect(b.good, 104);
    expect(b.excellent, 116);
    expect(b.full, 126);
    expect(b.bonusFull, 166);
    expect(b.levelOf(168), BenchmarkLevel.bonusFull);
    expect(JumpBenchmark.lookup(3, Gender.unspecified), isNull);
  });

  test('session breaks, segments and average', () {
    final s = session(
      id: 's1',
      date: '2026-11-09',
      count: 4,
      activeMs: 40000,
      jumps: [1000, 11000, 11200, 11300],
    );
    expect(s.breaks, 1);
    expect(s.segments(), [1, 3, 0, 0]);
    expect(s.avgPerMinute, 6);
    final copy = SessionRecord.fromMap(s.toMap());
    expect(copy.jumps, [1000, 11000, 11200, 11300]);
    expect(copy.localDate, '2026-11-09');
    expect(copy.mode, SessionMode.timed60);
  });

  test('period stats total / best / streak', () {
    final sessions = [
      session(id: 'a', date: '2026-11-08', count: 100),
      session(id: 'b', date: '2026-11-09', count: 200),
    ];
    final stats = computePeriodStats(
      sessions,
      today: DateTime(2026, 11, 9),
      from: '2026-11-08',
      to: '2026-11-09',
    );
    expect(stats.total, 300);
    expect(stats.activeDays, 2);
    expect(stats.best, 200);
    expect(stats.streak, 2);
    expect(stats.avgPerActiveDay, 150);
  });

  test('SessionRecord.fromResult maps core result', () {
    final start = DateTime(2026, 11, 9, 9, 41);
    final result = SessionResult(
      count: 3,
      jumps: const [320, 650, 980],
      activeMs: 60000,
      plannedMs: 60000,
      completed: true,
      valid: true,
      invalidReasons: const [],
      source: SourceKind.camera,
    );
    final r = SessionRecord.fromResult(
      id: 'r1',
      result: result,
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 60)),
      mode: sessionModeForDuration(60),
      profile: const ChildProfile(grade: 3, gender: Gender.male),
      standardVersion: JumpBenchmark.version,
      algoVersion: 'test',
      appVersion: '0.1.0',
    );

    expect(r.count, 3);
    expect(r.jumps, [320, 650, 980]);
    expect(r.activeMs, 60000);
    expect(r.mode, SessionMode.timed60);
    expect(r.source, SessionSource.camera);
    expect(r.localDate, localDateOf(start));
    expect(r.tzOffsetMin, start.timeZoneOffset.inMinutes);
    expect(r.gradeAtSession, 3);
    expect(r.genderAtSession, Gender.male);
    expect(r.valid, isTrue);
    expect(r.endedAtUtc, isNotNull);
  });

  test('SessionRecord.fromResult keeps invalid reasons / replay source', () {
    final start = DateTime(2026, 11, 9, 9, 41);
    final result = SessionResult(
      count: 1,
      jumps: const [100],
      activeMs: 3000,
      plannedMs: 60000,
      completed: false,
      valid: false,
      invalidReasons: const [
        SessionResult.reasonUnfinished,
        SessionResult.reasonNotCamera,
      ],
      source: SourceKind.replay,
    );
    final r = SessionRecord.fromResult(
      id: 'r2',
      result: result,
      startedAt: start,
      endedAt: start.add(const Duration(seconds: 3)),
      mode: SessionMode.timed60,
    );

    expect(r.valid, isFalse);
    expect(r.invalidReasons, ['unfinished', 'not_camera']);
    expect(r.source, SessionSource.manual);
    expect(r.gradeAtSession, isNull);
    expect(r.genderAtSession, isNull);
  });

  test('goal history picks the effective goal', () {
    final goals = [
      const GoalEntry(
        effectiveFrom: '2026-11-01',
        dailyGoal: 200,
        createdAtMs: 0,
      ),
      const GoalEntry(
        effectiveFrom: '2026-11-09',
        dailyGoal: 300,
        createdAtMs: 0,
      ),
    ];
    expect(goalForDate(goals, '2026-11-05'), 200);
    expect(goalForDate(goals, '2026-11-09'), 300);
    expect(goalForDate(goals, '2026-10-31'), 300);
    expect(calendarLevel(150, 300), 2);
  });

  test('export bundle roundtrip', () {
    final bundle = ExportBundle(
      exportedAt: DateTime.utc(2026, 11, 9, 2),
      appVersion: '0.1.0',
      profile: const ChildProfile(
        nickname: '小宇',
        grade: 3,
        gender: Gender.male,
      ),
      settings: AppSettings.defaults(),
      goalHistory: const [
        GoalEntry(effectiveFrom: '2026-11-01', dailyGoal: 300, createdAtMs: 0),
      ],
      sessions: [session(id: 'x', date: '2026-11-09', count: 168)],
    );
    final copy = ExportBundle.fromJson(bundle.toJson());
    expect(copy.profile?.nickname, '小宇');
    expect(copy.goalHistory.length, 1);
    expect(copy.sessions.length, 1);
    expect(copy.sessions.first.count, 168);
    expect(copy.settings.installId, isNotEmpty);
  });
}
