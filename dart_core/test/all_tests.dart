/// 无第三方依赖的测试 runner。
///
///   dart run test/all_tests.dart
///
/// 之所以不用 package:test —— 本机沙箱限制 pub 缓存的 rename（cross-device link），
/// `dart pub get` 装不了带依赖的包。纯 Dart 断言已经够用。
library;

import 'dart:convert';
import 'dart:io';

import '../lib/counter.dart';
import '../lib/landmark.dart';
import '../lib/framing.dart';
import '../lib/pose_frame.dart';
import '../lib/pose_source.dart';
import '../lib/posture.dart';
import '../lib/replay_pose_source.dart';
import '../lib/session_controller.dart';
import '../lib/session_result.dart';
import '../lib/session_state.dart';
import 'dart:async';

int _pass = 0;
int _fail = 0;
final List<String> _failures = [];

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    _failures.add('$name${detail == null ? '' : ' — $detail'}');
  }
}

void checkClose(String name, double actual, double expected, double tol) {
  check(name, (actual - expected).abs() <= tol,
      '期望 $expected，实际 $actual，容差 $tol');
}

void section(String title) {
  print('\n▶ $title');
}

/* ---------------- 计数核心 ---------------- */

Map<String, dynamic> _loadJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<dynamic> _framesOf(Map<String, dynamic> d) => d['frames'] as List;

int _runCounter(Map<String, dynamic> d) {
  final c = Counter();
  for (final fr in _framesOf(d)) {
    final a = fr as List;
    c.feed(
      (a[1] as num).toDouble(),
      (a[2] as num).toDouble(),
      (a[0] as num).toDouble(),
      PoseContext(
        hipX: (a[3] as num).toDouble(),
        tilt: (a[4] as num).toDouble(),
        kneeL: (a[5] as num).toDouble(),
        kneeR: (a[6] as num).toDouble(),
      ),
    );
  }
  return c.count;
}

void testGoldenVectors() {
  section('黄金向量（与 JS 版逐案例一致）');
  final dir = Directory('../jumprope/test/golden');
  if (!dir.existsSync()) {
    check('黄金向量目录存在', false, dir.path);
    return;
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  check('至少有一段向量', files.isNotEmpty);

  for (final f in files) {
    final d = _loadJson(f.path);
    final expected = (d['expected'] as num).toInt();
    final label = (d['labelCount'] as num?)?.toInt();
    final actual = _runCounter(d);
    final name = (d['name'] as String?) ?? f.uri.pathSegments.last;
    print(
        '   ${name.padRight(16)} Dart $actual  期望 $expected  标注 ${label ?? '-'}');
    check('$name 计数一致', actual == expected, '期望 $expected，实际 $actual');
  }
}

void testCounterBehaviour() {
  section('计数核心行为');

  // 静止不计数
  {
    final c = Counter();
    var t = 0.0;
    for (var i = 0; i < 300; i++) {
      c.feed(0.55 + (i % 3 - 1) * 0.0005, 0.18, t,
          const PoseContext(hipX: 0.5, tilt: 0, kneeL: 178, kneeR: 178));
      t += 33;
    }
    check('静止时计数为 0', c.count == 0, '实际 ${c.count}');
  }

  // 周期性跳跃会计数
  {
    final c = Counter();
    var t = 0.0;
    for (var i = 0; i < 180; i++) {
      final phase = (i % 12) / 12 * 2 * 3.14159265;
      final y = 0.55 - 0.05 * (phase < 3.14159 ? 1.0 : 0.0);
      c.feed(y, 0.18, t,
          const PoseContext(hipX: 0.5, tilt: 0, kneeL: 178, kneeR: 178));
      t += 33;
    }
    check('周期跳跃会计数', c.count > 5, '实际 ${c.count}');
  }

  // reset 后清空
  {
    final c = Counter();
    var t = 0.0;
    for (var i = 0; i < 120; i++) {
      final y = 0.55 - 0.05 * ((i % 12) < 6 ? 1.0 : 0.0);
      c.feed(y, 0.18, t,
          const PoseContext(hipX: 0.5, tilt: 0, kneeL: 178, kneeR: 178));
      t += 33;
    }
    final before = c.count;
    c.reset();
    check('reset 后计数归零', c.count == 0);
    check('reset 前确实计过数', before > 0, '实际 $before');
  }

  // 弯腰时暂停计数
  {
    final c = Counter();
    var t = 0.0;
    for (var i = 0; i < 120; i++) {
      final y = 0.55 - 0.05 * ((i % 12) < 6 ? 1.0 : 0.0);
      c.feed(y, 0.18, t,
          const PoseContext(hipX: 0.5, tilt: 60, kneeL: 178, kneeR: 178));
      t += 33;
    }
    check('弯腰（倾角 60°）时不计数', c.count == 0, '实际 ${c.count}');
  }
}

/* ---------------- 姿态判定 ---------------- */

void testPosture() {
  section('姿态判定（与 JS 逐案例一致）');
  final f = File('test/fixtures/posture_cases.json');
  if (!f.existsSync()) {
    check('姿态用例文件存在', false, f.path);
    return;
  }
  final cases = (_loadJson(f.path)['cases']) as List;

  var bad = 0;
  for (final c in cases) {
    final note = c['note'] as String;
    final lm = (c['lm'] as List).map((p) {
      final a = p as List;
      return Landmark(
        (a[0] as num).toDouble(),
        (a[1] as num).toDouble(),
        (a[2] as num).toDouble(),
        (a[3] as num).toDouble(),
      );
    }).toList();

    final p = postureOf(lm);
    final ok = (p.tilt - (c['tilt'] as num)).abs() <= 0.01 &&
        (p.kneeL - (c['kneeL'] as num)).abs() <= 0.01 &&
        (p.kneeR - (c['kneeR'] as num)).abs() <= 0.01 &&
        p.label == c['label'] &&
        p.standing == c['standing'];
    if (!ok) {
      bad++;
      if (bad <= 3) {
        print('   ✗ $note  期望 tilt=${c['tilt']} label=${c['label']}  '
            '实际 tilt=${p.tilt.toStringAsFixed(2)} label=${p.label}');
      }
    }
  }
  print('   ${cases.length} 组用例，不一致 $bad 组');
  check('姿态判定与 JS 一致', bad == 0, '$bad 组不一致');

  section('角度基本性质');
  const a = Landmark(0, 0, 0, 1);
  const b = Landmark(1, 0, 0, 1);
  const c = Landmark(1, 1, 0, 1);
  checkClose('直角 = 90°', angleAt(a, b, c), 90, 1e-6);

  const far = Landmark(2, 0, 0, 1); // a-b-far 三点共线，b 在中间
  checkClose('共线反向 = 180°', angleAt(a, b, far), 180, 1e-6);
  check('重合点兜底 180°', angleAt(b, b, c) == 180);

  final zero = List<Landmark>.generate(33, (_) => Landmark.zero);
  final p = postureOf(zero);
  check('NaN 场景不产生 NaN', p.tilt.isFinite && p.kneeL.isFinite);
}

/* ---------------- 会话编排 ---------------- */

/// 造一个站立的人：髋部 y = hipY，整体高 0.55
List<Landmark> skeleton(double hipY) {
  final lm = List<Landmark>.filled(33, const Landmark(0.5, 0.5, 0, 0.9));
  void put(int i, double x, double y, [double v = 0.9]) {
    lm[i] = Landmark(x, y, 0, v);
  }

  put(0, 0.5, hipY - 0.30); // 鼻子
  put(11, 0.44, hipY - 0.25); // 左肩
  put(12, 0.56, hipY - 0.25); // 右肩
  put(23, 0.45, hipY); // 左髋
  put(24, 0.55, hipY); // 右髋
  put(25, 0.45, hipY + 0.12); // 左膝
  put(26, 0.55, hipY + 0.12); // 右膝
  put(27, 0.45, hipY + 0.25); // 左踝
  put(28, 0.55, hipY + 0.25); // 右踝
  return lm;
}

List<PoseFrame> jumpingFrames({double seconds = 6, double fps = 30}) {
  final out = <PoseFrame>[];
  final n = (seconds * fps).round();
  for (var i = 0; i < n; i++) {
    final t = i * 1000 / fps;
    final phase = (i % (fps / 2.5).round()) / (fps / 2.5);
    final lift = phase < 0.5 ? 0.045 : 0.0;
    out.add(PoseFrame(t, skeleton(0.50 - lift)));
  }
  return out;
}

void testReplaySource() {
  section('日志回放数据源');
  final frames = jumpingFrames(seconds: 1);
  final src = ReplayPoseSource();
  src.loadFrames(frames);
  check('加载帧数正确', src.length == frames.length, '实际 ${src.length}');
  check('kind 为 replay', src.kind == SourceKind.replay);
}

Future<void> testSession() async {
  section('会话编排（取景 → 计数 → 结束）');

  final frames = jumpingFrames(seconds: 8);
  final src = ReplayPoseSource();
  src.loadFrames(frames);
  final sc = SessionController(
    source: src,
    durationSec: 4,
    countdownSec: 0,
    stableMs: 300,
  );

  final phases = <SessionPhase>[];
  final sub = sc.state.listen((s) {
    if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
  });

  await sc.start();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();

  check('经历取景阶段', phases.contains(SessionPhase.positioning), '实际 $phases');
  check('进入计数阶段', phases.contains(SessionPhase.running), '实际 $phases');
  check('最终结束', phases.contains(SessionPhase.finished), '实际 $phases');
  check('计数大于 0', sc.current.count > 0, '实际 ${sc.current.count}');
  check('结束后剩余时间为 0', sc.current.remainingMs == 0);
  await sc.dispose();
}

/// 手动驱动帧的数据源：测试暂停 / 提前结束时要能精确控制时间轴。
class _ManualSource implements PoseSource {
  final _c = StreamController<PoseFrame>.broadcast(sync: true);

  @override
  Stream<PoseFrame> get frames => _c.stream;

  @override
  SourceKind get kind => SourceKind.camera;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    if (!_c.isClosed) await _c.close();
  }

  @override
  Future<void> dispose() => stop();

  void emit(PoseFrame f) {
    if (!_c.isClosed) _c.add(f);
  }
}

Future<void> testSessionResult() async {
  section('会话结果（jumps / activeMs / valid）');

  // --- 回放：4s 会话，jumps 与计时完整 ---
  {
    final src = ReplayPoseSource();
    src.loadFrames(jumpingFrames(seconds: 6));
    final sc = SessionController(
      source: src,
      durationSec: 4,
      countdownSec: 0,
      stableMs: 0,
    );
    await sc.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final r = sc.result;
    check('结束时有结果', r != null);
    if (r != null) {
      check('结果 count 与状态一致', r.count == sc.current.count,
          '结果 ${r.count} / 状态 ${sc.current.count}');
      check('jumps 数 == count', r.jumps.length == r.count,
          'jumps ${r.jumps.length} / count ${r.count}');

      var sorted = true;
      for (var i = 1; i < r.jumps.length; i++) {
        if (r.jumps[i] < r.jumps[i - 1]) sorted = false;
      }
      check('jumps 升序', sorted, '${r.jumps}');
      check('jumps 落在活动时间内', r.jumps.every((j) => j >= 0 && j <= r.activeMs),
          '${r.jumps}');
      check('activeMs == 4000', r.activeMs == 4000, '实际 ${r.activeMs}');
      check(
          '回放未计入统计',
          !r.valid && r.invalidReasons.contains(SessionResult.reasonNotCamera),
          '${r.invalidReasons}');
    }
    await sc.dispose();
  }

  // --- 暂停：活动时长不含暂停段 ---
  {
    final src = _ManualSource();
    final sc = SessionController(
      source: src,
      durationSec: 10,
      countdownSec: 0,
      stableMs: 0,
    );
    await sc.start();
    final frames = jumpingFrames(seconds: 2);
    for (final f in frames) {
      src.emit(f);
    }
    check('进入计数阶段', sc.current.phase == SessionPhase.running,
        '实际 ${sc.current.phase}');
    final before = sc.current.activeMs;
    check('暂停前已计时', before > 1500, '实际 $before');

    sc.pause();
    check('暂停后 phase=paused', sc.current.phase == SessionPhase.paused);
    for (var i = 0; i < 21; i++) {
      src.emit(PoseFrame(2000 + i * 50.0, skeleton(0.5)));
    }
    check('暂停期间活动时长不变', sc.current.activeMs == before,
        '暂停前 $before / 现在 ${sc.current.activeMs}');

    sc.resume();
    src.emit(PoseFrame(4000, skeleton(0.5)));
    final after = sc.current.activeMs;
    check('恢复后只增加 1s（4000-3000）', (after - before - 1000).abs() <= 2,
        '暂停前 $before / 现在 $after');

    sc.finishEarly();
    final r = sc.result;
    check('提前结束有结果', r != null);
    if (r != null) {
      check(
          '提前结束未完成',
          !r.valid && r.invalidReasons.contains(SessionResult.reasonUnfinished),
          '${r.invalidReasons}');
      check('结果活动时长一致', r.activeMs == after, '结果 ${r.activeMs} / 状态 $after');
    }
    await sc.dispose();
  }

  // --- 自由跳：不自动结束，手动结束时算完成 ---
  {
    final src = _ManualSource();
    final sc = SessionController(
      source: src,
      durationSec: 0,
      countdownSec: 0,
      stableMs: 0,
    );
    await sc.start();
    for (final f in jumpingFrames(seconds: 3)) {
      src.emit(f);
    }
    check('自由跳不自动结束', sc.current.phase == SessionPhase.running,
        '实际 ${sc.current.phase}');
    check('实时活动时长递增', sc.current.activeMs > 1000, '实际 ${sc.current.activeMs}');
    check('实时 jumps 可见', sc.current.jumps.length == sc.current.count,
        'jumps ${sc.current.jumps.length} / count ${sc.current.count}');

    sc.finishEarly();
    final r = sc.result;
    check('自由跳提前结束有结果', r != null);
    if (r != null) {
      check('自由跳 plannedMs=0', r.plannedMs == 0, '实际 ${r.plannedMs}');
      check('自由跳算完成', r.completed);
      check('相机自由跳有效', r.valid, '${r.invalidReasons}');
      check('自由跳 activeMs 约 3s', (r.activeMs - 3000).abs() <= 60,
          '实际 ${r.activeMs}');
    }
    await sc.dispose();
  }

  // --- 0 跳：标无效，避免把「站着不动」算成活跃天 ---
  {
    final src = _ManualSource();
    final sc = SessionController(
      source: src,
      durationSec: 0,
      countdownSec: 0,
      stableMs: 0,
    );
    await sc.start();
    for (var t = 0.0; t <= 1000; t += 33.0) {
      src.emit(PoseFrame(t, skeleton(0.5)));
    }
    sc.finishEarly();
    final r = sc.result;
    check('0 跳会话有结果', r != null);
    if (r != null) {
      check(
          '0 跳标无效',
          !r.valid && r.invalidReasons.contains(SessionResult.reasonNoJumps),
          '${r.invalidReasons}');
    }
    await sc.dispose();
  }

  // --- 出框累计 > 3s：无效 ---
  {
    final src = _ManualSource();
    final sc = SessionController(
      source: src,
      durationSec: 10,
      countdownSec: 0,
      stableMs: 0,
    );
    await sc.start();
    for (var t = 0.0; t <= 1000; t += 33.0) {
      src.emit(PoseFrame(t, skeleton(0.5)));
    }
    for (var t = 1033.0; t <= 5000; t += 33.0) {
      src.emit(PoseFrame(t, const []));
    }
    src.emit(PoseFrame(5020, skeleton(0.5)));

    sc.finishEarly();
    final r = sc.result;
    check('出框会话有结果', r != null);
    if (r != null) {
      check(
          '出框累计超限无效',
          !r.valid && r.invalidReasons.contains(SessionResult.reasonOutOfFrame),
          '${r.invalidReasons}');
    }
    await sc.dispose();
  }
}

void testFramingRejectsBadPose() {
  section('取景判定');
  final far = PoseFrame(0, skeleton(0.5));
  // 把整体压缩，高度不足 0.30
  final small = PoseFrame(
    0,
    far.landmarks
        .map((p) => Landmark(
            0.5 + (p.x - 0.5) * 0.3, 0.5 + (p.y - 0.5) * 0.3, 0, p.visibility))
        .toList(),
  );
  check('太远被拒', !evaluateFramingForTest(small));

  final noFeet = PoseFrame(
    0,
    far.landmarks.asMap().entries.map((e) {
      final l = e.value;
      final v = (e.key == 27 || e.key == 28) ? 0.1 : l.visibility;
      return Landmark(l.x, l.y, l.z, v);
    }).toList(),
  );
  check('脚不可见被拒', !evaluateFramingForTest(noFeet));

  check('正常站立通过', evaluateFramingForTest(far));
}

/* ---------------- 入口 ---------------- */

Future<void> main() async {
  final sw = Stopwatch()..start();
  testGoldenVectors();
  testCounterBehaviour();
  testPosture();
  testReplaySource();
  await testSession();
  await testSessionResult();
  testFramingRejectsBadPose();

  print('\n${'=' * 50}');
  print('通过 $_pass  失败 $_fail  用时 ${sw.elapsedMilliseconds}ms');
  if (_fail > 0) {
    print('\n失败项:');
    for (final f in _failures) {
      print('  ✗ $f');
    }
    exit(1);
  }
  print('全部通过 ✅');
}
