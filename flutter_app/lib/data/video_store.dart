import 'dart:io';

import 'data_repository.dart';

/// 录像文件的生命周期：只保留 [retention] 天，删会话时一起删。
class VideoStore {
  VideoStore(this._repo);

  final DataRepository _repo;

  static const Duration retention = Duration(days: 3);

  /// App 启动时调用；删文件 + 删元数据。
  Future<void> cleanup() async {
    final cutoff = DateTime.now().subtract(retention).millisecondsSinceEpoch;
    final expired = await _repo.videosBefore(cutoff);
    for (final video in expired) {
      await _deleteFile(video.rawPath);
      await _repo.deleteVideo(video.sessionId);
    }
  }

  /// 删某条会话的录像（文件 + 元数据）。
  Future<void> deleteForSession(String sessionId) async {
    final video = await _repo.videoForSession(sessionId);
    if (video != null) await _deleteFile(video.rawPath);
    await _repo.deleteVideo(sessionId);
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 文件被占用/已删都不影响元数据清理
    }
  }
}
