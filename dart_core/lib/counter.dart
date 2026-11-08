/// 跳绳计数核心 —— `public/counter.mjs` 的 Dart 移植版。
///
/// 逐行对应，行为必须完全一致：
/// 同一份黄金向量，JS 与 Dart 的输出必须相等。
///
/// 纯 Dart，不依赖 Flutter，可以直接 `dart test` / `dart run`。
library;

class CounterConfig {
  final int minDt;          // 两次计数最小间隔(ms)
  final double smooth;      // 一阶低通平滑系数
  final double baseAlpha;   // 慢速基线跟随速度
  final double ampMin;      // 振幅下限
  final double promK;       // 峰确认回落比例
  final double winSec;      // 振幅统计窗口（秒）
  final double lagSec;      // 滞后时长（秒）
  final double fastSec;     // 快速振幅窗口（秒）
  final double xSec;        // 横向位移窗口（秒）
  final int minSamples;     // 窗口内最少样本数
  final double moveXMax;    // 横向位移门限
  final double tiltMax;     // 躯干倾角门限（度）
  final double kneeMin;     // 膝角门限（度）

  const CounterConfig({
    this.minDt = 150,
    this.smooth = 0.60,
    this.baseAlpha = 0.06,
    this.ampMin = 0.055,
    this.promK = 0.45,
    this.winSec = 2.00,
    this.lagSec = 0.333,
    this.fastSec = 0.7667,
    this.xSec = 1.20,
    this.minSamples = 20,
    this.moveXMax = 0.25,
    this.tiltMax = 35,
    this.kneeMin = 100,
  });

  CounterConfig copyWith({
    int? minDt,
    double? smooth,
    double? baseAlpha,
    double? ampMin,
    double? promK,
    double? winSec,
    double? lagSec,
    double? fastSec,
    double? xSec,
    int? minSamples,
    double? moveXMax,
    double? tiltMax,
    double? kneeMin,
  }) {
    return CounterConfig(
      minDt: minDt ?? this.minDt,
      smooth: smooth ?? this.smooth,
      baseAlpha: baseAlpha ?? this.baseAlpha,
      ampMin: ampMin ?? this.ampMin,
      promK: promK ?? this.promK,
      winSec: winSec ?? this.winSec,
      lagSec: lagSec ?? this.lagSec,
      fastSec: fastSec ?? this.fastSec,
      xSec: xSec ?? this.xSec,
      minSamples: minSamples ?? this.minSamples,
      moveXMax: moveXMax ?? this.moveXMax,
      tiltMax: tiltMax ?? this.tiltMax,
      kneeMin: kneeMin ?? this.kneeMin,
    );
  }
}

/// 每帧的姿态上下文，用于区分「跳跃」和「走动 / 弯腰」。
class PoseContext {
  final double? hipX;
  final double? tilt;
  final double? kneeL;
  final double? kneeR;

  const PoseContext({this.hipX, this.tilt, this.kneeL, this.kneeR});
}

class Counter {
  final CounterConfig c;

  Counter([CounterConfig? cfg]) : c = cfg ?? const CounterConfig();

  double? _baseHipY;
  double _smooth = 0;
  final List<(double, double)> _hist = [];   // (t, v)
  final List<double> _wave = [];

  int _dir = 1;
  double _ext = 0;
  double _extT = 0;
  bool _primed = false;
  double _lastCountT = double.negativeInfinity;
  int _count = 0;

  double _amp = 0;
  double _prom = 0;
  final List<(double, double)> _xHist = [];  // (t, v)
  String _gate = 'ok';

  int get count => _count;
  double get amp => _amp;
  double get prom => _prom;
  double get peak => _ext;
  bool get rising => _dir >= 0;
  String get gate => _gate;
  double get lift => _smooth;
  List<double> get wave => _wave;

  void reset() {
    _baseHipY = null;
    _smooth = 0;
    _hist.clear();
    _wave.clear();
    _dir = 1;
    _ext = 0;
    _extT = 0;
    _primed = false;
    _lastCountT = double.negativeInfinity;
    _count = 0;
    _amp = 0;
    _prom = 0;
    _xHist.clear();
    _gate = 'ok';
  }

  /// 取时间窗内的值并升序排序。lagSec>0 时排除最近 lagSec 的数据。
  static List<double> _windowValues(
      List<(double, double)> arr, double now, double winSec,
      [double lagSec = 0]) {
    final lo = now - winSec * 1000;
    final hi = lagSec > 0 ? now - lagSec * 1000 : double.infinity;
    final out = <double>[];
    for (var i = arr.length - 1; i >= 0; i--) {
      final e = arr[i];
      if (e.$1 < lo) break;
      if (e.$1 <= hi) out.add(e.$2);
    }
    out.sort();
    return out;
  }

  /// 送入一帧姿态，返回本帧是否确认了一个新峰。
  bool feed(double hipY, double torso, double nowMs, [PoseContext? ctx]) {
    final base = _baseHipY;
    if (base == null) {
      _baseHipY = hipY;
    } else {
      _baseHipY = base + (hipY - base) * c.baseAlpha;
    }

    final lift = (_baseHipY! - hipY) / torso;
    _smooth = _smooth * (1 - c.smooth) + lift * c.smooth;

    _wave.add(_smooth);
    if (_wave.length > 260) _wave.removeAt(0);

    _hist.add((nowMs, _smooth));
    final histKeep = nowMs - c.winSec * 1000 * 3;
    while (_hist.isNotEmpty && _hist.first.$1 < histKeep) {
      _hist.removeAt(0);
    }

    // ---- 动作闸门 ----
    final hipX = ctx?.hipX;
    if (hipX != null) {
      _xHist.add((nowMs, hipX));
      final xKeep = nowMs - c.xSec * 1000 * 3;
      while (_xHist.isNotEmpty && _xHist.first.$1 < xKeep) {
        _xHist.removeAt(0);
      }
    }
    var moving = false;
    final xs = _windowValues(_xHist, nowMs, c.xSec);
    if (xs.length >= 12) {
      final xr = xs[((xs.length * 0.9).floor())] -
          xs[((xs.length * 0.1).floor())];
      if (xr > c.moveXMax) moving = true;
    }
    final tilt = ctx?.tilt ?? 0;
    final kneeL = ctx?.kneeL ?? 180;
    final kneeR = ctx?.kneeR ?? 180;
    final bending = tilt > c.tiltMax || (kneeL < c.kneeMin && kneeR < c.kneeMin);
    _gate = moving ? 'move' : (bending ? 'bend' : 'ok');

    final win = _windowValues(_hist, nowMs, c.winSec, c.lagSec);

    if (_hist.length < c.minSamples || _gate != 'ok' || win.length < 8) {
      _dir = 1;
      _ext = _smooth;
      _extT = nowMs;
      _primed = false;
      return false;
    }

    // ---- 振幅：滞后窗口 p10/p90 ----
    final n = win.length;
    final p10 = win[(n * 0.10).floor()];
    final p90 = win[(n * 0.90).floor()];
    _amp = (p90 - p10) / 2;
    _prom = _amp * c.promK;

    // ---- 快速振幅 ----
    final fast = _windowValues(_hist, nowMs, c.fastSec);
    final fastN = fast.length;
    final ampFast = fastN >= 2
        ? (fast[(fastN * 0.9).floor()] - fast[(fastN * 0.1).floor()]) / 2
        : 0.0;

    if (ampFast < c.ampMin) {
      _dir = 1;
      _ext = _smooth;
      _extT = nowMs;
      return false;
    }

    if (!_primed) {
      _ext = _smooth;
      _extT = nowMs;
      _primed = true;
      return false;
    }

    if (_dir >= 0) {
      if (_smooth > _ext) {
        _ext = _smooth;
        _extT = nowMs;
      } else if (_ext - _smooth > _prom) {
        var counted = false;
        if (_extT - _lastCountT > c.minDt) {
          _lastCountT = _extT;
          _count += 1;
          counted = true;
        }
        _dir = -1;
        _ext = _smooth;
        _extT = nowMs;
        return counted;
      }
    } else {
      if (_smooth < _ext) {
        _ext = _smooth;
        _extT = nowMs;
      } else if (_smooth - _ext > _prom) {
        _dir = 1;
        _ext = _smooth;
        _extT = nowMs;
      }
    }

    return false;
  }
}
