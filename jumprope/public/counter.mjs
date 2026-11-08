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
  WIN: 60,          // 振幅统计窗口（帧）
  LAG: 10,          // 滞后帧数
  FAST_WIN: 24,     // 快速振幅窗口：停跳后用它快速关闸
  X_WIN: 36,        // 横向位移统计窗口（帧，约 1.2 秒）
  MOVE_X_MAX: 0.25, // 髋部横向移动超过画面宽度 25% → 判定为走动，暂停计数
  TILT_MAX: 35,     // 躯干倾角超过 35° → 判定为弯腰，暂停计数
  KNEE_MIN: 100,    // 双膝都小于 100° → 判定为深蹲，暂停计数
};

export function createCounter(cfg = {}) {
  const C = { ...DEFAULT_CFG, ...cfg };

  let baseHipY = null;
  let smooth = 0;
  let hist = [];
  let wave = [];

  let dir = 1;          // 1 = 上升段，-1 = 下降段
  let ext = 0;          // 当前方向的极值
  let extT = 0;         // 极值出现的时间
  let primed = false;   // 是否已用第一帧初始化
  let lastCountT = -Infinity;
  let count = 0;

  let amp = 0;
  let prom = 0;
  let xBuf = [];
  let gate = 'ok';          // ok | move | bend

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
    xBuf = [];
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

    hist.push(smooth);
    if (hist.length > C.WIN) hist.shift();

    // ---- 动作闸门：走动 / 弯腰 / 深蹲 时暂停计数（调整绳子和站位） ----
    if (ctx && typeof ctx.hipX === 'number') {
      xBuf.push(ctx.hipX);
      if (xBuf.length > C.X_WIN) xBuf.shift();
    }
    let moving = false;
    if (xBuf.length >= 12) {
      const xs = [...xBuf].sort((a, b) => a - b);
      const xr = xs[Math.floor(xs.length * 0.9)] - xs[Math.floor(xs.length * 0.1)];
      if (xr > C.MOVE_X_MAX) moving = true;
    }
    const bending = !!ctx && (
      (ctx.tilt ?? 0) > C.TILT_MAX ||
      ((ctx.kneeL ?? 180) < C.KNEE_MIN && (ctx.kneeR ?? 180) < C.KNEE_MIN)
    );
    gate = moving ? 'move' : bending ? 'bend' : 'ok';

    if (hist.length < 20 || gate !== 'ok') {
      // 调整动作期间重置波形状态，恢复跳跃后重新开始跟踪
      dir = 1;
      ext = smooth;
      extT = now;
      primed = false;
      return false;
    }

    // 振幅：滞后窗口的 p10/p90，对偏置和毛刺都免疫
    const win = hist.slice(0, hist.length - C.LAG).sort((a, b) => a - b);
    const n = win.length;
    const p10 = win[Math.floor(n * 0.10)];
    const p90 = win[Math.floor(n * 0.90)];
    amp = (p90 - p10) / 2;
    prom = amp * C.PROM_K;

    // 没在跳：保持方向为上升，等待重新起跳
    // 快速振幅：只看最近一小段。停跳后 ~0.8 秒内就会掉到门限以下，
    // 避免慢窗口里残留的大振幅继续放行若干个假峰。
    const fastN = Math.min(C.FAST_WIN, hist.length);
    const fast = hist.slice(hist.length - fastN).sort((a, b) => a - b);
    const ampFast = (fast[Math.floor(fastN * 0.9)] - fast[Math.floor(fastN * 0.1)]) / 2;

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
