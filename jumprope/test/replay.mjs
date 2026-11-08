#!/usr/bin/env node
/**
 * 用「和线上完全相同的计数代码」(public/counter.mjs) 回放关键点序列。
 *
 * 用法:
 *   node test/replay.mjs landmarks.json [真实次数]
 *   node test/replay.mjs landmarks.json 42 --sweep     # 参数扫描
 */
import { readFileSync } from 'node:fs';
import { createCounter, DEFAULT_CFG } from '../public/counter.mjs';
import { postureOf } from '../public/posture.mjs';

const toLm = (arr) => arr.map(([x, y, z, v]) => ({ x, y, z, visibility: v }));

const [, , input, expectedArg, ...flags] = process.argv;
if (!input) {
  console.log('用法: node test/replay.mjs landmarks.json [真实次数] [--sweep]');
  process.exit(1);
}

const data = JSON.parse(readFileSync(input, 'utf8'));
const expected = expectedArg && !expectedArg.startsWith('--') ? Number(expectedArg) : null;
const sweep = flags.includes('--sweep') || process.argv.includes('--sweep');

/** 从一帧关键点算出计数器需要的量 */
function frameToSignal(fr) {
  if (!fr.lm) return null;
  const lm = fr.lm;
  const hipY = (lm[23][1] + lm[24][1]) / 2;
  const shY = (lm[11][1] + lm[12][1]) / 2;
  const vis = Math.min(lm[23][3] ?? 1, lm[24][3] ?? 1);
  if (vis < 0.45) return null;
  const torso = Math.max(Math.abs(hipY - shY), 0.03);
  const post = postureOf(toLm(lm));
  const hipX = (lm[23][0] + lm[24][0]) / 2;
  return { hipY, torso, t: fr.t, ctx: { hipX, tilt: post.tilt, kneeL: post.kneeL, kneeR: post.kneeR } };
}

function replay(cfg) {
  const counter = createCounter(cfg);
  const events = [];
  let valid = 0;

  for (const fr of data.frames) {
    const s = frameToSignal(fr);
    if (!s) continue;
    valid += 1;
    if (counter.feed(s.hipY, s.torso, s.t, s.ctx)) events.push(s.t);
  }

  return { count: counter.count, events, valid, counter };
}

function stats(events) {
  if (events.length < 2) return { intervals: [], mean: 0, cv: 0 };
  const iv = [];
  for (let i = 1; i < events.length; i++) iv.push(events[i] - events[i - 1]);
  const mean = iv.reduce((a, b) => a + b, 0) / iv.length;
  const sd = Math.sqrt(iv.reduce((a, b) => a + (b - mean) ** 2, 0) / iv.length);
  return { intervals: iv, mean, cv: mean ? sd / mean : 0 };
}

const durationSec = data.frames.length / (data.fps || 30);

console.log('=== 视频信息 ===');
console.log(`分辨率 ${data.width}x${data.height}  帧率 ${Number(data.fps).toFixed(2)}  帧数 ${data.frames.length}  时长 ${durationSec.toFixed(1)}s`);

const base = replay({});
console.log('\n=== 当前线上参数 ===');
console.log(`检出帧 ${base.valid}/${data.frames.length}`);
console.log(`计数 ${base.count}`);
if (expected) {
  const err = ((base.count - expected) / expected) * 100;
  console.log(`真实 ${expected}   误差 ${err.toFixed(1)}%`);
}
console.log(`频率 ${(base.count / (durationSec / 60)).toFixed(0)} 次/分`);

const st = stats(base.events);
if (st.intervals.length) {
  console.log(`\n计数间隔: 平均 ${st.mean.toFixed(0)}ms  变异系数 ${st.cv.toFixed(2)}`);
  const buckets = {};
  for (const iv of st.intervals) {
    const k = Math.round(iv / 100) * 100;
    buckets[k] = (buckets[k] || 0) + 1;
  }
  console.log('间隔分布:', Object.entries(buckets).sort((a, b) => a[0] - b[0])
    .map(([k, v]) => `${k}ms×${v}`).join('  '));
}

if (sweep) {
  console.log('\n=== 参数扫描（以你给的真实次数为目标）===');
  const grid = [];
  for (const AMP_MIN of [0.015, 0.025, 0.035, 0.045])
    for (const UP_K of [0.3, 0.4, 0.5])
      for (const MIN_DT of [150, 180, 220])
        grid.push({ AMP_MIN, UP_K, DOWN_K: UP_K, MIN_DT });

  const rows = grid.map((cfg) => {
    const r = replay(cfg);
    const err = expected ? Math.abs(r.count - expected) / expected : 0;
    return { cfg, count: r.count, err };
  }).sort((a, b) => a.err - b.err || Math.abs(a.count - base.count) - Math.abs(b.count - base.count));

  for (const r of rows.slice(0, 8)) {
    console.log(
      `AMP_MIN=${String(r.cfg.AMP_MIN).padEnd(5)} UP_K=${r.cfg.UP_K} MIN_DT=${String(r.cfg.MIN_DT).padEnd(3)}` +
      `  -> 计数 ${String(r.count).padStart(4)}` + (expected ? `  误差 ${(r.err * 100).toFixed(1)}%` : '')
    );
  }
}

console.log('\n默认参数:', JSON.stringify(DEFAULT_CFG));
