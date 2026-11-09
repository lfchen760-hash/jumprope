import 'package:flutter/material.dart';

import '../data/data_repository.dart';
import '../data/date_utils.dart';
import '../data/session_record.dart';
import 'theme.dart';
import 'ui.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.repo});

  final DataRepository repo;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<SessionRecord> _sessions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.repo.recentSessions(100);
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取记录失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final children = <Widget>[];
    String? lastDate;
    for (final s in _sessions) {
      if (s.localDate != lastDate) {
        lastDate = s.localDate;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 18, bottom: 8),
            child: Text(
              _dateLabel(s.localDate),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      children.add(_SessionTile(session: s));
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.ink,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Text('记录', style: inkTitle(24)),
            const SizedBox(height: 4),
            const Text(
              '每一跳都算数',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
              )
            else if (_sessions.isEmpty)
              const _EmptyHistory()
            else
              ...children,
          ],
        ),
      ),
    );
  }

  String _dateLabel(String date) {
    final today = todayLocalDate();
    if (date == today) return '今天';
    if (date == addDays(today, -1)) return '昨天';
    return date;
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final SessionRecord session;

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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
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
