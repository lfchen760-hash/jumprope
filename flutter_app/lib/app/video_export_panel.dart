import 'package:flutter/material.dart';

import 'theme.dart';

/// 原始录像页底部的「生成/分享带特效视频」区域。
class VideoExportPanel extends StatelessWidget {
  const VideoExportPanel({
    super.key,
    required this.exporting,
    required this.progress,
    required this.uri,
    required this.path,
    required this.error,
    required this.onExport,
    required this.onCancel,
    required this.onShare,
  });

  final bool exporting;
  final double progress;
  final String? uri;
  final String? path;
  final String? error;
  final VoidCallback onExport;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    if (uri != null) {
      return _wrap(
        children: [
          const Text(
            '带计数/倒计时的视频已保存到相册',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('分享'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: onExport, child: const Text('重新生成')),
            ],
          ),
        ],
      );
    }
    if (exporting) {
      return _wrap(
        children: [
          LinearProgressIndicator(
            value: progress <= 0 ? null : progress,
            color: AppColors.brandOrange,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '正在生成特效视频 ${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const Spacer(),
              TextButton(onPressed: onCancel, child: const Text('取消')),
            ],
          ),
        ],
      );
    }
    return _wrap(
      children: [
        if (error != null) ...[
          Text(
            '导出失败：$error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
          const SizedBox(height: 6),
        ] else if (path != null) ...[
          const Text(
            '视频已生成，但当前系统版本无法自动保存到相册',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 6),
        ],
        FilledButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('生成带计数/倒计时的视频'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandOrange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _wrap({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      color: Colors.black,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
