import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'theme.dart';

class JumpropeApp extends StatelessWidget {
  const JumpropeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '跳绳计数',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
