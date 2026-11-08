/**
 * 跳绳计数核心 —— 纯逻辑，无 DOM 依赖。
 * 浏览器（app.js）和离线回放测试（test/replay.mjs）共用这一份实现，
 * 保证"测试通过"就等于"线上通过"。
 *
 * 算法：ZigZag 峰值确认
 *   信号上升时跟踪极大值，从极大值回落超过 prom 时确认这是一个峰并计数。
 *   相比"阈值迟滞状态机"，它不要求信号在固定电平间往返，
 *   因而对直流偏置、幅度变化、暂停后恢复都更稳健。
 *
 * 实测（3 段真实视频，真实 145/168/184 次）：
 *   ZigZag  145 / 162 / 170   （误差 0% / -3.6% / -7.6%）
 *   旧状态机 81 / 144 / 156   （误差 -44% / -14% / -15%）
 */

export const DEFAULT_CFG = {
  MIN_DT: 150,      // 两次计数最小间隔(ms) -> 上限约 400 次/分
  SMOOTH: 0.60,     // 一阶低通平滑系数
  BASE_ALPHA: 0.06, // 慢速基线跟随速度（去直流）
  AMP_MIN: 0.055,   // 振幅下限：约等于髋部 3cm 峰峰值。低于此值视为没在跳
  PROM_K: 0.45,     // 峰确认回落量 = 振幅 × PROM_K
  WIN_SEC: 2.00,    // 振幅统计窗口（秒）
  LAG_SEC: 0.333,   // 滞后时长（秒）：阈值用"过去"的数据算
  FAST_SEC: 0.7667, // 快速振幅窗口（秒）：停跳后快速关闸（=24帧@30fps）
  X_SEC: 1.20,      // 横向位移统计窗口（秒）
  MIN_SAMPLES: 20,  // 窗口内最少样本数（统计稳定性下限）
  MOVE_X_MAX: 0.25, // 髋部横向移动超过画面宽度 25% → 判定为走动，暂停计数
  TILT_MAX: 35,     // 躯干倾角超过 35° → 判定为弯腰，暂停计数
  KNEE_MIN: 100,    // 双膝都小于 100° → 判定为深蹲，暂停计数
};

export function createCounter(cfg = {}) {
  const C = { ...DEFAULT_CFG, ...cfg };

  let baseHipY = null;
  let smooth = 0;
  let hist = [];        // [{ t, v }]
  let wave = [];

  let dir = 1;          // 1 = 上升段，-1 = 下降段
  let ext = 0;          // 当前方向的极值
  let extT = 0;         // 极值出现的时间
  let primed = false;   // 是否已用第一帧初始化
  let lastCountT = -Infinity;
  let count = 0;

  let amp = 0;
  let prom = 0;
  let xHist = [];       // [{ t, v }]
  let gate = 'ok';          // ok | move | bend

  /** 取时间窗内的值并升序排序。lagSec>0 时排除最近 lagSec 的数据。 */
  function windowValues(arr, now, winSec, lagSec = 0) {
    const lo = now - winSec * 1000;
    const hi = lagSec > 0 ? now - lagSec * 1000 : Infinity;
    const out = [];
    for (let i = arr.length - 1; i >= 0; i--) {
      const e = arr[i];
      if (e.t < lo) break;
      if (e.t <= hi) out.push(e.v);
    }
    return out.sort((a, b) => a - b);
  }

  function reset() {
    baseHipY = null;
    smooth = 0;
    hist = [];
    wave = [];
    dir = 1;
    ext = 0;
    extT = 0;
    primed = false;
    lastCountT = -Infinity;
    count = 0;
    amp = 0;
    prom = 0;
    xHist = [];
    gate = 'ok';
  }

  /**
   * 送入一帧姿态。
   * @param {number} hipY  髋部中点的归一化 y
   * @param {number} torso 躯干长度（肩中点到髋中点），用于尺度归一化
   * @param {number} now   时间戳（ms，单调递增）
   * @param {object} ctx   可选：{ hipX, tilt, kneeL, kneeR } 用于区分"跳跃"和"走动/弯腰"
   * @returns {boolean}    本帧是否确认了一个新峰（即计了一次）
   */
  function feed(hipY, torso, now, ctx) {
    if (baseHipY === null) baseHipY = hipY;
    else baseHipY += (hipY - baseHipY) * C.BASE_ALPHA;

    const lift = (baseHipY - hipY) / torso;
    smooth = smooth * (1 - C.SMOOTH) + lift * C.SMOOTH;

    wave.push(smooth);
    if (wave.length > 260) wave.shift();

    hist.push({ t: now, v: smooth });
    // 只保留最长时间窗的数据，避免无限增长
    const maxKeep = now - C.WIN_SEC * 1000 * 3;
    while (hist.length && hist[0].t < maxKeep) hist.shift();

    // ---- 动作闸门：走动 / 弯腰 / 深蹲 时暂停计数（调整绳子和站位） ----
    if (ctx && typeof ctx.hipX === 'number') {
      xHist.push({ t: now, v: ctx.hipX });
      const xKeep = now - C.X_SEC * 1000 * 3;
      while (xHist.length && xHist[0].t < xKeep) xHist.shift();
    }
    let moving = false;
    const xs = windowValues(xHist, now, C.X_SEC);
    if (xs.length >= 12) {
      const xr = xs[Math.floor(xs.length * 0.9)] - xs[Math.floor(xs.length * 0.1)];
      if (xr > C.MOVE_X_MAX) moving = true;
    }
    const bending = !!ctx && (
      (ctx.tilt ?? 0) > C.TILT_MAX ||
      ((ctx.kneeL ?? 180) < C.KNEE_MIN && (ctx.kneeR ?? 180) < C.KNEE_MIN)
    );
    gate = moving ? 'move' : bending ? 'bend' : 'ok';

    const win = windowValues(hist, now, C.WIN_SEC, C.LAG_SEC);

    if (hist.length < C.MIN_SAMPLES || gate !== 'ok' || win.length < 8) {
      // 调整动作期间重置波形状态，恢复跳跃后重新开始跟踪
      dir = 1;
      ext = smooth;
      extT = now;
      primed = false;
      return false;
    }

    // 振幅：滞后窗口的 p10/p90，对偏置和毛刺都免疫
    const n = win.length;
    const p10 = win[Math.floor(n * 0.10)];
    const p90 = win[Math.floor(n * 0.90)];
    amp = (p90 - p10) / 2;
    prom = amp * C.PROM_K;

    // 没在跳：保持方向为上升，等待重新起跳
    // 快速振幅：只看最近一小段。停跳后 ~0.8 秒内就会掉到门限以下，
    // 避免慢窗口里残留的大振幅继续放行若干个假峰。
    const fast = windowValues(hist, now, C.FAST_SEC);
    const fastN = fast.length;
    const ampFast = fastN >= 2
      ? (fast[Math.floor(fastN * 0.9)] - fast[Math.floor(fastN * 0.1)]) / 2
      : 0;

    if (ampFast < C.AMP_MIN) {
      dir = 1;
      ext = smooth;
      extT = now;
      return false;
    }

    if (!primed) {
      ext = smooth;
      extT = now;
      primed = true;
      return false;
    }

    if (dir >= 0) {
      if (smooth > ext) {
        ext = smooth;
        extT = now;
      } else if (ext - smooth > prom) {
        // 从极大值回落超过 prom → 确认刚才那个峰
        let counted = false;
        if (extT - lastCountT > C.MIN_DT) {
          lastCountT = extT;
          count += 1;
          counted = true;
        }
        dir = -1;
        ext = smooth;
        extT = now;
        return counted;
      }
    } else {
      if (smooth < ext) {
        ext = smooth;
        extT = now;
      } else if (smooth - ext > prom) {
        // 从极小值回升超过 prom → 转为上升段
        dir = 1;
        ext = smooth;
        extT = now;
      }
    }

    return false;
  }

  return {
    reset,
    feed,
    get count() { return count; },
    get amp() { return amp; },
    get prom() { return prom; },
    get peak() { return ext; },
    get rising() { return dir >= 0; },
    get gate() { return gate; },
    get lift() { return smooth; },
    get wave() { return wave; },
  };
}
