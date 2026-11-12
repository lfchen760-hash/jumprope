import 'package:flutter/material.dart';

import '../data/child_profile.dart';
import '../data/data_repository.dart';
import '../data/date_utils.dart';
import '../data/goal_entry.dart';
import '../data/period.dart';
import '../data/period_stats.dart';
import '../data/session_record.dart';
import 'history/all_records_view.dart';
import 'history/delete_session.dart';
import 'history/error_card.dart';
import 'history/history_aggregates.dart';
import 'history/history_header.dart';
import 'history/period_best_card.dart';
import 'history/period_calendar.dart';
import 'history/period_summary_card.dart';
import 'history/period_tabs.dart';
import 'history/session_list.dart';
import 'theme.dart';

/// 记录页：日 / 周 / 月 / 年 + 月历热力 + 明细。
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.repo,
    required this.dataVersion,
    required this.onDataChanged,
  });

  final DataRepository repo;
  final int dataVersion;
  final VoidCallback onDataChanged;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<SessionRecord> _sessions = const [];
  List<GoalEntry> _goals = const [];
  ChildProfile? _profile;
  bool _loading = true;
  String? _error;
  bool _calendarMode = true;
  PeriodKind _kind = PeriodKind.month;
  String _anchor = todayLocalDate();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataVersion != widget.dataVersion) _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.repo.allSessions();
      final goals = await widget.repo.goalHistory();
      final profile = await widget.repo.loadProfile();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _goals = goals;
        _profile = profile;
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

    final today = todayLocalDate();
    final now = DateTime.now();
    final range = rangeFor(_kind, _anchor);
    final stats = computePeriodStats(
      _sessions,
      today: now,
      from: range.start,
      to: range.end,
    );
    final prev = previousRange(range);
    final prevStats = computePeriodStats(
      _sessions,
      today: now,
      from: prev.start,
      to: prev.end,
    );

    String? compareText;
    bool? comparePositive;
    if (range.start.compareTo(today) > 0) {
      compareText = '还没到';
    } else if (range.end.compareTo(today) < 0) {
      final pct = percentChange(stats.total, prevStats.total);
      if (pct == null) {
        compareText = '上期暂无记录';
      } else {
        compareText = '${pct >= 0 ? '+' : ''}$pct% 较上期';
        comparePositive = pct >= 0;
      }
    } else {
      compareText = '本周期进行中';
    }

    final totals = <String, int>{};
    final hasAny = <String>{};
    final inRange = <SessionRecord>[];
    for (final session in _sessions) {
      if (!range.contains(session.localDate)) continue;
      inRange.add(session);
      hasAny.add(session.localDate);
      if (session.valid) {
        totals[session.localDate] =
            (totals[session.localDate] ?? 0) + session.count;
      }
    }
    inRange.sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));

    final levels = <String, int>{};
    for (final entry in totals.entries) {
      levels[entry.key] = calendarLevel(
        entry.value,
        goalForDate(_goals, entry.key),
      );
    }

    final best = bestSession(inRange);
    final benchmark = benchmarkFor(best, _profile);

    final visible = inRange.take(100).toList();
    final sortedYears = availableYears(_sessions, [
      now.year,
      parseLocalDate(_anchor).year,
    ]);
    final daySessions = inRange
        .where((s) => s.localDate == range.start)
        .toList();
    final rangeYear = parseLocalDate(range.start).year;
    final todayDate = parseLocalDate(today);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.ink,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            HistoryHeader(
              profile: _profile,
              year: parseLocalDate(range.start).year,
              years: sortedYears,
              onYearSelected: _selectYear,
              calendarMode: _calendarMode,
              onToggleMode: () {
                setState(() => _calendarMode = !_calendarMode);
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              ErrorCard(message: _error!, onRetry: _load)
            else if (_sessions.isEmpty)
              const EmptyHistory()
            else if (!_calendarMode)
              AllRecordsView(
                sessions: _sessions,
                today: today,
                onDelete: _confirmDelete,
              )
            else ...[
              PeriodTabs(selected: _kind, onChanged: _selectKind),
              const SizedBox(height: 12),
              PeriodSummaryCard(
                spanLabel: rangeSpan(range, today),
                stats: stats,
                compareText: compareText,
                comparePositive: comparePositive,
              ),
              const SizedBox(height: 12),
              PeriodCalendar(
                kind: _kind,
                range: range,
                today: today,
                totals: totals,
                levels: levels,
                hasAny: hasAny,
                daySessionCount: daySessions.length,
                dayGoal: goalForDate(_goals, range.start),
                dayBest: bestCount(daySessions),
                monthlyTotals: monthlyTotals(_sessions, rangeYear),
                currentMonth: rangeYear == todayDate.year
                    ? todayDate.month
                    : null,
                onSelectDay: _selectDay,
                onSelectMonth: (month) => _selectMonth(rangeYear, month),
                onPrev: () => _shift(-1),
                onNext: () => _shift(1),
                onToday: _goToday,
                showToday: !range.contains(today),
              ),
              const SizedBox(height: 12),
              PeriodBestCard(
                label: bestLabel(_kind),
                best: best,
                benchmark: benchmark,
              ),
              const SizedBox(height: 18),
              SessionList(
                sessions: visible,
                today: today,
                truncated: inRange.length > visible.length,
                onDelete: _confirmDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(SessionRecord session) async {
    try {
      final deleted = await confirmDeleteSession(
        context,
        repo: widget.repo,
        session: session,
      );
      if (!deleted || !mounted) return;
      // AppShell 会自增 dataVersion，didUpdateWidget 里重新读库。
      widget.onDataChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('记录已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  void _shift(int delta) {
    final next = shiftRange(rangeFor(_kind, _anchor), delta);
    setState(() => _anchor = next.start);
  }

  void _goToday() {
    setState(() => _anchor = todayLocalDate());
  }

  void _selectKind(PeriodKind kind) {
    if (kind == _kind) return;
    setState(() => _kind = kind);
  }

  void _selectDay(String date) {
    setState(() {
      _kind = PeriodKind.day;
      _anchor = date;
    });
  }

  void _selectMonth(int year, int month) {
    setState(() {
      _kind = PeriodKind.month;
      _anchor = '$year-${month.toString().padLeft(2, '0')}-01';
    });
  }

  void _selectYear(int year) {
    if (year == parseLocalDate(_anchor).year) return;
    setState(() {
      _kind = PeriodKind.year;
      _anchor = yearStartOf(year);
    });
  }
}
