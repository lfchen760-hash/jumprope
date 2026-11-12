import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jumprope_core/jumprope_core.dart';

import 'app/result_page.dart';
import 'build_info.dart';
import 'data/data_repository.dart';
import 'data/pose/camera_pose_source.dart';
import 'data/pose/mediapipe_landmarker.dart';
import 'data/session_record.dart';
import 'data/session_saver.dart';
import 'data/session_video.dart';
import 'data/video_recorder.dart';
import 'skeleton_painter.dart';
import 'tick_player.dart';
import 'voice_service.dart';

/// 计数页：相机预览 + 骨架 + 大数字 + 计时/节奏。
///
/// 从首页带着时长进来，进页面自动启动；结束后自动落库并跳到结果页。
/// 视觉按 `design/mock-live.png`：顶部计时、下半屏大数字、底部进度和暂停。
class LivePage extends StatefulWidget {
  const LivePage({
    super.key,
    required this.durationSec,
    required this.nickname,
    this.previous,
    this.previousBest = 0,
  });

  /// 0 = 自由跳
  final int durationSec;
  final String nickname;
  final SessionRecord? previous;
  final int previousBest;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final _landmarker = MediaPipeLandmarker();
  final _saver = SessionSaver();
  final _repo = DataRepository();
  final _voice = VoiceService();
  final _tick = TickPlayer();
  final _video = VideoRecorder();

  SessionController? _controller;
  CameraPoseSource? _source;
  StreamSubscription<PoseFrame>? _lmSub;
  final ValueNotifier<PoseFrame?> _poseVN = ValueNotifier(null);
  Timer? _countdownTimer;
  StreamSubscription<SessionState>? _sub;

  SessionState _state = SessionState.idle;
  String? _error;
  String _diag = '';
  bool _showDiag = false;
  int _textureId = -1;

  DateTime? _sessionStartedAt;
  bool _handledFinish = false;
  int _lastSoundCount = 0;

  // 录像：手动开，最多一段；startOffset 用于把 jumps 映射到视频时间
  bool _recordRequested = false;
  bool _recording = false;
  bool _videoPaused = false;
  bool _videoStarting = false;
  int _videoStartOffsetMs = 0;
  RecordedVideo? _recordedVideo;

  bool get _active =>
      _state.phase == SessionPhase.running ||
      _state.phase == SessionPhase.positioning ||
      _state.phase == SessionPhase.countdown ||
      _state.phase == SessionPhase.paused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onState(SessionState s) {
    final prev = _state.phase;

    if (s.phase != prev) {
      _countdownTimer?.cancel();
      if (s.phase == SessionPhase.countdown) {
        var n = 3;
        void announce() {
          if (!mounted) return;
          _tick.play(high: n == 1);
          _voice.say('$n');
          n--;
        }

        // 3-2-1：Web 版也是进倒数立刻报 3
        announce();
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || _state.phase != SessionPhase.countdown || n < 1) {
            t.cancel();
            return;
          }
          announce();
        });
      } else if (s.phase == SessionPhase.running) {
        _sessionStartedAt = DateTime.now();
        _lastSoundCount = 0;
        _voice.resetCount();
        _tick.play(high: true);
        _voice.say('开始');
      } else if (s.phase == SessionPhase.paused) {
        _voice.say('已暂停');
      } else if (s.phase == SessionPhase.finished) {
        _tick.play(high: true);
        _voice.say('时间到，共 ${s.count} 次');
        unawaited(_finishAndShowResult());
      }
    }

    if (s.phase == SessionPhase.positioning && !s.framing.ok) {
      _voice.sayOnce(s.framing.message);
    }
    if (s.phase == SessionPhase.running) {
      _voice.announceCount(s.count);
      if (_recordRequested && !_recording) unawaited(_startVideo());
      if (_recording && _videoPaused) {
        _videoPaused = false;
        unawaited(_video.resume());
      }
    } else if (s.phase == SessionPhase.paused && _recording) {
      _videoPaused = true;
      unawaited(_video.pause());
    }

    // 每跳一下「嘀」：整十次用高音，和 Web 版 beep(count % 10 === 0) 一致
    if (s.phase == SessionPhase.running && s.count > _lastSoundCount) {
      for (var c = _lastSoundCount + 1; c <= s.count; c++) {
        _tick.play(high: c % 10 == 0);
      }
      _lastSoundCount = s.count;
    }

    if (mounted) setState(() => _state = s);
  }

  Future<void> _finishAndShowResult() async {
    if (_handledFinish) return;
    _handledFinish = true;

    final result = _controller?.result;
    final started = _sessionStartedAt;
    if (result == null || started == null || result.activeMs <= 0) {
      await _stopVideo(discard: true);
      await _leave();
      return;
    }

    // 先停录像，等 native Finalize 拿到文件信息，再落库
    final recorded = await _stopVideo();
    final ended = DateTime.now();
    SessionRecord? record;
    String? saveError;
    try {
      record = await _saver.save(
        result: result,
        startedAt: started,
        endedAt: ended,
        mode: sessionModeForDuration(widget.durationSec),
      );
    } catch (e) {
      saveError = '$e';
    }
    // 落库失败也让用户看到本次成绩，不白跳
    record ??= SessionRecord.fromResult(
      id:
          's-${started.millisecondsSinceEpoch}'
          '-${ended.millisecondsSinceEpoch}',
      result: result,
      startedAt: started,
      endedAt: ended,
      mode: sessionModeForDuration(widget.durationSec),
    );

    SessionVideo? videoRow;
    if (recorded != null && recorded.path.isNotEmpty) {
      videoRow = SessionVideo(
        sessionId: record.id,
        rawPath: recorded.path,
        startOffsetMs: _videoStartOffsetMs,
        durationMs: recorded.durationMs,
        width: recorded.width,
        height: recorded.height,
        rotation: recorded.rotation,
        hasAudio: recorded.hasAudio,
        sizeBytes: recorded.sizeBytes,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        await _repo.saveVideo(videoRow);
      } catch (_) {
        // 录像元数据失败不影响成绩
      }
    }

    await _stop();
    if (!mounted) return;

    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ResultPage(
          record: record!,
          nickname: widget.nickname,
          previous: widget.previous,
          previousBest: widget.previousBest,
          saveError: saveError,
          video: videoRow,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(action);
  }

  Future<void> _leave() async {
    await _stopVideo(discard: true);
    await _stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmClose() async {
    if (_state.phase == SessionPhase.finished) return;
    if (!_active) {
      await _leave();
      return;
    }

    final canSave =
        _state.phase == SessionPhase.running ||
        _state.phase == SessionPhase.paused;

    // 弹窗期间先停表，避免「继续跳」回来发现白走几秒
    final wasRunning = _state.phase == SessionPhase.running;
    if (wasRunning) _controller?.pause();

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('结束本次训练？'),
        content: Text(canSave ? '结束会保存当前成绩，放弃则不保存。' : '当前还没有开始计数。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续跳'),
          ),
          if (canSave)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('结束并保存'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('放弃', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      _finishEarly();
    } else if (action == 'discard') {
      await _leave();
    } else if (wasRunning) {
      _controller?.resume();
    }
  }

  Future<void> _loadDiag() async {
    final native = await _landmarker.getDiagnostics();
    final extra = StringBuffer()
      ..writeln('build=$kBuildId')
      ..writeln('dartFrames=${_source?.frameCount ?? 0}')
      ..writeln('dartPoses=${_source?.poseCount ?? 0}')
      ..writeln('phase=${_state.phase}')
      ..writeln(
        'gate=${_state.gate} framing=${_state.framing.ok}'
        ' (${_state.framing.message})',
      )
      ..writeln('textureId=$_textureId')
      ..writeln(
        'voice=${_voice.status} enabled=${_voice.enabled} '
        'ready=${_voice.isReady}',
      );
    if (!mounted) return;
    setState(() {
      _diag = '$native\n$extra';
      _showDiag = true;
    });
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _state = SessionState.idle;
      _handledFinish = false;
      _lastSoundCount = 0;
    });

    try {
      try {
        final settings = await _repo.loadSettings();
        _voice.enabled = settings.voiceEnabled;
      } catch (_) {
        // 读设置失败不影响计数，用默认语音开
      }
      await _voice.init();
      await _landmarker.init();
      _textureId = await _landmarker.getPreviewTextureId();

      final source = CameraPoseSource(_landmarker);
      _source = source;

      final controller = SessionController(
        source: source,
        durationSec: widget.durationSec,
        countdownSec: 3,
      );
      _controller = controller;

      _sub = controller.state.listen(_onState);

      _lmSub = _landmarker.frames.listen((f) {
        _poseVN.value = f.hasPose ? f : null;
      });

      await controller.start();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _state = SessionState.idle;
      });
      await _loadDiag();
      if (mounted) setState(() => _showDiag = true);
    }
  }

  void _togglePause() {
    final c = _controller;
    if (c == null) return;
    if (_state.phase == SessionPhase.paused) {
      c.resume();
    } else if (_state.phase == SessionPhase.running) {
      c.pause();
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopVideo();
      _recordRequested = false;
      if (mounted) _snack('已停止录像');
      return;
    }
    if (_recordedVideo != null) {
      _snack('本次已经录过一段，结束后可在结果页查看');
      return;
    }
    setState(() => _recordRequested = !_recordRequested);
    if (!_recordRequested) {
      _snack('已关闭录像');
      return;
    }
    if (_state.phase == SessionPhase.running) {
      await _startVideo();
    } else {
      _snack('已开启录像，开始计数后自动录制');
    }
  }

  Future<void> _startVideo() async {
    if (_recording || _recordedVideo != null || _videoStarting) return;
    _videoStarting = true;
    try {
      final path = await _video.start();
      if (!mounted) {
        await _video.stop();
        return;
      }
      if (_state.phase != SessionPhase.running &&
          _state.phase != SessionPhase.paused) {
        await _video.stop();
        return;
      }
      if (path == null) {
        setState(() => _recordRequested = false);
        _snack('录像启动失败');
        return;
      }
      setState(() {
        _recording = true;
        _recordRequested = false;
        _videoPaused = false;
        _videoStartOffsetMs = _state.activeMs;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _recordRequested = false);
      _snack('录像启动失败：${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordRequested = false);
      _snack('录像启动失败：$e');
    } finally {
      _videoStarting = false;
    }
  }

  /// 停止录像；discard=true 时把文件删掉（放弃本次训练）。
  Future<RecordedVideo?> _stopVideo({bool discard = false}) async {
    var info = _recordedVideo;
    if (_recording) {
      try {
        info = await _video.stop();
      } catch (_) {
        info = null;
      }
      _recording = false;
      _videoPaused = false;
    }
    _recordedVideo = info;
    if (discard && info != null) {
      try {
        final file = File(info.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _recordedVideo = null;
    }
    if (mounted) setState(() {});
    return _recordedVideo;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toggleVoice() {
    setState(() => _voice.enabled = !_voice.enabled);
    if (!_voice.enabled) unawaited(_voice.stop());
    unawaited(_persistVoice());
  }

  Future<void> _persistVoice() async {
    try {
      final settings = await _repo.loadSettings();
      await _repo.saveSettings(settings.copyWith(voiceEnabled: _voice.enabled));
    } catch (_) {
      // 设置保存失败不影响本次计数
    }
  }

  void _finishEarly() {
    final c = _controller;
    if (c == null) {
      unawaited(_leave());
      return;
    }
    c.finishEarly();
  }

  Future<void> _flip() async {
    if (_recording) {
      _snack('录像中不能切换摄像头');
      return;
    }
    try {
      await _source?.flip();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '切换摄像头失败: $e');
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _lmSub?.cancel();
    _lmSub = null;
    _poseVN.value = null;
    _countdownTimer?.cancel();
    await _voice.stop();
    await _controller?.stop();
    _controller = null;
    if (mounted) setState(() => _state = SessionState.idle);
  }

  @override
  void dispose() {
    if (_recording) {
      // 页面被直接销毁（非正常结束）时兜底：停录像并删文件
      unawaited(
        _video.stop().then((info) async {
          if (info == null) return;
          try {
            final file = File(info.path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }),
      );
    }
    _sub?.cancel();
    _lmSub?.cancel();
    _poseVN.dispose();
    _countdownTimer?.cancel();
    _voice.dispose();
    _controller?.dispose();
    _landmarker.dispose();
    super.dispose();
  }

  /// 顶部状态文案：就位 / 出框 / 走动 / 弯腰 / 暂停。
  String get _statusText {
    switch (_state.phase) {
      case SessionPhase.idle:
        return '正在启动相机…';
      case SessionPhase.positioning:
        return _state.framing.ok ? '已就位 · 全身入镜' : _state.framing.message;
      case SessionPhase.countdown:
        return '准备…';
      case SessionPhase.running:
        if (_state.gate == 'move') return '检测到走动，暂停计数';
        if (_state.gate == 'bend') return '检测到弯腰，暂停计数';
        return '已就位 · 全身入镜';
      case SessionPhase.paused:
        return '已暂停';
      case SessionPhase.finished:
        return '正在生成结果…';
    }
  }

  bool get _statusWarn {
    if (_state.phase == SessionPhase.positioning) return !_state.framing.ok;
    if (_state.phase == SessionPhase.running) return _state.gate != 'ok';
    return _error != null;
  }

  String _clockFor(int ms) {
    final total = (ms / 1000).round().clamp(0, 24 * 3600).toInt();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final idle = _state.phase == SessionPhase.idle;
    final finished = _state.phase == SessionPhase.finished;
    final active = !idle && !finished;

    final timed = widget.durationSec > 0;
    final progress = timed && _state.activeMs > 0
        ? (_state.activeMs / (widget.durationSec * 1000))
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    final remainSec = (_state.remainingMs / 1000).ceil();
    final avg = _state.activeMs >= 3000 && _state.count > 0
        ? (_state.count * 60000 / _state.activeMs).round()
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<PoseFrame?>(
                valueListenable: _poseVN,
                builder: (_, frame, __) {
                  final lms = frame?.landmarks ?? const <Landmark>[];
                  return CustomPaint(
                    painter: SkeletonPainter(
                      lms,
                      mirrored: _source?.front ?? true,
                    ),
                  );
                },
              ),
            ),
          ),

          if (_showDiag)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showDiag = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.92),
                  padding: const EdgeInsets.fromLTRB(14, 44, 14, 14),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _diag.isEmpty ? '（长按状态条获取）' : _diag,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: 'monospace',
                        color: Color(0xFFB9F6CA),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 上下压暗，保证白字可读
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 420,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.62),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _topBar(),
                if (active) ...[
                  const SizedBox(height: 10),
                  GestureDetector(onLongPress: _loadDiag, child: _statusPill()),
                  if ((_source?.frameCount ?? 0) == 0) ...[
                    const SizedBox(height: 8),
                    _hintPill('相机没有输出画面（权限或初始化失败）'),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    _hintPill('相机错误：$_error'),
                  ],
                ],
                if (idle && _error == null) ...[
                  const Spacer(),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 14),
                  Text(
                    '正在启动相机…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const Spacer(),
                ],
                if (finished) ...[
                  const Spacer(),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 14),
                  Text(
                    '正在生成结果…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const Spacer(),
                ],
                if (_error != null && !active) ...[
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _start,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                        ),
                        child: const Text('重试'),
                      ),
                      TextButton(
                        onPressed: _leave,
                        child: Text(
                          '返回',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
                if (active) ...[
                  const Spacer(),
                  Text(
                    '当前次数',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_state.count}',
                        style: const TextStyle(
                          fontSize: 104,
                          fontWeight: FontWeight.w800,
                          height: 0.95,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                          shadows: [
                            Shadow(blurRadius: 26, color: Colors.black54),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 16),
                        child: Text(
                          '次',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    avg == null ? '平均 — 次/分' : '平均 $avg 次/分',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        if (timed) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              height: 6,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFFF8A1F),
                                            Color(0xFFFF2D6B),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Text(
                              _clockFor(_state.activeMs),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              timed ? '剩余 $remainSec 秒' : '自由跳',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _togglePause,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _state.phase == SessionPhase.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _state.phase == SessionPhase.paused ? '继续' : '暂停',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.close_rounded,
            onTap: _confirmClose,
            tooltip: '结束',
          ),
          const SizedBox(width: 6),
          _circleButton(
            icon: _recording
                ? Icons.stop_circle_outlined
                : Icons.videocam_outlined,
            onTap: _toggleRecord,
            tooltip: _recording ? '停止录像' : '录制本次',
            color: _recording ? Colors.redAccent : Colors.white,
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _clockFor(
                        _state.phase == SessionPhase.idle
                            ? widget.durationSec * 1000
                            : widget.durationSec > 0
                            ? _state.remainingMs
                            : _state.activeMs,
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _circleButton(
            icon: Icons.cameraswitch_outlined,
            onTap: _flip,
            tooltip: '翻转',
          ),
          const SizedBox(width: 6),
          _circleButton(
            icon: _voice.enabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            onTap: _toggleVoice,
            tooltip: _voice.enabled ? '关闭语音' : '打开语音',
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color color = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }

  Widget _statusPill() {
    final warn = _statusWarn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: warn ? const Color(0xFFE89634) : const Color(0xFF1EAA69),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 12,
              color: warn ? const Color(0xFFFFC266) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.amber),
      ),
    );
  }
}
