import { FilesetResolver, PoseLandmarker } from './vendor/tasks-vision.mjs';
import { createCounter } from './counter.mjs';
import { getModelAsset } from './model-cache.mjs';
import { postureOf, angleAt } from './posture.mjs';

/* ============================ 配置 ============================ */
const CFG = {
  MIN_DT: 180,        // 两次计数最小间隔(ms) -> 上限约 330 次/分
  SMOOTH: 0.70,       // 平滑系数
  BASE_ALPHA: 0.03,   // 慢速基线跟随速度
  AMP_MIN: 0.035,     // 振幅下限：低于此值视为没在跳
  UP_K: 0.40,         // 起飞线 = 中心 + 振幅 × 0.40
  DOWN_K: 0.40,       // 复位线 = 中心 - 振幅 × 0.40
  WIN: 60,            // 统计窗口（帧）
  LAG: 10,            // 滞后帧数，阈值不被当前帧带跑
  REARM_MS: 700,      // 未复位时强制复位
  CALIB_MS: 1000,     // 起跳前准备时长
  VIS_MIN: 0.45,      // 髋部关键点最低可见度
};

/* 33 个关键点里我们关心的骨架连线 */
const BONES = [
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24],
  [23, 25], [25, 27], [24, 26], [26, 28],
  [27, 29], [29, 31], [28, 30], [30, 32], [27, 31], [28, 32],
];

/* ============================ DOM ============================ */
const $ = (id) => document.getElementById(id);
const video = $('cam');
const overlay = $('overlay');
const octx = overlay.getContext('2d');
const waveCv = $('wave');
const wctx = waveCv.getContext('2d');
const elCount = $('count');
const elTimer = $('timer');
const elRate = $('rate');
const elStatus = $('status');
const elCover = $('cover');
const elErr = $('err');
const elGuide = $('guide');
const elDebug = $('debug');
const camWrap = $('camWrap');

/* 推理用降采样画布：预览保持高清，喂给模型的图缩小以提升帧率 */
const work = document.createElement('canvas');
const workCtx = work.getContext('2d', { alpha: false });
const LONG_SIDE = 640;

function grabFrame() {
  const vw = video.videoWidth || 640;
  const vh = video.videoHeight || 480;
  let W, H;
  if (vw >= vh) { W = LONG_SIDE; H = Math.max(1, Math.round((LONG_SIDE * vh) / vw)); }
  else { H = LONG_SIDE; W = Math.max(1, Math.round((LONG_SIDE * vw) / vh)); }
  if (work.width !== W || work.height !== H) {
    work.width = W;
    work.height = H;
  }
  workCtx.drawImage(video, 0, 0, W, H);
  return work;
}

/* ---------------- 模型预热 ---------------- */
let modelPromise = null;
let modelReady = false;

function setModelHint(text, cls) {
  const el = $('modelHint');
  if (!el) return;
  el.textContent = text || '';
  el.className = cls || '';
}

function ensureModel() {
  if (modelPromise) return modelPromise;
  modelReady = false;
  setModelHint('正在加载模型…', 'loading');
  modelPromise = initModel()
    .then(() => {
      modelReady = true;
      setModelHint('模型已就绪 ✅', 'ok');
      if (phase === 'idle') setStatus('模型已就绪，点开始吧');
      return true;
    })
    .catch((e) => {
      modelPromise = null;
      setModelHint('模型加载失败，点击开始重试', 'bad');
      throw e;
    });
  return modelPromise;
}

/* 页面一打开就开始加载，不等用户点开始 */
setTimeout(() => { ensureModel().catch(() => {}); }, 250);

/* 计数核心：与离线回放测试共用同一份实现 */
const counter = createCounter();

/* ============================ 状态 ============================ */
let landmarker = null;
let stream = null;
let facing = 'user';
let running = false;       // 采集循环是否在跑
let phase = 'idle';        // idle | positioning | countdown | running | paused | finished
let count = 0;
let armed = true;
let airAt = 0;

let lastAmp = 0;
let lastH = 0;
let lastError = '';
let lastPosture = null;
let durationSec = 60;        // 单次时长
let sessionEndAt = 0;        // 结束时刻
let pausedRemain = 0;        // 暂停时剩余的毫秒
let goodSince = 0;           // 取景合格起始时刻
let lastProblem = '';        // 上次播报的取景问题
let lastProblemAt = 0;
let cdTimer = null;
let lastTickSec = -1;

let startAt = 0;
let waveBuf = [];
let lastPoseAt = 0;
let lastVideoTime = -1;
let hasPose = false;
let fps = 0;
let frameCount = 0;
let fpsMark = 0;
let lastBoxH = 0;
let lastLift = 0;
let lastDbg = 0;

/* ============================ 工具 ============================ */
function setStatus(t, warn = false) {
  if (elStatus.textContent === t && elStatus.classList.contains('warn') === warn) return;
  elStatus.textContent = t;
  elStatus.classList.toggle('warn', warn);
}

/* ---------- 声音层 1：WebAudio 蜂鸣（零延迟，必定可用） ---------- */
let audioCtx = null;
let voiceReady = true;      // 浏览器语音合成是否可用
let speaking = false;

async function unlockAudio() {
  if (!audioCtx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    audioCtx = new AC();
  }
  if (audioCtx.state === 'suspended') {
    try { await audioCtx.resume(); } catch (_) { /* 忽略 */ }
  }
  // iOS 需要播一小段静音才算真正解锁
  try {
    const buf = audioCtx.createBuffer(1, 1, 22050);
    const src = audioCtx.createBufferSource();
    src.buffer = buf;
    src.connect(audioCtx.destination);
    src.start(0);
  } catch (_) { /* 忽略 */ }
}

function beep(high = false) {
  if (!audioCtx) return;
  const t = audioCtx.currentTime;
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();
  osc.type = 'sine';
  osc.frequency.setValueAtTime(high ? 1340 : 990, t);
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(0.24, t + 0.006);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.085);
  osc.connect(gain).connect(audioCtx.destination);
  osc.start(t);
  osc.stop(t + 0.1);
}


const VOICE_MODES = [
  { label: '语音·关', every: 0 },
  { label: '语音·10', every: 10 },
  { label: '语音·5', every: 5 },
  { label: '语音·每个', every: 1 },
];
let voiceMode = 1;

function speak(text, { urgent = false, force = false } = {}) {
  if (!force && voiceMode === 0) return;
  if (!voiceReady) return;
  if (!('speechSynthesis' in window)) { voiceReady = false; return; }

  try {
    // 「每个」模式下不排队，直接打断，保证跟得上
    if (urgent && speechSynthesis.speaking) speechSynthesis.cancel();
    if (!urgent && speechSynthesis.speaking) return;

    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'zh-CN';
    u.rate = 1.4;
    u.pitch = 1.08;
    u.volume = 1;
    u.onstart = () => { speaking = true; };
    u.onend = () => { speaking = false; };
    u.onerror = () => { speaking = false; };
    speechSynthesis.speak(u);
    speaking = true;
  } catch (_) {
    voiceReady = false;   // 该浏览器不支持，安静降级为蜂鸣
  }
}

/* ============================ 模型 ============================ */
async function initModel() {
  setStatus('正在加载模型…');
  const vision = await FilesetResolver.forVisionTasks('./wasm');

  const modelUrl = await getModelAsset((got, total, fromCache) => {
    if (fromCache) setModelHint('模型已从本地缓存加载 ✅', 'loading');
    else setModelHint(`下载模型 ${(got / 1048576).toFixed(1)}MB / ${(total / 1048576).toFixed(1)}MB`, 'loading');
  });
  const opts = (delegate) => ({
    baseOptions: {
      modelAssetPath: modelUrl,
      delegate,
    },
    runningMode: 'VIDEO',
    numPoses: 2,
    minPoseDetectionConfidence: 0.5,
    minPosePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });

  try {
    landmarker = await PoseLandmarker.createFromOptions(vision, opts('GPU'));
  } catch (e) {
    console.warn('GPU delegate 失败，回退 CPU', e);
    landmarker = await PoseLandmarker.createFromOptions(vision, opts('CPU'));
  }
}

/* ============================ 摄像头 ============================ */
async function startCamera() {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: {
      facingMode: facing,
      width: { ideal: 1280 },
      height: { ideal: 720 },
      frameRate: { ideal: 30, max: 30 },
    },
  });
  video.srcObject = stream;
  await video.play();
  await new Promise((res) => {
    if (video.videoWidth) return res();
    video.onloadedmetadata = () => res();
  });
  camWrap.classList.toggle('mirrored', facing === 'user');
}

/* ============================ 计数核心 ============================ */
/* 进入取景阶段：检查站位 → 合格后倒数 */
function beginPositioning() {
  clearTimeout(cdTimer);
  count = 0;
  armed = true;
  counter.reset();
  waveBuf = counter.wave;
  lastAmp = 0;
  lastError = '';
  startAt = 0;
  goodSince = 0;
  lastProblem = '';
  lastTickSec = -1;
  phase = 'positioning';

  elCount.textContent = '0';
  elTimer.textContent = fmtDuration(durationSec);
  elRate.textContent = '0';
  $('result').classList.remove('on');
  $('countdown').classList.remove('on');
  $('toggleBtn').disabled = true;
  $('toggleBtn').textContent = '暂停';
  setStatus('请站好，让我看清全身');
}

function fmtDuration(sec) {
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
}

/* 3-2-1 倒数 */
function startCountdown() {
  if (phase === 'countdown') return;
  phase = 'countdown';
  goodSince = 0;
  guidance('', 0);
  setStatus('准备…');

  const box = $('countdown');
  const num = $('cdNum');
  box.classList.add('on');

  let n = 3;
  const tick = () => {
    num.textContent = String(n);
    num.style.animation = 'none';
    void num.offsetWidth;      // 强制重排以重放动画
    num.style.animation = '';
    beep(n === 1);
    speak(String(n), { force: true, urgent: true });

    if (n > 1) {
      n -= 1;
      cdTimer = setTimeout(tick, 1000);
    } else {
      cdTimer = setTimeout(() => {
        box.classList.remove('on');
        startSession();
      }, 1000);
    }
  };
  tick();
}

/* 正式开始计时 */
function startSession() {
  phase = 'running';
  counter.reset();
  waveBuf = counter.wave;
  count = 0;
  elCount.textContent = '0';
  startAt = performance.now();
  sessionEndAt = startAt + durationSec * 1000;
  lastTickSec = -1;
  $('toggleBtn').disabled = false;
  $('toggleBtn').textContent = '暂停';
  beep(true);
  speak('开始', { force: true });
  setStatus('跳吧！');
}

/* 时间到 */
function finishSession() {
  if (phase === 'finished' || phase === 'idle') return;
  phase = 'finished';
  clearTimeout(cdTimer);
  $('countdown').classList.remove('on');
  $('poseHint').classList.remove('on');

  const mins = startAt ? (performance.now() - startAt) / 60000 : 0;
  const rate = mins > 0.2 ? Math.round(count / mins) : 0;

  elTimer.textContent = '0:00';
  $('rNum').textContent = String(count);
  $('rSub').textContent = `用时 ${durationSec} 秒 · 平均 ${rate} 次/分`;
  $('result').classList.add('on');
  $('toggleBtn').disabled = true;
  setStatus('已结束');
  beep(true);
  speak(`时间到，本次跳了 ${count} 个`, { force: true });
}

function addCount() {
  count += 1;
  elCount.textContent = String(count);

  // 每一次都有声音：蜂鸣打底，整十音调更高
  beep(count % 10 === 0);

  // 语音报数（按模式）
  const every = VOICE_MODES[voiceMode].every;
  if (every > 0 && count % every === 0) {
    speak(String(count), { urgent: every === 1 });
  }
}

function bbox(lm) {
  let x0 = 1, y0 = 1, x1 = 0, y1 = 0;
  for (const p of lm) {
    if ((p.visibility ?? 1) < 0.3) continue;
    if (p.x < x0) x0 = p.x;
    if (p.y < y0) y0 = p.y;
    if (p.x > x1) x1 = p.x;
    if (p.y > y1) y1 = p.y;
  }
  if (x1 < x0 || y1 < y0) return { w: 0, h: 0, area: 0 };
  const w = x1 - x0, h = y1 - y0;
  return { w, h, area: w * h };
}

/* 取景是否合格：返回 {ok, msg} */
function evalFraming(post, box, poseCount) {
  if (poseCount > 1) return { ok: false, msg: '画面里只能有一个人' };
  if (box.h > 0.96) return { ok: false, msg: '请退后一点，要拍到全身' };
  if (box.h < 0.30) return { ok: false, msg: '请靠近一点' };
  if (!post || !post.fullBody) return { ok: false, msg: '请把脚也放进画面' };
  if (!post.standing) return { ok: false, msg: '请站直一点' };
  return { ok: true, msg: '' };
}

/* 取景提示：变化时立刻播报，持续不合规时每 5 秒提醒一次 */
function guidance(msg, now) {
  const el = $('poseHint');
  if (!msg) {
    el.classList.remove('on');
    lastProblem = '';
    return;
  }
  el.textContent = msg;
  el.classList.add('on');
  if (msg !== lastProblem) {
    lastProblem = msg;
    lastProblemAt = now;
    speak(msg, { force: true });
  } else if (now - lastProblemAt > 5000) {
    lastProblemAt = now;
    speak(msg, { force: true });
  }
}

function processPose(res, now) {
  const poses = res.landmarks || [];
  if (!poses.length) {
    if (now - lastPoseAt > 800) {
      setStatus('没有检测到人，请让全身进入画面', true);
      armed = true;
      if (phase === 'positioning') guidance('请站到画面中间', now);
    }
    return;
  }
  lastPoseAt = now;

  // 多人时取面积最大的那个
  let lm = poses[0];
  if (poses.length > 1) {
    lm = poses.reduce((a, b) => (bbox(b).area > bbox(a).area ? b : a));
  }

  const box = bbox(lm);
  lastBoxH = box.h;

  const post = postureOf(lm);
  lastPosture = post;

  const hipY = (lm[23].y + lm[24].y) / 2;
  const shY = (lm[11].y + lm[12].y) / 2;
  const vis = Math.min(lm[23].visibility ?? 1, lm[24].visibility ?? 1);
  const torso = Math.max(Math.abs(hipY - shY), 0.03);

  if (vis < CFG.VIS_MIN) {
    setStatus('请正对镜头，让上半身清晰可见', true);
    return;
  }

  // 跳绳过程中的轻提示（不打断计数）
  if (phase === 'running') {
    const g = counter.gate;
    if (g === 'move') setStatus('检测到走动，暂停计数', true);
    else if (g === 'bend') setStatus('检测到弯腰，暂停计数', true);
    else if (box.h > 0.98) setStatus('有点太近，可以退半步', true);
    else if (!post.fullBody) setStatus('脚快出画了，往后退一点', true);
    else setStatus('跳吧！');
  }

  // ===== 取景阶段：不合格就语音提示，合格后进入倒数 =====
  if (phase === 'positioning') {
    const f = evalFraming(post, box, poses.length);
    guidance(f.msg, now);
    if (f.ok) {
      if (!goodSince) goodSince = now;
      setStatus('就位了，准备开始…');
      if (now - goodSince >= 500) startCountdown();
    } else {
      goodSince = 0;
      setStatus(f.msg, true);
    }
    return;
  }

  if (phase === 'countdown' || phase === 'finished') return;

  if (phase !== 'running') return;

  // 计数器内部完成：慢速基线 → 平滑 → 分位数中心/振幅 → 迟滞上升沿
  const hipX = (lm[23].x + lm[24].x) / 2;
  const counted = counter.feed(hipY, torso, now, {
    hipX,
    tilt: post.tilt,
    kneeL: post.kneeL,
    kneeR: post.kneeR,
  });

  lastLift = counter.lift;
  lastAmp = counter.amp;
  lastH = counter.prom;
  armed = counter.rising;
  waveBuf = counter.wave;

  if (counted) addCount();
}

/* ============================ 绘制 ============================ */
function sizeCanvas() {
  const w = video.videoWidth || 1280;
  const h = video.videoHeight || 720;
  if (overlay.width !== w || overlay.height !== h) {
    overlay.width = w;
    overlay.height = h;
  }
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const cw = waveCv.clientWidth, ch = waveCv.clientHeight;
  if (waveCv.width !== Math.round(cw * dpr) || waveCv.height !== Math.round(ch * dpr)) {
    waveCv.width = Math.round(cw * dpr);
    waveCv.height = Math.round(ch * dpr);
    wctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
}

function drawSkeleton(res) {
  sizeCanvas();
  octx.clearRect(0, 0, overlay.width, overlay.height);
  const poses = res.landmarks || [];
  if (!poses.length) return;

  let lm = poses[0];
  if (poses.length > 1) lm = poses.reduce((a, b) => (bbox(b).area > bbox(a).area ? b : a));

  const W = overlay.width, H = overlay.height;

  // 连线
  octx.lineWidth = Math.max(3, W / 260);
  octx.strokeStyle = 'rgba(90,200,255,.85)';
  octx.lineCap = 'round';
  for (const [a, b] of BONES) {
    const p = lm[a], q = lm[b];
    if (!p || !q) continue;
    if ((p.visibility ?? 1) < 0.3 || (q.visibility ?? 1) < 0.3) continue;
    octx.beginPath();
    octx.moveTo(p.x * W, p.y * H);
    octx.lineTo(q.x * W, q.y * H);
    octx.stroke();
  }

  // 关键点（髋部高亮）
  for (let i = 0; i < lm.length; i++) {
    const p = lm[i];
    if ((p.visibility ?? 1) < 0.3) continue;
    const big = i === 23 || i === 24;
    octx.beginPath();
    octx.arc(p.x * W, p.y * H, big ? 9 : 4.5, 0, Math.PI * 2);
    octx.fillStyle = big ? '#ffd166' : 'rgba(255,255,255,.9)';
    octx.fill();
  }
}

function drawWave() {
  const w = waveCv.clientWidth, h = waveCv.clientHeight;
  wctx.clearRect(0, 0, w, h);
  if (waveBuf.length < 2) return;

  const mid = h / 2;
  // 按缓冲区里真实出现过的最大幅度缩放，保证永远画得下
  let peak = 0.05;
  for (let i = 0; i < waveBuf.length; i++) {
    const a = Math.abs(waveBuf[i]);
    if (a > peak) peak = a;
  }
  const scale = (h * 0.40) / peak;
  const toY = (v) => {
    const y = mid - v * scale;
    return y < 1 ? 1 : y > h - 1 ? h - 1 : y;
  };

  const center = 0;

  // 自适应参考线：±振幅
  if (lastAmp > 0) {
    const upT = lastAmp;
    const downT = -lastAmp;

    wctx.setLineDash([4, 4]);
    wctx.lineWidth = 1;
    wctx.strokeStyle = 'rgba(255,209,102,.7)';
    wctx.beginPath();
    wctx.moveTo(0, toY(upT));
    wctx.lineTo(w, toY(upT));
    wctx.stroke();

    wctx.strokeStyle = 'rgba(120,200,255,.6)';
    wctx.beginPath();
    wctx.moveTo(0, toY(downT));
    wctx.lineTo(w, toY(downT));
    wctx.stroke();
    wctx.setLineDash([]);
  }

  // 中线
  wctx.strokeStyle = 'rgba(255,255,255,.12)';
  wctx.beginPath();
  wctx.moveTo(0, toY(center));
  wctx.lineTo(w, toY(center));
  wctx.stroke();

  // 曲线
  const n = waveBuf.length;
  wctx.beginPath();
  for (let i = 0; i < n; i++) {
    const x = (i / Math.max(1, n - 1)) * w;
    const y = toY(waveBuf[i]);
    i ? wctx.lineTo(x, y) : wctx.moveTo(x, y);
  }
  wctx.strokeStyle = '#5ac8ff';
  wctx.lineWidth = 2;
  wctx.shadowColor = 'rgba(90,200,255,.6)';
  wctx.shadowBlur = 8;
  wctx.stroke();
  wctx.shadowBlur = 0;
}

/* ============================ 主循环 ============================ */
function loop() {
  requestAnimationFrame(loop);
  if (!running || !landmarker || video.readyState < 2) return;
  if (video.currentTime === lastVideoTime) return;
  lastVideoTime = video.currentTime;

  const now = performance.now();
  let res;
  try {
    res = landmarker.detectForVideo(grabFrame(), now);
  } catch (e) {
    console.warn('detect 失败', e);
    return;
  }

  frameCount += 1;
  if (now - fpsMark > 1000) {
    fps = (frameCount * 1000) / (now - fpsMark);
    frameCount = 0;
    fpsMark = now;
  }

  hasPose = (res.landmarks || []).length > 0;
  elGuide.classList.toggle('on', !hasPose);
  camWrap.classList.toggle('dim', !hasPose);

  drawSkeleton(res);
  drawWave();

  if (now - lastDbg > 250) {
    lastDbg = now;
    elDebug.textContent =
      `fps    ${fps.toFixed(1)}\n` +
      `人体   ${hasPose ? '有' : '无'}\n` +
      `身高   ${lastBoxH.toFixed(2)}\n` +
      `lift   ${lastLift >= 0 ? '+' : ''}${lastLift.toFixed(3)}\n` +
      `振幅   ${lastAmp.toFixed(3)}  阈${lastH.toFixed(3)}\n` +
      `姿态   ${lastPosture ? lastPosture.label + ' 倾' + lastPosture.tilt.toFixed(0) + '° 膝' + lastPosture.knee.toFixed(0) + '°' : '-'}\n` +
      `状态   ${phase}` + (lastError ? `\nerr    ${lastError}` : '');
  }

  if (phase === 'paused') return;
  try {
    processPose(res, now);
  } catch (e) {
    lastError = (e && e.message) ? e.message : String(e);
    console.error(e);
  }
}

/* ============================ 计时 ============================ */
setInterval(() => {
  if (phase !== 'running') return;
  const now = performance.now();
  const left = Math.max(0, sessionEndAt - now);
  const sec = Math.ceil(left / 1000);

  elTimer.textContent = fmtDuration(Math.min(sec, durationSec));

  // 最后 5 秒滴答提醒
  if (sec <= 5 && sec > 0 && sec !== lastTickSec) {
    lastTickSec = sec;
    beep(false);
  }

  const mins = (now - startAt) / 60000;
  elRate.textContent = mins > 0.05 ? String(Math.round(count / mins)) : '0';

  if (left <= 0) finishSession();
}, 200);

/* ============================ 交互 ============================ */
$('startBtn').addEventListener('click', async () => {
  const btn = $('startBtn');
  btn.disabled = true;
  btn.textContent = '启动中…';
  elErr.textContent = '';

  try {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error(
        'bad-context:当前环境不能调用摄像头。\n' +
        'secureContext=' + window.isSecureContext +
        '\n请确认地址是以 https:// 开头，并换用 Chrome / Safari / 系统自带浏览器。'
      );
    }

    try { await unlockAudio(); } catch (_) { /* 没有声音也不影响计数 */ }

    if (!modelReady) {
      btn.textContent = '准备模型…';
      await ensureModel();
    }

    btn.textContent = '开摄像头…';
    await startCamera();

    elCover.classList.add('hidden');
    running = true;
    beginPositioning();
    $('voiceBtn').textContent = VOICE_MODES[voiceMode].label;
    beep(false);
    speak('请站好，让我看清全身', { force: true });
    loop();
  } catch (e) {
    console.error(e);
    const name = e && e.name ? e.name : '';
    let msg = e && e.message ? e.message : String(e);

    if (name === 'NotAllowedError') {
      msg = '摄像头权限被拒绝了。\n请在浏览器的网站设置里允许摄像头，然后刷新页面。';
    } else if (name === 'NotFoundError') {
      msg = '没有找到摄像头设备。';
    } else if (name === 'NotReadableError') {
      msg = '摄像头被其他 App 占用了，请先关掉相机/视频通话类应用。';
    } else if (msg.startsWith('bad-context:')) {
      msg = msg.slice('bad-context:'.length);
    }

    elErr.textContent = '启动失败：\n' + msg;
    btn.disabled = false;
    btn.textContent = '重试';
  }
});

$('toggleBtn').addEventListener('click', () => {
  const btn = $('toggleBtn');
  if (phase === 'running') {
    phase = 'paused';
    pausedRemain = Math.max(0, sessionEndAt - performance.now());
    btn.textContent = '继续';
    setStatus('已暂停');
    speak(`已暂停，现在${count}个`, { force: true });
  } else if (phase === 'paused') {
    phase = 'running';
    sessionEndAt = performance.now() + pausedRemain;
    btn.textContent = '暂停';
    setStatus('跳吧！');
    beep(true);
    speak('继续', { force: true });
  }
});

$('resetBtn').addEventListener('click', () => {
  beginPositioning();
});

$('voiceBtn').addEventListener('click', async () => {
  voiceMode = (voiceMode + 1) % VOICE_MODES.length;
  $('voiceBtn').textContent = VOICE_MODES[voiceMode].label;
  await unlockAudio();
  if (voiceMode === 0) {
    if ('speechSynthesis' in window) speechSynthesis.cancel();
    beep(false);
  } else {
    speak(String(count || 3), { force: true });   // 点一下就能听到效果
  }
});

/* 时长选择 */
document.querySelectorAll('#durs button').forEach((b) => {
  b.addEventListener('click', () => {
    document.querySelectorAll('#durs button').forEach((x) => x.classList.remove('on'));
    b.classList.add('on');
    durationSec = Number(b.dataset.sec) || 60;
    elTimer.textContent = fmtDuration(durationSec);
    beep(false);
  });
});

/* 再跳一次 */
$('againBtn').addEventListener('click', () => {
  beginPositioning();
});

$('soundTest').addEventListener('click', async () => {
  await unlockAudio();
  beep(false);
  setTimeout(() => beep(true), 130);
  speak('声音正常，一二三', { force: true });
  const hint = $('soundHint');
  if (hint) {
    hint.textContent = voiceReady
      ? '已播放：蜂鸣声 + 语音。听不到就调大音量，或关掉手机静音开关。'
      : '蜂鸣已播放，但这个浏览器不支持语音合成。';
  }
});

$('flipBtn').addEventListener('click', async () => {
  facing = facing === 'user' ? 'environment' : 'user';
  try {
    await startCamera();
    beginPositioning();
  } catch (e) {
    console.warn(e);
    setStatus('切换摄像头失败', true);
  }
});

/* 防止误触缩放 */
document.addEventListener('gesturestart', (e) => e.preventDefault());
