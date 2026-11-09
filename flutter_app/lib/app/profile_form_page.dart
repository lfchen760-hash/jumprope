import 'package:flutter/material.dart';

import '../data/child_profile.dart';
import '../data/data_repository.dart';
import '../data/date_utils.dart';
import 'theme.dart';
import 'ui.dart';

/// 档案表单：首启引导和「编辑档案」共用。
///
/// - `onboarding=true`：无返回键，保存后回调 `onSaved`
/// - 编辑模式：保存后 `Navigator.pop(true)`
class ProfileFormPage extends StatefulWidget {
  const ProfileFormPage({
    super.key,
    required this.repo,
    this.initial,
    this.initialGoal = 300,
    this.onboarding = false,
    this.onSaved,
  });

  final DataRepository repo;
  final ChildProfile? initial;
  final int initialGoal;
  final bool onboarding;
  final VoidCallback? onSaved;

  @override
  State<ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<ProfileFormPage> {
  late final TextEditingController _nickname;
  late final TextEditingController _birthYear;
  int? _grade;
  Gender _gender = Gender.unspecified;
  int _goal = 300;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nickname = TextEditingController(
      text: p == null || p.nickname == ChildProfile.fallbackNickname
          ? ''
          : p.nickname,
    );
    _birthYear = TextEditingController(text: p?.birthYear?.toString() ?? '');
    _grade = p?.grade;
    _gender = p?.gender ?? Gender.unspecified;
    _goal = widget.initialGoal;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    final year = int.tryParse(_birthYear.text.trim());
    final profile = ChildProfile(
      nickname: _nickname.text.trim().isEmpty
          ? ChildProfile.fallbackNickname
          : _nickname.text.trim(),
      birthYear: year == null || year < 1990 || year > DateTime.now().year
          ? null
          : year,
      grade: _grade,
      gender: _gender,
      showBenchmark: _grade != null && _gender != Gender.unspecified,
      createdAtMs: widget.initial?.createdAtMs ?? now,
      updatedAtMs: now,
    );

    try {
      await widget.repo.saveProfile(profile);
      await widget.repo.setGoal(todayLocalDate(), _goal);
      if (widget.onboarding) {
        final settings = await widget.repo.loadSettings();
        await widget.repo.saveSettings(settings.copyWith(onboardingDone: true));
      }
      if (!mounted) return;
      if (widget.onboarding) {
        widget.onSaved?.call();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  if (!widget.onboarding)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  Text(
                    widget.onboarding ? '先认识一下' : '编辑档案',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  if (widget.onboarding) ...[
                    Text('欢迎使用跳绳计数', style: inkTitle(26)),
                    const SizedBox(height: 6),
                    const Text(
                      '填一下孩子的基本信息，用来对照国标参考线。\n'
                      '所有资料只存在这台手机。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('昵称'),
                        TextField(
                          controller: _nickname,
                          maxLength: 12,
                          decoration: const InputDecoration(
                            hintText: '小朋友',
                            counterText: '',
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('出生年份（可不填）'),
                        TextField(
                          controller: _birthYear,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          decoration: const InputDecoration(
                            hintText: '如 2018',
                            counterText: '',
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('年级'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var g = 1; g <= 6; g++)
                              _Choice(
                                label: '$g 年级',
                                selected: _grade == g,
                                onTap: () => setState(() => _grade = g),
                              ),
                            _Choice(
                              label: '不填',
                              selected: _grade == null,
                              onTap: () => setState(() => _grade = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const _FieldLabel('性别'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in Gender.values)
                              _Choice(
                                label: genderLabel(g),
                                selected: _gender == g,
                                onTap: () => setState(() => _gender = g),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('每日目标'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in const [100, 200, 300, 500])
                              _Choice(
                                label: '$g 个',
                                selected: _goal == g,
                                onTap: () => setState(() => _goal = g),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC62828),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  GradientButton(
                    label: _saving
                        ? '保存中…'
                        : widget.onboarding
                        ? '开始使用'
                        : '保存',
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '年级和性别用来对照 2014 国标；不填就不显示参考线。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.muted,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : const Color(0xFFF4EFE4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
