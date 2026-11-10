import 'dart:async';

import 'package:flutter/services.dart';

/// 每跳一下的「嘀」。原生 SoundPool 播放 res/raw/tick_*.wav。
///
/// 和 Web 版 `beep()` 对应：普通跳 990Hz，整十次 1340Hz。
/// 没有原生实现时静默降级，不影响计数。
class TickPlayer {
  TickPlayer({this.enabled = true});

  static const _channel = MethodChannel('com.jumprope/sound');

  bool enabled;

  void play({bool high = false}) {
    if (!enabled) return;
    unawaited(_play(high));
  }

  Future<void> _play(bool high) async {
    try {
      await _channel.invokeMethod<void>('playTick', {'high': high});
    } catch (_) {
      // 非 Android / 通道未注册时静默跳过
    }
  }
}
