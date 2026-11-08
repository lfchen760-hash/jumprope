#!/usr/bin/env node
/** 用 JS 版计数核心跑黄金向量。用法: node test/count_golden.mjs golden.json */
import { readFileSync } from 'node:fs';
import { createCounter } from '../public/counter.mjs';

const data = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const c = createCounter();
for (const f of data.frames) {
  c.feed(f[1], f[2], f[0], { hipX: f[3], tilt: f[4], kneeL: f[5], kneeR: f[6] });
}
console.log(c.count);
