import 'package:flutter/material.dart';

import '../../data/session_record.dart';
import '../../data/session_video.dart';
import 'session_list.dart';

/// 默认视图：全部记录，按时间倒序，最多显示 200 条。
class AllRecordsView extends StatelessWidget {
  const AllRecordsView({
    super.key,
    required this.sessions,
    required this.today,
    required this.onDelete,
    required this.videos,
    required this.onOpenVideo,
  });

  final List<SessionRecord> sessions;
  final String today;
  final ValueChanged<SessionRecord> onDelete;
  final Map<String, SessionVideo> videos;
  final ValueChanged<SessionVideo> onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final sorted = [...sessions]
      ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
    final visible = sorted.take(200).toList();
    return SessionList(
      title: '全部记录',
      sessions: visible,
      today: today,
      truncated: sorted.length > visible.length,
      onDelete: onDelete,
      videos: videos,
      onOpenVideo: onOpenVideo,
    );
  }
}
