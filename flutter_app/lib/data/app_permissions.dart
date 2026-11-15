import 'package:flutter/services.dart';

class SessionPermissions {
  const SessionPermissions({required this.camera, required this.audio});

  final bool camera;
  final bool audio;
}

/// 点「开始跳绳」时一次性申请相机 + 麦克风，避免进计数页后再弹窗。
Future<SessionPermissions> requestSessionPermissions() async {
  const channel = MethodChannel('com.jumprope/pose');
  try {
    final map = await channel.invokeMapMethod<String, bool>(
      'requestPermissions',
    );
    return SessionPermissions(
      camera: map?['camera'] ?? false,
      audio: map?['audio'] ?? false,
    );
  } on MissingPluginException {
    // 旧包没有该通道时保持可用；新包一定走原生弹窗
    return const SessionPermissions(camera: true, audio: true);
  } on PlatformException {
    return const SessionPermissions(camera: false, audio: false);
  }
}
