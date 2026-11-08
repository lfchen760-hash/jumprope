import { FilesetResolver, PoseLandmarker } from './vendor/tasks-vision.mjs';
import { createCounter, DEFAULT_CFG } from './counter.mjs';
import { getModelAsset, humanSize } from './model-cache.mjs';

const $ = (id) => document.getElementById(id);
const video = $('video');
const overlay = $('overlay');
const octx = overlay.getContext('2d');
const timeline = $('timeline');
const tctx = timeline.getContext('2d');

const BONES = [
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24],
  [23, 25], [25, 27], [24, 26], [26, 28],
  [27, 29], [29, 31], [28, 30], [30, 32], [27, 31], [28, 32],
];

let poseVideo = null;   // 只初始化一次，分析与回看共用
let lmTs = 0;           // 喂给模型的时间戳，只需单调递增
let analyzing = false;

let samples = [];       // { t, lift, amp, counted }
let events = [];        // { t, i }
let gaps = [];          // { from, to, ms }
let duration = 0;
let effectiveFps = 0;
let currentT = 0;
let lastSeenT = -1;
let detectErr = '';
let wasmMs = 0;
let initMs = 0;

const fmt = (t) => `${t.toFixed(2)}s`;

function toast(msg) {
  const el = $('toast');
  el.textContent = msg;
  el.classList.add('on');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('on'), 1600);
}

/* ---------------- 模型 ---------------- */
async function initModels() {
  if (poseVideo) return;
  const t0 = performance.now();
  const ticker = setInterval(() => {
    const sec = ((performance.now() - t0) / 1000).toFixed(0);
    $('progress').textContent = `加载模型中… 已等待 ${sec}s（首次较慢，之后会走缓存）`;
  }, 300);
  $('progress').textContent = '加载模型中…';
  const modelUrl = await getModelAsset((got, total, fromCache) => {
    $('progress').textContent = fromCache
      ? '模型已从本地缓存加载 ✅'
      : `下载模型 ${humanSize(got)} / ${humanSize(total)}  (${Math.round(got / total * 100)}%)`;
  });

  const opts = (mode) => ({
    baseOptions: { modelAssetPath: modelUrl, delegate: 'GPU' },
    runningMode: mode,
    numPoses: 1,
    minPoseDetectionConfidence: 0.5,
    minPosePresenceConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });
  const tWasm = performance.now();
  const vision = await FilesetResolver.forVisionTasks('./wasm');
  wasmMs = performance.now() - tWasm;

  const tInit = performance.now();
  try {
    poseVideo = await PoseLandmarker.createFromOptions(vision, opts('VIDEO'));
  } catch (e) {
    poseVideo = await PoseLandmarker.createFromOptions(vision, {
      ...opts('VIDEO'),
      baseOptions: { modelAssetPath: modelUrl, delegate: 'CPU' },
    });
  }
  initMs = performance.now() - tInit;
  clearInterval(ticker);
  setTimeout(renderDiag, 300);
}

/* 统一入口：所有帧都用同一个模型实例，靠自增时间戳满足单调性 */
function detectOn(frame) {
  lmTs += 33;
  return poseVideo.detectForVideo(frame, lmTs);
}

function human(n) {
  if (!n) return '0 B';
  return n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.round(n / 1024) + ' KB';
}

function renderDiag() {
  const el = $('diag');
  if (!el) return;
  const rows = [];
  const res = performance.getEntriesByType('resource')
    .filter((r) => /wasm|models|vendor/.test(r.name));
  rows.push('资源                              传输      解码后    耗时     缓存');
  for (const r of res) {
    const name = r.name.split('/').pop().slice(0, 30).padEnd(30);
    const cached = r.transferSize === 0 ? '是' : '否';
    rows.push(
      `${name}  ${human(r.encodedBodySize).padStart(8)}  ${human(r.decodedBodySize).padStart(8)}  ` +
      `${(r.duration / 1000).toFixed(2)}s  ${cached}`
    );
  }
  rows.push('');
  rows.push(`wasm 加载：${(wasmMs / 1000).toFixed(2)}s`);
  rows.push(`模型初始化：${(initMs / 1000).toFixed(2)}s`);
  rows.push(`合计：${((wasmMs + initMs) / 1000).toFixed(2)}s`);
  el.textContent = rows.join('\n');
}

/* 页面一打开就在后台加载模型，把等待时间藏进"选视频"的过程 */
let modelReady = false;
setTimeout(async () => {
  try {
    await initModels();
    modelReady = true;
    const d = $('drop');
    if (d && d.style.display !== 'none') {
      const hint = d.querySelector('.hint');
      if (hint) hint.innerHTML = '建议用手机原片，60 秒左右 · mp4 / mov<br><span style="color:#6ee7a8">模型已就绪 ✅</span>';
    }
    if (!$('progress').textContent.includes('视频')) $('progress').textContent = '模型已就绪';
  } catch (e) {
    $('progress').textContent = '模型预加载失败，点开始时会重试';
  }
}, 200);

/* ---------------- 选文件 ---------------- */
const drop = $('drop');
const fileInput = $('file');

drop.addEventListener('click', () => fileInput.click());
drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('hover'); });
drop.addEventListener('dragleave', () => drop.classList.remove('hover'));
drop.addEventListener('drop', (e) => {
  e.preventDefault();
  drop.classList.remove('hover');
  if (e.dataTransfer.files[0]) loadFile(e.dataTransfer.files[0]);
});
fileInput.addEventListener('change', () => {
  if (fileInput.files[0]) loadFile(fileInput.files[0]);
});

let fileName = '';

function loadFile(file) {
  if (!file.type.startsWith('video/')) return toast('请选择视频文件');
  fileName = file.name;
  video.src = URL.createObjectURL(file);
  video.load();
  drop.style.display = 'none';
  $('main').classList.add('on');
  $('progress').textContent = '视频已载入，点「开始分析」';
  video.addEventListener('loadedmetadata', () => {
    duration = video.duration;
    $('sDur').textContent = `${duration.toFixed(1)}s`;
    sizeOverlay();
    drawTimeline();
  }, { once: true });
}

function sizeOverlay() {
  const w = video.videoWidth || 720;
  const h = video.videoHeight || 1280;
  if (overlay.width !== w || overlay.height !== h) {
    overlay.width = w;
    overlay.height = h;
  }
}

/* ---------------- 分析 ---------------- */
$('startBtn').addEventListener('click', startAnalysis);

async function startAnalysis() {
  if (analyzing) return;
  if (!video.src) return toast('先选择视频');

  analyzing = true;
  events = [];
  samples = [];
  gaps = [];
  lastSeenT = -1;
  $('startBtn').disabled = true;
  $('copyBtn').disabled = true;
  $('jsonBtn').disabled = true;
  $('table').hidden = true;
  $('report').hidden = true;

  try {
    await initModels();
  } catch (e) {
    $('progress').textContent = '模型加载失败：' + e.message;
    analyzing = false;
    $('startBtn').disabled = false;
    return;
  }

  const counter = createCounter();
  video.currentTime = 0;
  await seekTo(0);
  video.playbackRate = 1;

  let frames = 0;
  const t0 = performance.now();

  const step = (mediaTime) => {
    if (!analyzing) return;
    const t = typeof mediaTime === 'number' ? mediaTime : video.currentTime;
    if (t > lastSeenT) {
      lastSeenT = t;
      processFrame(t);
    }
    if (video.ended) { finish(); return; }
    scheduleNext();
  };

  function processFrame(mediaTimeSec) {
    if (video.readyState < 2) return;
    let res;
    try {
      res = detectOn(video);
    } catch (e) {
      detectErr = e && e.message ? e.message : String(e);
      $('progress').textContent = '检测出错：' + detectErr;
      return;
    }
    frames += 1;
    drawSkeleton(res);

    const poses = res.landmarks || [];
    if (poses.length) {
      const lm = poses[0];
      const hipY = (lm[23].y + lm[24].y) / 2;
      const shY = (lm[11].y + lm[12].y) / 2;
      const vis = Math.min(lm[23].visibility ?? 1, lm[24].visibility ?? 1);
      if (vis >= 0.45) {
        const torso = Math.max(Math.abs(hipY - shY), 0.03);
        const counted = counter.feed(hipY, torso, mediaTimeSec * 1000);
        samples.push({ t: mediaTimeSec, lift: counter.lift, amp: counter.amp, counted });
        if (counted) {
          events.push({ t: mediaTimeSec, i: events.length + 1 });
          $('sCount').textContent = String(counter.count);
        }
      }
    }
    const elapsed = (performance.now() - t0) / 1000;
    effectiveFps = frames / Math.max(elapsed, 0.001);
    $('progress').textContent =
      `分析中 ${mediaTimeSec.toFixed(1)}/${duration.toFixed(1)}s · ${effectiveFps.toFixed(0)}fps`;
  }

  function scheduleNext() {
    if (video.requestVideoFrameCallback) {
      video.requestVideoFrameCallback((_now, meta) => step(meta.mediaTime));
    } else {
      requestAnimationFrame(() => step(video.currentTime));
    }
  }

  video.play().catch((e) => {
    $('progress').textContent = '无法播放：' + e.message;
    analyzing = false;
    $('startBtn').disabled = false;
  });
  step();
}

function seekTo(t) {
  return new Promise((res) => {
    if (Math.abs(video.currentTime - t) < 0.001) return res();
    const done = () => { video.removeEventListener('seeked', done); res(); };
    video.addEventListener('seeked', done);
    video.currentTime = t;
  });
}

/* ---------------- 收尾统计 ---------------- */
function finish() {
  analyzing = false;
  $('startBtn').disabled = false;
  $('startBtn').textContent = '重新分析';
  $('copyBtn').disabled = false;
  $('jsonBtn').disabled = false;

  const count = events.length;
  $('sCount').textContent = String(count);
  $('sDur').textContent = `${duration.toFixed(1)}s`;
  $('sRate').textContent = duration > 0 ? `${Math.round(count / (duration / 60))} /分` : '—';
  let prog = `完成：${samples.length} 帧采样 · 实际 ${effectiveFps.toFixed(0)}fps`;
  if (effectiveFps < 12) {
    prog += '  ⚠️ 采样率偏低，结果可能与实时运行有偏差';
  }
  $('progress').textContent = prog;

  // 间隔
  const iv = [];
  for (let i = 1; i < events.length; i++) iv.push(events[i].t - events[i - 1].t);
  const sorted = [...iv].sort((a, b) => a - b);
  const med = sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
  $('sMed').textContent = med ? `${(med * 1000).toFixed(0)}ms` : '—';

  // 疑似漏计：间隔明显偏长
  gaps = [];
  for (let i = 1; i < events.length; i++) {
    const dt = events[i].t - events[i - 1].t;
    if (med > 0 && dt > med * 1.7) {
      gaps.push({ from: events[i - 1].t, to: events[i].t, ms: Math.round(dt * 1000) });
    }
  }
  // 开头一段
  if (events.length && events[0].t > Math.max(1.5, med * 2.5)) {
    gaps.unshift({ from: 0, to: events[0].t, ms: Math.round(events[0].t * 1000) });
  }
  gaps.sort((a, b) => a.from - b.from);

  $('sGap').textContent = String(gaps.length);
  $('sGap').className = 'v ' + (gaps.length ? 'warn' : 'good');

  drawTimeline();
  buildTable(med);
  buildReport(med);
  setTimeout(renderDiag, 100);
  $('table').hidden = false;
  $('report').hidden = false;
}

/* ---------------- 时间轴 ---------------- */
function drawTimeline() {
  const dpr = Math.min(devicePixelRatio || 1, 2);
  const w = timeline.clientWidth || 600;
  const h = 130;
  if (timeline.width !== Math.round(w * dpr) || timeline.height !== Math.round(h * dpr)) {
    timeline.width = Math.round(w * dpr);
    timeline.height = Math.round(h * dpr);
    tctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  tctx.clearRect(0, 0, w, h);
  if (!duration) return;

  const padT = 16, padB = 18;
  const plotH = h - padT - padB;
  const mid = padT + plotH / 2;

  // 疑似漏计区间
  for (const g of gaps) {
    const x1 = (g.from / duration) * w;
    const x2 = (g.to / duration) * w;
    tctx.fillStyle = 'rgba(255,80,80,.16)';
    tctx.fillRect(x1, padT, Math.max(2, x2 - x1), plotH);
  }

  // 波形
  if (samples.length > 1) {
    let peak = 0.05;
    for (const s of samples) peak = Math.max(peak, Math.abs(s.lift));
    const scale = (plotH * 0.42) / peak;
    tctx.beginPath();
    for (let i = 0; i < samples.length; i++) {
      const x = (samples[i].t / duration) * w;
      const y = mid - samples[i].lift * scale;
      i ? tctx.lineTo(x, y) : tctx.moveTo(x, y);
    }
    tctx.strokeStyle = '#5ac8ff';
    tctx.lineWidth = 1.2;
    tctx.stroke();
  }

  // 计数点
  tctx.fillStyle = '#ffd166';
  for (const e of events) {
    const x = (e.t / duration) * w;
    tctx.beginPath();
    tctx.arc(x, padT + 4, 2.6, 0, Math.PI * 2);
    tctx.fill();
  }

  // 播放头
  const px = (currentT / duration) * w;
  tctx.strokeStyle = 'rgba(255,255,255,.65)';
  tctx.lineWidth = 1;
  tctx.beginPath();
  tctx.moveTo(px, 0);
  tctx.lineTo(px, h - padB);
  tctx.stroke();

  // 时间刻度
  tctx.fillStyle = 'rgba(200,215,255,.45)';
  tctx.font = '10px ui-monospace, monospace';
  const stepSec = duration > 40 ? 10 : 5;
  for (let s = 0; s <= duration; s += stepSec) {
    const x = (s / duration) * w;
    tctx.fillText(`${s}s`, x + 2, h - 5);
  }
}

timeline.addEventListener('click', async (e) => {
  if (analyzing || !duration) return;
  const rect = timeline.getBoundingClientRect();
  const t = ((e.clientX - rect.left) / rect.width) * duration;
  await jumpTo(t);
});
timeline.addEventListener('mousemove', (e) => {
  if (!duration) return;
  const rect = timeline.getBoundingClientRect();
  showAt(((e.clientX - rect.left) / rect.width) * duration);
});

let lastShown = -1;
function showAt(t) {
  if (Math.abs(t - lastShown) < 0.01) return;
  lastShown = t;
  currentT = t;
  $('sNow').textContent = fmt(t);
  const near = nearestSample(t);
  $('sSig').textContent = near
    ? `${near.lift >= 0 ? '+' : ''}${near.lift.toFixed(3)} / ${near.amp.toFixed(3)}`
    : '—';
  drawTimeline();
}

function nearestSample(t) {
  if (!samples.length) return null;
  let lo = 0, hi = samples.length - 1;
  while (lo < hi) {
    const m = (lo + hi) >> 1;
    if (samples[m].t < t) lo = m + 1; else hi = m;
  }
  const a = samples[Math.max(0, lo - 1)];
  const b = samples[lo];
  return Math.abs(a.t - t) < Math.abs(b.t - t) ? a : b;
}

async function jumpTo(t) {
  await jumpAndDraw(t);
}

async function jumpAndDraw(t) {
  await seekTo(Math.max(0, Math.min(duration - 0.02, t)));
  currentT = video.currentTime;
  showAt(currentT);
  await drawFrameSkeleton();
}

async function drawFrameSkeleton() {
  try {
    if (!poseVideo) await initModels();
    drawSkeleton(detectOn(video));
  } catch (e) { /* 忽略 */ }
}

/* ---------------- 画骨架 ---------------- */
function drawSkeleton(res) {
  sizeOverlay();
  octx.clearRect(0, 0, overlay.width, overlay.height);
  const poses = (res && res.landmarks) || [];
  if (!poses.length) return;
  const lm = poses[0];
  const W = overlay.width, H = overlay.height;

  octx.lineWidth = Math.max(3, W / 240);
  octx.strokeStyle = 'rgba(90,200,255,.9)';
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
  for (let i = 0; i < lm.length; i++) {
    const p = lm[i];
    if ((p.visibility ?? 1) < 0.3) continue;
    const big = i === 23 || i === 24;
    octx.beginPath();
    octx.arc(p.x * W, p.y * H, big ? 10 : 5, 0, Math.PI * 2);
    octx.fillStyle = big ? '#ffd166' : 'rgba(255,255,255,.9)';
    octx.fill();
  }
}

/* ---------------- 表格 ---------------- */
function buildTable(med) {
  const tbody = $('table').querySelector('tbody');
  tbody.innerHTML = '';
  events.forEach((e, idx) => {
    const prev = idx > 0 ? events[idx - 1].t : null;
    const dt = prev != null ? (e.t - prev) * 1000 : null;
    const isGap = prev != null && med > 0 && (e.t - prev) > med * 1.7;

    const tr = document.createElement('tr');
    if (isGap) tr.className = 'bad-row';
    tr.innerHTML =
      `<td class="num">${e.i}</td>` +
      `<td class="num">${fmt(e.t)}</td>` +
      `<td class="num">${dt == null ? '—' : dt.toFixed(0) + 'ms'}</td>` +
      `<td class="${isGap ? 'bad' : ''}">${isGap ? '偏长·疑似漏计' : '正常'}</td>` +
      `<td><button class="ghost" style="padding:4px 10px;font-size:12px">跳到</button></td>`;
    tr.addEventListener('click', () => jumpAndDraw(e.t));
    tbody.appendChild(tr);
  });
}

/* ---------------- 报告 ---------------- */
function buildReport(med) {
  const lines = [];
  lines.push(`文件：${fileName}`);
  lines.push(`时长：${duration.toFixed(1)}s`);
  lines.push(`计数：${events.length}`);
  lines.push(`平均频率：${Math.round(events.length / (duration / 60))} 次/分`);
  lines.push(`中位间隔：${(med * 1000).toFixed(0)}ms`);
  lines.push(`实际采样：${effectiveFps.toFixed(0)}fps`);
  lines.push('');
  if (!gaps.length) {
    lines.push('没有发现明显偏长的间隔。');
  } else {
    lines.push(`疑似漏计 ${gaps.length} 段（间隔 > 中位数的 1.7 倍）：`);
    for (const g of gaps) {
      lines.push(`  ${g.from.toFixed(2)}s → ${g.to.toFixed(2)}s   间隔 ${g.ms}ms`);
    }
    lines.push('');
    lines.push('提示：点时间轴跳到这些区间，看画面里人在做什么（起跳太小 / 出画 / 停顿）。');
  }
  $('reportText').textContent = lines.join('\n');
}

$('copyBtn').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('reportText').textContent);
    toast('已复制，直接粘贴给我');
  } catch (e) {
    const r = document.createRange();
    r.selectNodeContents($('reportText'));
    const sel = getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
    toast('已选中，手动复制即可');
  }
});

$('jsonBtn').addEventListener('click', () => {
  const payload = {
    file: fileName,
    duration,
    fpsSampled: effectiveFps,
    config: DEFAULT_CFG,
    count: events.length,
    events: events.map((e) => Number(e.t.toFixed(3))),
    gaps: gaps.map((g) => ({ from: +g.from.toFixed(3), to: +g.to.toFixed(3), ms: g.ms })),
    samples: samples.map((s) => ({
      t: +s.t.toFixed(3),
      lift: +s.lift.toFixed(4),
      amp: +s.amp.toFixed(4),
      c: s.counted ? 1 : 0,
    })),
  };
  const blob = new Blob([JSON.stringify(payload, null, 0)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = fileName.replace(/\.[^.]+$/, '') + '.analysis.json';
  a.click();
  toast('已导出');
});

video.addEventListener('ended', () => { if (analyzing) finish(); });

video.addEventListener('timeupdate', () => {
  if (!analyzing) {
    currentT = video.currentTime;
    $('sNow').textContent = fmt(currentT);
    drawTimeline();
  }
});

addEventListener('resize', () => { drawTimeline(); });
