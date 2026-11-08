import 'package:flutter_tts/flutter_tts.dart';

/// 语音播报：倒数、跳数、结束总结、取景提示。
///
/// 用系统 TTS，不打包音频文件；中文引擎缺失时静默降级（只是没声音）。
class VoiceService {
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  bool enabled = true;

  String? _lastSpoken;
  int _lastSpokenMs = 0;

  bool get isReady => _ready;

  /// 初始化状态摘要（诊断面板用）
  String status = '未初始化';

  Future<void> init() async {
    if (_ready) return;
    try {
      final engines = await _tts.getEngines;
      final langs = await _tts.getLanguages;
      final avail = await _tts.isLanguageAvailable('zh-CN');
      final set = await _tts.setLanguage('zh-CN');
      status = 'engines=${engines is List ? engines.length : engines} '
          'langs=${langs is List ? langs.length : langs} '
          'zhAvail=$avail setLang=$set';
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // 打断上一句，保证倒数不排队
      await _tts.awaitSpeakCompletion(false);
      _ready = true;
    } catch (e) {
      _ready = false;
      status = 'ERR $e';
    }
  }

  /// 播报一句话。[interrupt] 为 true 时先打断当前语句。
  Future<void> say(String text, {bool interrupt = true}) async {
    if (!enabled || !_ready || text.isEmpty) return;
    try {
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // 没有 TTS 引擎时不影响计数
    }
  }

  /// 同一句话不重复播报（取景提示会随帧频繁变化）
  Future<void> sayOnce(String text, {int minGapMs = 2500}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (text == _lastSpoken && now - _lastSpokenMs < minGapMs) return;
    _lastSpoken = text;
    _lastSpokenMs = now;
    await say(text);
  }

  int _lastAnnouncedCount = 0;

  /// 报数：每 [step] 个播报一次，且同一数字不重复
  Future<void> announceCount(int count, {int step = 10}) async {
    if (count <= 0 || count % step != 0) return;
    if (count == _lastAnnouncedCount) return;
    _lastAnnouncedCount = count;
    await say('$count');
  }

  void resetCount() => _lastAnnouncedCount = 0;

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }
}
