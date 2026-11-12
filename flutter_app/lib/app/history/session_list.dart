import 'package:flutter/material.dart';

import '../../data/date_utils.dart';
import '../../data/period.dart';
import '../../data/session_record.dart';
import '../../data/session_video.dart';
import '../theme.dart';
import '../ui.dart';

/// 所选周期内的会话明细，按日期分组。
class SessionList extends StatelessWidget {
  const SessionList({
    super.key,
    required this.sessions,
    required this.today,
    this.title = '明细',
    this.truncated = false,
    this.onDelete,
    this.videos = const {},
    this.onOpenVideo,
  });

  final List<SessionRecord> sessions;
  final String today;
  final String title;
  final bool truncated;
  final ValueChanged<SessionRecord>? onDelete;
  final Map<String, SessionVideo> videos;
  final ValueChanged<SessionVideo>? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SessionRecord>>{};
    for (final session in sessions) {
      groups.putIfAbsent(session.localDate, () => []).add(session);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final children = <Widget>[];
    for (final date in dates) {
      final items = groups[date]!;
      var sum = 0;
      for (final item in items) {
        if (item.valid) sum += item.count;
      }
      children.add(
        Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 16, bottom: 7),
          child: Row(
            children: [
              Text(
                _dateLabel(date),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              if (sum > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '· $sum 个',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      );
      for (final session in items) {
        children.add(
          _SessionTile(
            session: session,
            onDelete: onDelete,
            video: videos[session.id],
            onOpenVideo: onOpenVideo,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: inkTitle(16)),
            const Spacer(),
            Text(
              '${sessions.length} 次',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                '这段时间还没有记录',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          )
        else ...[
          ...children,
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '仅显示最近 ${sessions.length} 条',
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ),
        ],
      ],
    );
  }

  String _dateLabel(String date) {
    if (date == today) return '今天';
    if (date == addDays(today, -1)) return '昨天';
    final d = parseLocalDate(date);
    final sameYear = d.year == parseLocalDate(today).year;
    return sameYear ? shortMonthDay(date) : fullDate(date);
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    this.onDelete,
    this.video,
    this.onOpenVideo,
  });

  final SessionRecord session;
  final ValueChanged<SessionRecord>? onDelete;
  final SessionVideo? video;
  final ValueChanged<SessionVideo>? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final avg = session.avgPerMinute;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                formatSessionTime(session.startedAtUtc).split(' ').last,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${session.count}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1,
                        ),
                      ),
                      const Text(
                        ' 个',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                      const Spacer(),
                      if (!session.valid)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EEE2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '未计入',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      if (video != null && onOpenVideo != null)
                        IconButton(
                          onPressed: () => onOpenVideo!(video!),
                          icon: const Icon(Icons.play_circle_outline, size: 18),
                          color: AppColors.inkSoft,
                          tooltip: '查看录像',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          onPressed: () => onDelete!(session),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: AppColors.muted,
                          tooltip: '删除记录',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sessionModeLabel(session.mode)} · '
                    '${avg == null ? '平均 —' : '平均 $avg 次/分'}'
                    '${session.breaks > 0 ? ' · 中断 ${session.breaks} 次' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条记录都没有时的空状态。
class EmptyHistory extends StatelessWidget {
  const EmptyHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 70, bottom: 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.track,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.show_chart,
              color: AppColors.muted,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '第一条记录等你创造',
            style: TextStyle(fontSize: 15, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          const Text(
            '跳完一组就会出现在这里',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
