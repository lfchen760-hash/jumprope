import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_settings.dart';
import 'child_profile.dart';
import 'export_bundle.dart';
import 'goal_entry.dart';
import 'period_stats.dart';
import 'session_record.dart';

class ImportResult {
  final int sessions;
  final int goals;
  final String backupJson;

  const ImportResult({
    required this.sessions,
    required this.goals,
    required this.backupJson,
  });
}

/// 数据层门面：UI 只依赖它，不直接碰 SQLite。
class DataRepository {
  DataRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<ChildProfile?> loadProfile() => _db.loadProfile();

  Future<void> saveProfile(ChildProfile profile) => _db.saveProfile(profile);

  Future<AppSettings> loadSettings() => _db.loadSettings();

  Future<void> saveSettings(AppSettings settings) => _db.saveSettings(settings);

  Future<void> saveSession(SessionRecord session) => _db.insertSession(session);

  Future<List<SessionRecord>> allSessions() => _db.allSessions();

  Future<List<SessionRecord>> recentSessions(int limit) =>
      _db.recentSessions(limit);

  /// 删除一条会话；日/周/月/年、纪录、连续天数都会随之重算。
  Future<void> deleteSession(String id) => _db.deleteSession(id);

  Future<List<GoalEntry>> goalHistory() => _db.goalHistory();

  Future<int> goalForDate(String date) => _db.goalForDate(date);

  Future<void> setGoal(String date, int goal) => _db.setGoal(date, goal);

  Future<PeriodStats> stats({DateTime? today, String? from, String? to}) async {
    final sessions = await _db.allSessions();
    return computePeriodStats(
      sessions,
      today: today ?? DateTime.now(),
      from: from,
      to: to,
    );
  }

  Future<ExportBundle> buildExport() async {
    final profile = await _db.loadProfile();
    final settings = await _db.loadSettings();
    final goals = await _db.goalHistory();
    final sessions = await _db.allSessions();
    return ExportBundle(
      exportedAt: DateTime.now(),
      appVersion: kAppVersion,
      profile: profile,
      settings: settings,
      goalHistory: goals,
      sessions: sessions,
    );
  }

  Future<String> exportJson() async =>
      jsonEncode((await buildExport()).toJson());

  /// 导入前会先导出一份当前数据作为 backupJson；replace=true 为整体替换。
  Future<ImportResult> importJson(String raw, {bool replace = false}) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('导入文件不是 JSON 对象');
    }
    final bundle = ExportBundle.fromJson(Map<String, dynamic>.from(decoded));
    final backupJson = await exportJson();

    final db = await _db.database;
    var sessions = 0;
    var goals = 0;
    await db.transaction((txn) async {
      if (replace) {
        for (final t in [
          AppDatabase.tableSessions,
          AppDatabase.tableProfile,
          AppDatabase.tableGoals,
          AppDatabase.tableSettings,
        ]) {
          await txn.delete(t);
        }
      }

      final profile = bundle.profile;
      if (profile != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final map = profile.toMap()
          ..['id'] = 1
          ..['created_at'] = profile.createdAtMs ?? now
          ..['updated_at'] = now;
        await txn.insert(
          AppDatabase.tableProfile,
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert(AppDatabase.tableSettings, {
        'key': AppDatabase.settingsKey,
        'value': jsonEncode(bundle.settings.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final g in bundle.goalHistory) {
        await txn.insert(
          AppDatabase.tableGoals,
          g.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        goals++;
      }

      for (final s in bundle.sessions) {
        await txn.insert(
          AppDatabase.tableSessions,
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        sessions++;
      }
    });

    return ImportResult(
      sessions: sessions,
      goals: goals,
      backupJson: backupJson,
    );
  }

  Future<void> clearAllData() => _db.clearAllData();
}
