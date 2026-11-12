import 'package:flutter/material.dart';

import '../data/child_profile.dart';
import '../data/data_repository.dart';
import '../data/date_utils.dart';
import '../data/video_store.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'profile_form_page.dart';
import 'profile_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _repo = DataRepository();
  int _tab = 0;
  int _dataVersion = 0;
  bool _booting = true;
  bool _needsOnboarding = false;
  ChildProfile? _profile;
  int _goal = 300;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final profile = await _repo.loadProfile();
      final settings = await _repo.loadSettings();
      final goal = await _repo.goalForDate(todayLocalDate());
      // 录像只留 3 天；启动时清一次，失败不影响 App
      try {
        await VideoStore(_repo).cleanup();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _booting = false;
        _profile = profile;
        _goal = goal;
        _needsOnboarding = profile == null || !settings.onboardingDone;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _needsOnboarding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        backgroundColor: AppColors.cream,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsOnboarding) {
      return ProfileFormPage(
        repo: _repo,
        initial: _profile,
        initialGoal: _goal,
        onboarding: true,
        onSaved: () => setState(() {
          _needsOnboarding = false;
          _dataVersion++;
        }),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomePage(
            repo: _repo,
            dataVersion: _dataVersion,
            onOpenHistory: () => setState(() => _tab = 1),
            onDataChanged: () => setState(() => _dataVersion++),
          ),
          HistoryPage(
            repo: _repo,
            dataVersion: _dataVersion,
            onDataChanged: () => setState(() => _dataVersion++),
          ),
          ProfilePage(
            repo: _repo,
            onChanged: () => setState(() => _dataVersion++),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 68,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.track,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
