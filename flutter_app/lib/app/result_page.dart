import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/session_record.dart';
import 'theme.dart';
import 'ui.dart';

/// 一次训练的结果。传进来的 [record] 已经落库。
class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    required this.record,
    required this.nickname,
    this.previous,
    this.previousBest = 0,
    this.saveError,
  });

  final SessionRecord record;
  final String nickname;
  final SessionRecord? previous;
  final int previousBest;

  /// 落库失败时的错误信息；为空表示保存成功。
  final String? saveError;

  bool get _isRecord => record.valid && record.count > previousBest;

  int? get _delta => previous == null ? null : record.count - previous!.count;

  String get _encourage {
    if (record.count <= 0) return '再来一次吧';
    if (_isRecord) return '太棒了，$nickname！';
    final d = _delta;
    if (d != null && d > 0) return '进步了，$nickname！';
    return '完成了，$nickname！';
  }

  String? get _deltaText {
    final d = _delta;
    if (d == null) return null;
    if (d > 0) return '比上次多跳了 $d 个';
    if (d < 0) return '比上次少了 ${-d} 个';
    return '和上次一样多';
  }

  @override
  Widget build(BuildContext context) {
    final segments = record.segments();
    final reasonText = record.invalidReasons
        .map(invalidReasonLabel)
        .toSet()
        .join('、');

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    '本次成绩',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        size: 22,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_isRecord)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.actionGradient,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '新纪录',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Center(
                    child: GradientRing(
                      size: 232,
                      stroke: 13,
                      ticks: 36,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${record.count}',
                            style: const TextStyle(
                              fontSize: 74,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              color: AppColors.ink,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '次 · ${sessionModeLabel(record.mode)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _encourage,
                    textAlign: TextAlign.center,
                    style: inkTitle(24),
                  ),
                  if (_deltaText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _deltaText!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: (_delta ?? 0) > 0
                            ? AppColors.success
                            : AppColors.muted,
                      ),
                    ),
                  ],
                  if (saveError != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE9E7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '保存失败：$saveError',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC62828),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (!record.valid) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6EFE2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        reasonText.isEmpty ? '本次未计入统计' : '本次未计入统计：$reasonText',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warn,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _StatCard(
                        label: '用时',
                        value: formatClock(record.activeMs),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: '平均',
                        value: record.avgPerMinute?.toString() ?? '—',
                        unit: '次/分',
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: '中断',
                        value: '${record.breaks}',
                        unit: '次',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _RhythmCard(segments: segments, activeMs: record.activeMs),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: '再来一组',
                    onPressed: () => Navigator.of(context).pop('again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('history'),
                    child: const Text(
                      '保存并查看记录',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x101C335F),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1,
                    ),
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit!,
                    style: const TextStyle(fontSize: 9, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RhythmCard extends StatelessWidget {
  const _RhythmCard({required this.segments, required this.activeMs});

  final List<int> segments;
  final int activeMs;

  String get _stability {
    final vals = segments.where((v) => v > 0).toList();
    if (vals.length < 2) return '—';
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    if (mean <= 0) return '—';
    var sum = 0.0;
    for (final v in vals) {
      sum += (v - mean) * (v - mean);
    }
    final cv = math.sqrt(sum / vals.length) / mean;
    if (cv < 0.15) return '全程很稳';
    if (cv < 0.30) return '比较稳';
    return '有点起伏';
  }

  @override
  Widget build(BuildContext context) {
    final maxV = segments.isEmpty
        ? 0
        : segments.reduce((a, b) => a > b ? a : b);
    final stable = _stability;
    final stableColor = stable == '全程很稳'
        ? AppColors.success
        : stable == '—'
        ? AppColors.muted
        : AppColors.warn;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '节奏',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(stable, style: TextStyle(fontSize: 11, color: stableColor)),
            ],
          ),
          const SizedBox(height: 14),
          if (segments.isEmpty)
            const SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  '暂无节奏数据',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            )
          else
            SizedBox(
              height: 72,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in segments)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: maxV <= 0
                              ? 0.04
                              : (v / maxV).clamp(0.04, 1.0).toDouble(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.gradient,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '每 10 秒',
                style: TextStyle(fontSize: 9, color: AppColors.muted),
              ),
              const Spacer(),
              Text(
                durationLabel(activeMs),
                style: const TextStyle(fontSize: 9, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
