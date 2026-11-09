import 'package:flutter/material.dart';

import '../data/data_repository.dart';
import 'history_page.dart';
import 'home_page.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomePage(
            repo: _repo,
            onOpenHistory: () => setState(() => _tab = 1),
            onDataChanged: () => setState(() => _dataVersion++),
          ),
          HistoryPage(key: ValueKey('history-$_dataVersion'), repo: _repo),
          ProfilePage(repo: _repo),
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
