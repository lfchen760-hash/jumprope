import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// 最小验证页：只用官方 camera 插件显示预览。
/// 用来判断"这台设备 + Flutter"到底能不能显示相机画面，
/// 不含 MediaPipe、不含任何自研原生代码。
class CameraTestPage extends StatefulWidget {
  const CameraTestPage({super.key});

  @override
  State<CameraTestPage> createState() => _CameraTestPageState();
}

class _CameraTestPageState extends State<CameraTestPage> {
  CameraController? _controller;
  String _status = '初始化中…';
  int _frames = 0;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      setState(() => _status = '找到 ${cameras.length} 个相机');
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;

      await controller.startImageStream((image) {
        _frames++;
        if (_frames % 10 == 0 && mounted) setState(() {});
      });

      setState(() => _status = '已启动: ${front.name}');
    } catch (e) {
      setState(() => _status = '失败: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            CameraPreview(c)
          else
            const ColoredBox(color: Color(0xFF101020)),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(6),
                color: Colors.black54,
                child: Text(
                  '$_status\n帧数: $_frames',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: () => setState(() => _ticks++),
                  child: Text('界面可交互 ✓ ($_ticks)'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
