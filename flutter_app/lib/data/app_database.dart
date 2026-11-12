import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_settings.dart';
import 'child_profile.dart';
import 'date_utils.dart';
import 'goal_entry.dart';
import 'session_record.dart';
import 'session_video.dart';

/// 本地 SQLite。schema v3；以后只加不删，迁移前备份。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int schemaVersion = 3;
  static const String settingsKey = 'app_settings_v1';

  static const String tableProfile = 'profile';
  static const String tableSessions = 'sessions';
  static const String tableGoals = 'goal_history';
  static const String tableSettings = 'settings';
  static const String tableVideos = 'session_videos';

  static const String _createVideosSql =
      '''
    CREATE TABLE IF NOT EXISTS $tableVideos (
      session_id TEXT PRIMARY KEY,
      raw_path TEXT NOT NULL,
      start_offset_ms INTEGER NOT NULL DEFAULT 0,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      width INTEGER NOT NULL DEFAULT 0,
      height INTEGER NOT NULL DEFAULT 0,
      rotation INTEGER NOT NULL DEFAULT 0,
      has_audio INTEGER NOT NULL DEFAULT 0,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
  ''';

  static const String _createVideosIndexSql =
      'CREATE INDEX IF NOT EXISTS idx_videos_created '
      'ON $tableVideos(created_at)';

  static const String _dbName = 'jumprope.db';

  Future<Database>? _openFuture;
  String? _path;

  Future<Database> get database => _openFuture ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    _path = p.join(dir, _dbName);
    return openDatabase(
      _path!,
      version: schemaVersion,
      onConfigure: (db) async {
        final old =
            Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ??
            0;
        if (old > 0 && old < schemaVersion && _path != null) {
          final f = File(_path!);
          if (await f.exists()) {
            await f.copy('${_path!}.bak-v$old');
          }
        }
      },
      onCreate: (db, version) async {
        final b = db.batch();
        b.execute('''
          CREATE TABLE $tableProfile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            nickname TEXT NOT NULL,
            birth_year INTEGER,
            grade INTEGER,
            gender TEXT NOT NULL DEFAULT 'unspecified',
            show_benchmark INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER,
            updated_at INTEGER
          )
        ''');
        b.execute('''
          CREATE TABLE $tableSessions (
            id TEXT PRIMARY KEY,
            started_at_utc INTEGER NOT NULL,
            ended_at_utc INTEGER,
            local_date TEXT NOT NULL,
            tz_offset_min INTEGER NOT NULL,
            mode TEXT NOT NULL,
            source TEXT NOT NULL,
            count INTEGER NOT NULL,
            active_ms INTEGER NOT NULL,
            jumps_json TEXT NOT NULL,
            valid INTEGER NOT NULL DEFAULT 1,
            invalid_reasons_json TEXT,
            grade_at_session INTEGER,
            gender_at_session TEXT,
            standard_version TEXT,
            algo_version TEXT,
            app_version TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        b.execute(
          'CREATE INDEX idx_sessions_date ON $tableSessions(local_date)',
        );
        b.execute(
          'CREATE INDEX idx_sessions_started ON $tableSessions(started_at_utc)',
        );
        b.execute('''
          CREATE TABLE $tableGoals (
            effective_from TEXT PRIMARY KEY,
            daily_goal INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        b.execute('''
          CREATE TABLE $tableSettings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        b.execute(_createVideosSql);
        b.execute(_createVideosIndexSql);
        await b.commit(noResult: true);

        await db.insert(
          tableGoals,
          GoalEntry(
            effectiveFrom: todayLocalDate(),
            dailyGoal: 300,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 是初始版本。以后按版本号追加 ALTER/CREATE，只加不删。
        if (oldVersion < 2) {
          // v2：提前结束/出框不再自动判无效。
          // 把旧库里仅因此被标无效的会话改回计入，并清掉这些原因；
          // 0 跳 / 非相机仍然保持无效。备份由 onConfigure 完成。
          await db.rawUpdate('''
            UPDATE $tableSessions
            SET valid = 1, invalid_reasons_json = NULL
            WHERE valid = 0
              AND count > 0
              AND source = 'camera'
              AND (
                invalid_reasons_json IS NULL
                OR (
                  invalid_reasons_json NOT LIKE '%no_jumps%'
                  AND invalid_reasons_json NOT LIKE '%not_camera%'
                )
              )
          ''');
        }
        if (oldVersion < 3) {
          // v3：原始录像元数据；视频文件本身不进库。
          await db.execute(_createVideosSql);
          await db.execute(_createVideosIndexSql);
        }
      },
      onDowngrade: (db, oldVersion, newVersion) async {
        throw StateError('数据库版本 $oldVersion 高于当前 App 支持的 $newVersion，请升级 App');
      },
    );
  }

  Future<ChildProfile?> loadProfile() async {
    final db = await database;
    final rows = await db.query(tableProfile, limit: 1);
    if (rows.isEmpty) return null;
    return ChildProfile.fromMap(rows.first);
  }

  Future<void> saveProfile(ChildProfile profile) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = profile.toMap()
      ..['id'] = 1
      ..['created_at'] = profile.createdAtMs ?? now
      ..['updated_at'] = now;
    await db.insert(
      tableProfile,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSession(SessionRecord session) async {
    final db = await database;
    await db.insert(
      tableSessions,
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SessionRecord>> sessionsBetween(String from, String to) async {
    final db = await database;
    final rows = await db.query(
      tableSessions,
      where: 'local_date >= ? AND local_date <= ?',
      whereArgs: [from, to],
      orderBy: 'started_at_utc ASC',
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  Future<List<SessionRecord>> allSessions() async {
    final db = await database;
    final rows = await db.query(tableSessions, orderBy: 'started_at_utc DESC');
    return rows.map(SessionRecord.fromMap).toList();
  }

  Future<List<SessionRecord>> recentSessions(int limit) async {
    final db = await database;
    final rows = await db.query(
      tableSessions,
      orderBy: 'started_at_utc DESC',
      limit: limit,
    );
    return rows.map(SessionRecord.fromMap).toList();
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    await db.delete(tableSessions, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveVideo(SessionVideo video) async {
    final db = await database;
    await db.insert(
      tableVideos,
      video.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SessionVideo?> videoForSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      tableVideos,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : SessionVideo.fromMap(rows.first);
  }

  Future<List<SessionVideo>> allVideos() async {
    final db = await database;
    final rows = await db.query(tableVideos, orderBy: 'created_at DESC');
    return rows.map(SessionVideo.fromMap).toList();
  }

  Future<void> deleteVideo(String sessionId) async {
    final db = await database;
    await db.delete(
      tableVideos,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<SessionVideo>> videosBefore(int createdAtMs) async {
    final db = await database;
    final rows = await db.query(
      tableVideos,
      where: 'created_at < ?',
      whereArgs: [createdAtMs],
    );
    return rows.map(SessionVideo.fromMap).toList();
  }

  Future<List<GoalEntry>> goalHistory() async {
    final db = await database;
    final rows = await db.query(tableGoals, orderBy: 'effective_from ASC');
    return rows.map(GoalEntry.fromMap).toList();
  }

  Future<int> goalForDate(String date) async {
    final db = await database;
    final rows = await db.query(
      tableGoals,
      where: 'effective_from <= ?',
      whereArgs: [date],
      orderBy: 'effective_from DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 300;
    return (rows.first['daily_goal'] as num).toInt();
  }

  Future<void> setGoal(String date, int goal) async {
    final db = await database;
    await db.insert(
      tableGoals,
      GoalEntry(
        effectiveFrom: date,
        dailyGoal: goal,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AppSettings> loadSettings() async {
    final db = await database;
    final rows = await db.query(
      tableSettings,
      where: 'key = ?',
      whereArgs: [settingsKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      final s = AppSettings.defaults();
      await saveSettings(s);
      return s;
    }
    try {
      final raw = rows.first['value'] as String;
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      final s = AppSettings.defaults();
      await saveSettings(s);
      return s;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await database;
    await db.insert(tableSettings, {
      'key': settingsKey,
      'value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in [
        tableSessions,
        tableVideos,
        tableProfile,
        tableGoals,
        tableSettings,
      ]) {
        await txn.delete(t);
      }
    });
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<void> close() async {
    final f = _openFuture;
    _openFuture = null;
    if (f != null) {
      final db = await f;
      await db.close();
    }
  }
}
