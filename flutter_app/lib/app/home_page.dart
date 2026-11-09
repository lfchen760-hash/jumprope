import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../data/child_profile.dart';
import '../data/data_repository.dart';
import '../data/date_utils.dart';
import '../data/session_record.dart';
import '../live_page.dart';
import 'theme.dart';
import 'ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repo,
    required this.onOpenHistory,
    required this.onDataChanged,
  });

  final DataRepository repo;
  final VoidCallback onOpenHistory;
  final VoidCallback onDataChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ChildProfile _profile = ChildProfile.defaults;
  int _goal = 300;
  int _todayTotal = 0;
  int _yesterdayTotal = 0;
  int _streak = 0;
  int? _best;
  SessionRecord? _last;
  int _durationSec = 60;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repo.loadProfile();
      final stats = await widget.repo.stats(today: DateTime.now());
      final goal = await widget.repo.goalForDate(todayLocalDate());
      final recent = await widget.repo.recentSessions(1);
      if (!mounted) return;

      final today = localDateOf(DateTime.now());
      final yesterday = addDays(today, -1);
      setState(() {
        _profile = profile ?? ChildProfile.defaults;
        _goal = goal;
        _todayTotal = stats.dailyTotals[today] ?? 0;
        _yesterdayTotal = stats.dailyTotals[yesterday] ?? 0;
        _streak = stats.streak;
        _best = stats.best;
        _last = recent.isEmpty ? null : recent.first;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '数据读取失败：$e';
      });
    }
  }

  Future<void> _startSession() async {
    final previous = _last;
    final best = _best ?? 0;
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LivePage(
          durationSec: _durationSec,
          nickname: _profile.nickname,
          previous: previous,
          previousBest: best,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    widget.onDataChanged();
    if (action == 'again') {
      await _startSession();
    } else if (action == 'history') {
      widget.onOpenHistory();
    }
  }

  double get _progress =>
      _goal <= 0 ? 0 : (_todayTotal / _goal).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final nickname = _profile.nickname;
    final remaining = (_goal - _todayTotal).clamp(0, 1 << 31);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.ink,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${greetingForHour(DateTime.now().hour)}，$nickname',
                        style: inkTitle(24),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '今天也要跳得开心',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                _Avatar(text: nickname),
              ],
            ),
            const SizedBox(height: 22),
            AppCard(
              child: Row(
                children: [
                  GradientRing(
                    size: 146,
                    stroke: 11,
                    ticks: 24,
                    progress: _progress,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_todayTotal',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Text(
                          '个',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '今日目标',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$_goal 个', style: inkTitle(28)),
                        const SizedBox(height: 6),
                        Text(
                          '已完成 ${(_progress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        const Divider(
                          height: 20,
                          thickness: 1,
                          color: AppColors.line,
                        ),
                        Text(
                          '还差 $remaining 个',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Dot(color: AppColors.brandPink),
                            const SizedBox(width: 6),
                            Text(
                              '连续 $_streak 天',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '昨天跳了 $_yesterdayTotal 个',
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
            const SizedBox(height: 20),
            _ModeSelector(
              value: _durationSec,
              onChanged: (v) => setState(() => _durationSec = v),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: '开始跳绳',
              icon: Icons.play_arrow,
              onPressed: _startSession,
            ),
            const SizedBox(height: 18),
            if (_last != null)
              _LastSessionCard(session: _last!, onTap: widget.onOpenHistory)
            else
              AppCard(
                onTap: widget.onOpenHistory,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 22,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      color: AppColors.muted,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '第一条记录等你创造',
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.muted.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ch = text.isEmpty ? '宇' : String.fromCharCode(text.runes.first);
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        gradient: AppColors.gradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [(60, '1 分钟'), (180, '3 分钟'), (0, '自由跳')];
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFE9DC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final (sec, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(sec),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == sec ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: value == sec
                        ? const [
                            BoxShadow(
                              color: Color(0x101C335F),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == sec
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: value == sec ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({required this.session, required this.onTap});

  final SessionRecord session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avg = session.avgPerMinute;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '上次成绩',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const Spacer(),
                    Text(
                      formatSessionTime(session.startedAtUtc),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${session.count} 个', style: inkTitle(22)),
                const SizedBox(height: 2),
                Text(
                  '${sessionModeLabel(session.mode)} · '
                  '${avg == null ? '平均 —' : '平均 $avg 次/分'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFAAA292)),
        ],
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
