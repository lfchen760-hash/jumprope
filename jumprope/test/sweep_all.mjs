#!/usr/bin/env node
/** 在三个真实视频上联合扫描参数，找出总误差最小的配置 */
import { readFileSync } from 'node:fs';
import { createCounter } from '../public/counter.mjs';

const FILES = [
  { path: '/tmp/lm_145个断3次.json', expected: 145, name: '145' },
  { path: '/tmp/lm_168个断0次.json', expected: 168, name: '168' },
  { path: '/tmp/lm_184个断2次.json', expected: 184, name: '184' },
];

const DATA = FILES.map((f) => {
  const j = JSON.parse(readFileSync(f.path, 'utf8'));
  const sig = [];
  for (const fr of j.frames) {
    if (!fr.lm) continue;
    const lm = fr.lm;
    const hipY = (lm[23][1] + lm[24][1]) / 2;
    const shY = (lm[11][1] + lm[12][1]) / 2;
    const vis = Math.min(lm[23][3] ?? 1, lm[24][3] ?? 1);
    if (vis < 0.45) continue;
    sig.push({ hipY, torso: Math.max(Math.abs(hipY - shY), 0.03), t: fr.t });
  }
  return { ...f, sig };
});

function count(cfg, d) {
  const c = createCounter(cfg);
  for (const s of d.sig) c.feed(s.hipY, s.torso, s.t);
  return c.count;
}

function score(cfg) {
  let total = 0;
  const counts = [];
  for (const d of DATA) {
    const n = count(cfg, d);
    counts.push(n);
    total += Math.abs(n - d.expected) / d.expected;
  }
  return { total, counts };
}

const results = [];
const AMPs = [0.010, 0.015, 0.020, 0.025, 0.030, 0.035];
const Ks = [0.20, 0.25, 0.30, 0.35, 0.40, 0.50];
const MINDTs = [120, 150, 180];
const SMOOTHs = [0.5, 0.65, 0.8];
const REARMs = [400, 700];

for (const AMP_MIN of AMPs)
  for (const UP_K of Ks)
    for (const DOWN_K of [UP_K])
      for (const MIN_DT of MINDTs)
        for (const SMOOTH of SMOOTHs)
          for (const REARM_MS of REARMs) {
            const cfg = { AMP_MIN, UP_K, DOWN_K, MIN_DT, SMOOTH, REARM_MS };
            const { total, counts } = score(cfg);
            results.push({ cfg, total, counts });
          }

results.sort((a, b) => a.total - b.total || a.counts[2] - b.counts[2]);

console.log('=== 最优 12 组（目标 145 / 168 / 184）===');
for (const r of results.slice(0, 12)) {
  console.log(
    `err=${(r.total * 100 / 3).toFixed(1).padStart(5)}%  ` +
    `AMP=${r.cfg.AMP_MIN} UP=${r.cfg.UP_K} DT=${String(r.cfg.MIN_DT).padStart(3)} ` +
    `SM=${r.cfg.SMOOTH} RE=${r.cfg.REARM_MS}  ->  ${r.counts.join(' / ')}`
  );
}

console.log('\n=== 当前线上配置 ===');
const cur = { AMP_MIN: 0.035, UP_K: 0.4, DOWN_K: 0.4, MIN_DT: 180, SMOOTH: 0.7, REARM_MS: 700 };
const cs = score(cur);
console.log(`err=${(cs.total * 100 / 3).toFixed(1)}%  ->  ${cs.counts.join(' / ')}`);
