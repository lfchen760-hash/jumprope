import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/data_repository.dart';
import 'theme.dart';
import 'ui.dart';

/// 训练相关设置：每次自动录像 / 训练时屏幕常亮。
///
/// 自己读写 `AppSettings`，避免把切换逻辑都塞进 ProfilePage。
class TrainingSettingsCard extends StatefulWidget {
  const TrainingSettingsCard({super.key, required this.repo});

  final DataRepository repo;

  @override
  State<TrainingSettingsCard> createState() => _TrainingSettingsCardState();
}

class _TrainingSettingsCardState extends State<TrainingSettingsCard> {
  AppSettings? _settings;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repo.loadSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // 不要用 AppSettings.defaults() 顶上：它会新生成 installId，
      // 用户一拨开关就会把安装标识覆盖掉。
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _save(AppSettings next) async {
    final prev = _settings;
    setState(() => _settings = next);
    try {
      await widget.repo.saveSettings(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _settings = prev);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置保存失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError) {
      return const AppCard(
        child: Text(
          '设置读取失败，重启 App 后再试',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      );
    }
    final s = _settings;
    if (s == null) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.autoRecord,
            onChanged: (v) => _save(s.copyWith(autoRecord: v)),
            title: const Text(
              '每次训练自动录像',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            subtitle: const Text(
              '开始计数后自动录制，可在计数页点摄像机停止；录像只保留 3 天',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.keepAwake,
            onChanged: (v) => _save(s.copyWith(keepAwake: v)),
            title: const Text(
              '训练时屏幕常亮',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            subtitle: const Text(
              '跳的时候不会自动息屏；会略微增加耗电',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
