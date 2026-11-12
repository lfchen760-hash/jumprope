/// 一次会话的原始录像（干净视频 + 时间轴元数据）。
///
/// 视频文件不进数据库，只存路径；特效在导出时根据 jumps/offset 现画，
/// 所以原始录像不用重录也能换特效。
class SessionVideo {
  final String sessionId;
  final String rawPath;

  /// 录像开始时对应的会话活动时间（毫秒）。中途开始录制时 > 0。
  final int startOffsetMs;

  final int durationMs;
  final int width;
  final int height;
  final int rotation;
  final bool hasAudio;
  final int sizeBytes;
  final int createdAtMs;

  const SessionVideo({
    required this.sessionId,
    required this.rawPath,
    required this.startOffsetMs,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
    required this.hasAudio,
    required this.sizeBytes,
    required this.createdAtMs,
  });

  SessionVideo copyWith({String? sessionId}) => SessionVideo(
    sessionId: sessionId ?? this.sessionId,
    rawPath: rawPath,
    startOffsetMs: startOffsetMs,
    durationMs: durationMs,
    width: width,
    height: height,
    rotation: rotation,
    hasAudio: hasAudio,
    sizeBytes: sizeBytes,
    createdAtMs: createdAtMs,
  );

  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'raw_path': rawPath,
    'start_offset_ms': startOffsetMs,
    'duration_ms': durationMs,
    'width': width,
    'height': height,
    'rotation': rotation,
    'has_audio': hasAudio ? 1 : 0,
    'size_bytes': sizeBytes,
    'created_at': createdAtMs,
  };

  factory SessionVideo.fromMap(Map<String, dynamic> map) => SessionVideo(
    sessionId: map['session_id'] as String,
    rawPath: map['raw_path'] as String,
    startOffsetMs: _int(map['start_offset_ms']) ?? 0,
    durationMs: _int(map['duration_ms']) ?? 0,
    width: _int(map['width']) ?? 0,
    height: _int(map['height']) ?? 0,
    rotation: _int(map['rotation']) ?? 0,
    hasAudio: _bool(map['has_audio']),
    sizeBytes: _int(map['size_bytes']) ?? 0,
    createdAtMs: _int(map['created_at']) ?? 0,
  );
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
