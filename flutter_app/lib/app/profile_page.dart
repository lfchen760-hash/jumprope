import 'package:flutter/material.dart';

import '../build_info.dart';
import '../data/child_profile.dart';
import '../data/data_repository.dart';
import '../data/date_utils.dart';
import 'theme.dart';
import 'ui.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.repo});

  final DataRepository repo;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ChildProfile _profile = ChildProfile.defaults;
  int _goal = 300;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.repo.loadProfile();
      final goal = await widget.repo.goalForDate(todayLocalDate());
      if (!mounted) return;
      setState(() {
        _profile = profile ?? ChildProfile.defaults;
        _goal = goal;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final name = _profile.nickname;
    final initial = name.isEmpty ? '宇' : String.fromCharCode(name.runes.first);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          Text('我的', style: inkTitle(24)),
          const SizedBox(height: 4),
          const Text(
            '档案只存在这台手机',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  gradient: AppColors.gradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: inkTitle(22)),
                    const SizedBox(height: 4),
                    Text(
                      '${_profile.displayGrade} · ${genderLabel(_profile.gender)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          AppCard(
            child: Column(
              children: [
                _Row(label: '每日目标', value: '$_goal 个'),
                const Divider(height: 22, color: AppColors.line),
                _Row(
                  label: '年龄',
                  value: _profile.age == null ? '未填' : '${_profile.age} 岁',
                ),
                const Divider(height: 22, color: AppColors.line),
                _Row(
                  label: '国标参考线',
                  value: _profile.hasBenchmark ? '已开启' : '需要年级和性别',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '数据说明',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '视频和关键点不会上传，也不会存进数据库。'
                  '只保存每次跳了多少、什么时候跳的。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '档案编辑、导入导出、隐私设置',
                  style: TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                SizedBox(height: 4),
                Text(
                  '下一版接入',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '版本 $kBuildId',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
