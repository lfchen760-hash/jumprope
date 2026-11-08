#!/usr/bin/env node
/** 原始关键点 JSON → 黄金向量格式。用法: node test/make_golden.mjs lm.json out.json [标注次数] */
import { readFileSync, writeFileSync } from 'node:fs';
import { postureOf } from '../public/posture.mjs';

const [, , input, output, labelArg] = process.argv;
if (!input || !output) {
  console.log('用法: node test/make_golden.mjs 关键点.json 输出.json [标注次数]');
  process.exit(1);
}
const j = JSON.parse(readFileSync(input, 'utf8'));
const frames = [];
for (const fr of j.frames) {
  if (!fr.lm) continue;
  const lm = fr.lm;
  const hipY = (lm[23][1] + lm[24][1]) / 2;
  const shY = (lm[11][1] + lm[12][1]) / 2;
  const hipX = (lm[23][0] + lm[24][0]) / 2;
  const post = postureOf(lm);
  frames.push([
    Math.round(fr.t),
    +hipY.toFixed(4), +Math.max(Math.abs(hipY - shY), 0.03).toFixed(4), +hipX.toFixed(4),
    +post.tilt.toFixed(1), +post.kneeL.toFixed(1), +post.kneeR.toFixed(1),
  ]);
}
writeFileSync(output, JSON.stringify({
  name: input.split('/').pop().replace(/\.json$/, ''),
  labelCount: labelArg ? Number(labelArg) : null,
  expected: null,
  fps: j.fps,
  frames,
}));
console.log(`生成 ${output}  ${frames.length} 帧`);
