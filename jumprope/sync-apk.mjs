/**
 * 从仓库的 apk 分支同步 APK 到本机下载目录。
 *
 * 为什么走 git 而不是 Release：
 *   GitHub 的 Release 下载通道（objects.githubusercontent.com）经常 504，
 *   而 git 通道一直可用。CI 会把构建产物推到 apk 分支。
 *
 *   node sync-apk.mjs          # 常驻轮询（每 5 分钟）
 *   node sync-apk.mjs --once   # 只检查一次
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_DIR = '/root/dsh/test/repo';
const BRANCH = 'apk';
const OUT_DIR = path.join(__dirname, 'public', 'download');
const OUT_FILE = path.join(OUT_DIR, 'jumprope.apk');
const STATE_FILE = path.join(__dirname, '.apk_sync_state.json');
const INTERVAL_MS = 5 * 60 * 1000;
// 从仓库拉取，必须走 Deploy Key；未显式设置时给默认值，
// 否则 GIT_SSH_COMMAND='' 会让 git 直接报 "cannot run"。
const SSH =
  process.env.GIT_SSH_COMMAND ||
  'ssh -i /root/dsh/test/.ssh/deploy_key ' +
    '-o UserKnownHostsFile=/root/dsh/test/.ssh/known_hosts -o IdentitiesOnly=yes';

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

const git = (args, opts = {}) =>
  execFileSync('git', ['-C', REPO_DIR, ...args], {
    encoding: 'buffer',
    maxBuffer: 512 * 1024 * 1024,
    env: { ...process.env, GIT_SSH_COMMAND: SSH },
    ...opts,
  });

function readState() {
  try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch { return {}; }
}
const writeState = (s) => fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2));

async function checkOnce() {
  try {
    git(['fetch', '-q', 'origin', BRANCH]);
  } catch (e) {
    log('git fetch 失败:', e.message.split('\n')[0]);
    return false;
  }

  let blob;
  try {
    blob = git(['rev-parse', `origin/${BRANCH}:jumprope.apk`]).toString().trim();
  } catch {
    log('apk 分支里没有 jumprope.apk');
    return false;
  }

  const state = readState();
  if (state.blob === blob && fs.existsSync(OUT_FILE)) {
    log(`已是最新 (${(fs.statSync(OUT_FILE).size / 1048576).toFixed(1)}MB)`);
    return false;
  }

  // apk 分支的 commit message 形如 "apk: build b054d1e [skip ci]"
  const subject = git(['log', '-1', '--format=%s', `origin/${BRANCH}`])
    .toString()
    .trim();
  const build = /build ([0-9a-f]{7,})/i.exec(subject)?.[1];
  const tag = build ?? git(['rev-parse', `origin/${BRANCH}`]).toString().trim().slice(0, 7);

  log('发现新构建，导出中…');
  try {
    const buf = git(['cat-file', '-p', `origin/${BRANCH}:jumprope.apk`]);
    const tmp = OUT_FILE + '.part';
    fs.writeFileSync(tmp, buf);
    fs.renameSync(tmp, OUT_FILE);
    writeState({ blob, size: buf.length, syncedAt: Date.now() });
    const versioned = path.join(OUT_DIR, `jumprope-${tag}.apk`);
    fs.copyFileSync(OUT_FILE, versioned);
    log(`完成 → ${OUT_FILE}  ${(buf.length / 1048576).toFixed(1)}MB`);
    log(`版本副本 → ${path.basename(versioned)}`);
    return true;
  } catch (e) {
    log('导出失败:', e.message.split('\n')[0]);
    return false;
  }
}

fs.mkdirSync(OUT_DIR, { recursive: true });

if (process.argv.includes('--once')) {
  await checkOnce();
  process.exit(0);
}

log('开始轮询 apk 分支（每 5 分钟）');
await checkOnce();
setInterval(checkOnce, INTERVAL_MS);
