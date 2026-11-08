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
  final int win;            // 振幅统计窗口（帧）
  final int lag;            // 滞后帧数
  final int fastWin;        // 快速振幅窗口
  final int xWin;           // 横向位移窗口
  final double moveXMax;    // 横向位移门限
  final double tiltMax;     // 躯干倾角门限（度）
  final double kneeMin;     // 膝角门限（度）

  const CounterConfig({
    this.minDt = 150,
    this.smooth = 0.60,
    this.baseAlpha = 0.06,
    this.ampMin = 0.055,
    this.promK = 0.45,
    this.win = 60,
    this.lag = 10,
    this.fastWin = 24,
    this.xWin = 36,
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
    int? win,
    int? lag,
    int? fastWin,
    int? xWin,
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
      win: win ?? this.win,
      lag: lag ?? this.lag,
      fastWin: fastWin ?? this.fastWin,
      xWin: xWin ?? this.xWin,
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
  final List<double> _hist = [];
  final List<double> _wave = [];

  int _dir = 1;
  double _ext = 0;
  double _extT = 0;
  bool _primed = false;
  double _lastCountT = double.negativeInfinity;
  int _count = 0;

  double _amp = 0;
  double _prom = 0;
  final List<double> _xBuf = [];
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
    _xBuf.clear();
    _gate = 'ok';
  }

  static List<double> _sorted(List<double> src) {
    final copy = List<double>.from(src);
    copy.sort();
    return copy;
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

    _hist.add(_smooth);
    if (_hist.length > c.win) _hist.removeAt(0);

    // ---- 动作闸门 ----
    final hipX = ctx?.hipX;
    if (hipX != null) {
      _xBuf.add(hipX);
      if (_xBuf.length > c.xWin) _xBuf.removeAt(0);
    }
    var moving = false;
    if (_xBuf.length >= 12) {
      final xs = _sorted(_xBuf);
      final xr = xs[((xs.length * 0.9).floor())] -
          xs[((xs.length * 0.1).floor())];
      if (xr > c.moveXMax) moving = true;
    }
    final tilt = ctx?.tilt ?? 0;
    final kneeL = ctx?.kneeL ?? 180;
    final kneeR = ctx?.kneeR ?? 180;
    final bending = tilt > c.tiltMax || (kneeL < c.kneeMin && kneeR < c.kneeMin);
    _gate = moving ? 'move' : (bending ? 'bend' : 'ok');

    if (_hist.length < 20 || _gate != 'ok') {
      _dir = 1;
      _ext = _smooth;
      _extT = nowMs;
      _primed = false;
      return false;
    }

    // ---- 振幅：滞后窗口 p10/p90 ----
    final win = _sorted(_hist.sublist(0, _hist.length - c.lag));
    final n = win.length;
    final p10 = win[(n * 0.10).floor()];
    final p90 = win[(n * 0.90).floor()];
    _amp = (p90 - p10) / 2;
    _prom = _amp * c.promK;

    // ---- 快速振幅 ----
    final fastN = c.fastWin < _hist.length ? c.fastWin : _hist.length;
    final fast = _sorted(_hist.sublist(_hist.length - fastN));
    final ampFast =
        (fast[(fastN * 0.9).floor()] - fast[(fastN * 0.1).floor()]) / 2;

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
