import 'dart:convert';

import 'child_profile.dart';

enum SessionMode { timed60, timed180, free }

enum SessionSource { camera, manual }

SessionMode sessionModeFrom(Object? v) {
  for (final m in SessionMode.values) {
    if (m.name == v) return m;
  }
  return SessionMode.timed60;
}

SessionSource sessionSourceFrom(Object? v) {
  for (final s in SessionSource.values) {
    if (s.name == v) return s;
  }
  return SessionSource.camera;
}

String sessionModeLabel(SessionMode m) => switch (m) {
  SessionMode.timed60 => '1 分钟',
  SessionMode.timed180 => '3 分钟',
  SessionMode.free => '自由跳',
};

/// 一次训练。`jumps` 是唯一事实，中断/节奏/平均都从它算。
class SessionRecord {
  final String id;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final String localDate; // YYYY-MM-DD，写入时冻结
  final int tzOffsetMin;
  final SessionMode mode;
  final SessionSource source;
  final int count;
  final int activeMs;
  final List<int> jumps; // offsetMs，活动时间
  final bool valid;
  final List<String> invalidReasons;
  final int? gradeAtSession;
  final Gender? genderAtSession;
  final String? standardVersion;
  final String algoVersion;
  final String appVersion;
  final DateTime createdAt;

  SessionRecord({
    required this.id,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.localDate,
    required this.tzOffsetMin,
    required this.mode,
    required this.source,
    required this.count,
    required this.activeMs,
    required List<int> jumps,
    required this.valid,
    required this.invalidReasons,
    required this.gradeAtSession,
    required this.genderAtSession,
    required this.standardVersion,
    required this.algoVersion,
    required this.appVersion,
    required this.createdAt,
  }) : jumps = List.unmodifiable([...jumps]..sort());

  bool get isTimed60 => mode == SessionMode.timed60;

  int? get fixedDurationSec => switch (mode) {
    SessionMode.timed60 => 60,
    SessionMode.timed180 => 180,
    SessionMode.free => null,
  };

  /// 相邻两跳 > 1.5s 记一次停顿。
  int get breaks {
    var n = 0;
    for (var i = 1; i < jumps.length; i++) {
      if (jumps[i] - jumps[i - 1] > 1500) n++;
    }
    return n;
  }

  /// 按固定时长分桶（默认 10s），末段不足也保留。
  List<int> segments({int bucketMs = 10000}) {
    if (activeMs <= 0) return const [];
    final n = (activeMs + bucketMs - 1) ~/ bucketMs;
    final out = List<int>.filled(n, 0);
    for (final j in jumps) {
      final i = j ~/ bucketMs;
      if (i >= 0 && i < n) out[i]++;
    }
    return out;
  }

  /// 活跃时间太短不显示平均，避免噪声。
  int? get avgPerMinute {
    if (activeMs < 3000) return null;
    return (count * 60000 / activeMs).round();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'started_at_utc': startedAtUtc.millisecondsSinceEpoch,
    'ended_at_utc': endedAtUtc?.millisecondsSinceEpoch,
    'local_date': localDate,
    'tz_offset_min': tzOffsetMin,
    'mode': mode.name,
    'source': source.name,
    'count': count,
    'active_ms': activeMs,
    'jumps_json': jsonEncode(jumps),
    'valid': valid ? 1 : 0,
    'invalid_reasons_json': invalidReasons.isEmpty
        ? null
        : jsonEncode(invalidReasons),
    'grade_at_session': gradeAtSession,
    'gender_at_session': genderAtSession?.name,
    'standard_version': standardVersion,
    'algo_version': algoVersion,
    'app_version': appVersion,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory SessionRecord.fromMap(Map<String, dynamic> map) {
    final startedMs =
        _int(map['started_at_utc']) ?? DateTime.now().millisecondsSinceEpoch;
    final createdMs = _int(map['created_at']) ?? startedMs;
    return SessionRecord(
      id: map['id'] as String,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(startedMs, isUtc: true),
      endedAtUtc: _dateOrNull(map['ended_at_utc']),
      localDate: map['local_date'] as String,
      tzOffsetMin: _int(map['tz_offset_min']) ?? 0,
      mode: sessionModeFrom(map['mode']),
      source: sessionSourceFrom(map['source']),
      count: _int(map['count']) ?? 0,
      activeMs: _int(map['active_ms']) ?? 0,
      jumps: _jumps(map['jumps_json']),
      valid: _bool(map['valid']),
      invalidReasons: _strings(map['invalid_reasons_json']),
      gradeAtSession: _int(map['grade_at_session']),
      genderAtSession: map['gender_at_session'] == null
          ? null
          : genderFromValue(map['gender_at_session']),
      standardVersion: map['standard_version'] as String?,
      algoVersion: (map['algo_version'] as String?) ?? 'unknown',
      appVersion: (map['app_version'] as String?) ?? 'unknown',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
    );
  }
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

DateTime? _dateOrNull(Object? v) {
  final ms = _int(v);
  return ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

List<int> _jumps(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return list.whereType<num>().map((e) => e.toInt()).toList();
  } catch (_) {
    return const [];
  }
}

List<String> _strings(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return list.whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}
