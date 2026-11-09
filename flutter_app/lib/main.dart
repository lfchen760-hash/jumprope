import 'package:flutter/material.dart';

import 'app/app.dart';
import 'build_info.dart';
import 'camera_test_page.dart';

void main() => runApp(kCameraTest ? const _TestApp() : const JumpropeApp());

/// 相机最小验证：`--dart-define=CAMERA_TEST=true`
class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraTestPage(),
    );
  }
}
