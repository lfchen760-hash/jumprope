import 'app_settings.dart';
import 'child_profile.dart';
import 'goal_entry.dart';
import 'session_record.dart';

const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0',
);

/// 导出/导入的完整载荷。schemaVersion 与数据库 user_version 独立递增。
class ExportBundle {
  static const int schemaVersion = 1;

  final DateTime exportedAt;
  final String appVersion;
  final ChildProfile? profile;
  final AppSettings settings;
  final List<GoalEntry> goalHistory;
  final List<SessionRecord> sessions;

  const ExportBundle({
    required this.exportedAt,
    required this.appVersion,
    required this.profile,
    required this.settings,
    required this.goalHistory,
    required this.sessions,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'appVersion': appVersion,
    'profile': profile?.toMap(),
    'settings': settings.toJson(),
    'goalHistory': goalHistory.map((e) => e.toMap()).toList(),
    'sessions': sessions.map((e) => e.toMap()).toList(),
  };

  factory ExportBundle.fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version <= 0) {
      throw const FormatException('导出文件缺少 schemaVersion');
    }
    if (version > schemaVersion) {
      throw FormatException('导出文件来自更新版本（$version），当前 App 只支持 $schemaVersion');
    }

    final profileRaw = json['profile'];
    final settingsRaw = json['settings'];
    final goalsRaw = json['goalHistory'];
    final sessionsRaw = json['sessions'];

    return ExportBundle(
      exportedAt: DateTime.tryParse('${json['exportedAt']}') ?? DateTime.now(),
      appVersion: (json['appVersion'] as String?) ?? 'unknown',
      profile: profileRaw is Map
          ? ChildProfile.fromMap(Map<String, dynamic>.from(profileRaw))
          : null,
      settings: settingsRaw is Map
          ? AppSettings.fromJson(Map<String, dynamic>.from(settingsRaw))
          : AppSettings.defaults(),
      goalHistory: goalsRaw is List
          ? goalsRaw
                .whereType<Map>()
                .map((e) => GoalEntry.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      sessions: sessionsRaw is List
          ? sessionsRaw
                .whereType<Map>()
                .map((e) => SessionRecord.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
    );
  }
}
