/**
 * 从 GitHub Release 自动同步 APK 到本机下载目录。
 *
 * 为什么用 Release：Release 资产是公开可下载的，
 * 服务器不需要任何 token 或 secret。
 *
 *   node sync-apk.mjs          # 常驻轮询
 *   node sync-apk.mjs --once   # 只检查一次
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const REPO = 'lfchen760-hash/jumprope';
const TAG = 'debug-latest';
const OUT_DIR = path.join(__dirname, 'public', 'download');
const OUT_FILE = path.join(OUT_DIR, 'jumprope-debug.apk');
const STATE_FILE = path.join(__dirname, '.apk_sync_state.json');
const INTERVAL_MS = 5 * 60 * 1000;

function log(...a) {
  console.log(new Date().toISOString().slice(11, 19), ...a);
}

function readState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function writeState(s) {
  fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2));
}

async function fetchRelease() {
  const url = `https://api.github.com/repos/${REPO}/releases/tags/${TAG}`;
  const res = await fetch(url, {
    headers: { 'User-Agent': 'jumprope-sync', Accept: 'application/vnd.github+json' },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    log(`查询 Release 失败: HTTP ${res.status}`);
    return null;
  }
  return res.json();
}

async function download(url, dest) {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'jumprope-sync' },
    redirect: 'follow',
  });
  if (!res.ok) throw new Error(`下载失败 HTTP ${res.status}`);

  const tmp = dest + '.part';
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(tmp, buf);
  fs.renameSync(tmp, dest);
  return buf.length;
}

async function checkOnce() {
  let rel;
  try {
    rel = await fetchRelease();
  } catch (e) {
    log('网络错误:', e.message);
    return false;
  }
  if (!rel) {
    log('还没有 debug-latest Release');
    return false;
  }

  const asset = (rel.assets || []).find((a) => a.name.endsWith('.apk'));
  if (!asset) {
    log('Release 里没有 .apk 资产');
    return false;
  }

  const state = readState();
  if (state.assetId === asset.id) {
    log(`已是最新 (${asset.name}, ${(asset.size / 1048576).toFixed(1)}MB)`);
    return false;
  }

  log(`发现新版本 ${asset.updated_at}，开始下载 ${(asset.size / 1048576).toFixed(1)}MB…`);
  try {
    const n = await download(asset.browser_download_url, OUT_FILE);
    writeState({ assetId: asset.id, updatedAt: asset.updated_at, size: n, syncedAt: Date.now() });
    log(`完成 → ${OUT_FILE}  ${(n / 1048576).toFixed(1)}MB`);
    return true;
  } catch (e) {
    log('下载失败:', e.message);
    return false;
  }
}

fs.mkdirSync(OUT_DIR, { recursive: true });

if (process.argv.includes('--once')) {
  await checkOnce();
  process.exit(0);
}

log('开始轮询 GitHub Release（每 5 分钟）');
await checkOnce();
setInterval(checkOnce, INTERVAL_MS);
