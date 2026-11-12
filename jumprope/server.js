const https = require('https');
const http = require('http');
const fs = require('fs');
const zlib = require('zlib');
const crypto = require('crypto');
const path = require('path');

const ROOT = path.join(__dirname, 'public');
const CERT = path.join(__dirname, 'certs');
const PUBLIC_IP = '101.37.129.56';
const HTTPS_PORT = 8080;
const HTTP_PORT = 80;
const DOWNLOAD_DIR = path.join(ROOT, 'download');
fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });
const UPLOAD_TOKEN = process.env.UPLOAD_TOKEN || crypto.randomBytes(12).toString('hex');
const PLAIN_HTTP_PORT = 8001;   // 仅本机调试：纯 HTTP，用来验证缓存行为

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.task': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.apk': 'application/vnd.android.package-archive',
  '.ico': 'image/x-icon',
};


/* ---------------- 预压缩缓存（brotli / gzip） ---------------- */
const encCache = new Map();   // filePath -> { mtime, br, gz }
const COMPRESSIBLE = new Set(['.wasm', '.js', '.mjs', '.html', '.css', '.json', '.task', '.svg']);

function buildEncoded(filePath, buf) {
  const enc = { mtime: fs.statSync(filePath).mtimeMs, br: null, gz: null };
  try {
    enc.br = zlib.brotliCompressSync(buf, {
      params: {
        [zlib.constants.BROTLI_PARAM_QUALITY]: 8,
        [zlib.constants.BROTLI_PARAM_SIZE_HINT]: buf.length,
      },
    });
  } catch (_) { /* 忽略 */ }
  try {
    enc.gz = zlib.gzipSync(buf, { level: 9 });
  } catch (_) { /* 忽略 */ }
  return enc;
}

function getEncoded(filePath, buf) {
  const ext = path.extname(filePath).toLowerCase();
  if (!COMPRESSIBLE.has(ext) || buf.length < 1024) return null;
  const mtime = fs.statSync(filePath).mtimeMs;
  const hit = encCache.get(filePath);
  if (hit && hit.mtime === mtime) return hit;
  const enc = buildEncoded(filePath, buf);
  encCache.set(filePath, enc);
  return enc;
}

// 启动后在后台预热，避免第一个请求卡住
function warmCompression() {
  const targets = [];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p);
      else if (COMPRESSIBLE.has(path.extname(p).toLowerCase()) && st.size > 4096) targets.push(p);
    }
  };
  try { walk(ROOT); } catch (_) { return; }
  let i = 0;
  const next = () => {
    if (i >= targets.length) {
      const before = targets.reduce((a, p) => a + fs.statSync(p).size, 0);
      const after = targets.reduce((a, p) => a + (encCache.get(p)?.br?.length || fs.statSync(p).size), 0);
      console.log(`[压缩] ${targets.length} 个文件预热完成: ${(before/1048576).toFixed(1)}MB -> ${(after/1048576).toFixed(1)}MB`);
      return;
    }
    const p = targets[i++];
    try {
      const buf = fs.readFileSync(p);
      const mtime = fs.statSync(p).mtimeMs;
      encCache.set(p, buildEncoded(p, buf));
    } catch (_) { /* 忽略 */ }
    setTimeout(next, 0);
  };
  setTimeout(next, 50);
}


/* ---------------- 下载页 ---------------- */
const DOWNLOAD_EXT = ['.apk', '.zip', '.txt', '.log', '.json'];

function renderDownloadPage() {
  const EXT = ['.apk', '.zip', '.txt', '.log', '.json'];
  let files = [];
  try {
    files = fs.readdirSync(DOWNLOAD_DIR)
      .filter((f) => EXT.some((e) => f.toLowerCase().endsWith(e)))
      .map((f) => ({ name: f, mtime: fs.statSync(path.join(DOWNLOAD_DIR, f)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime)
      .map((x) => x.name);
  } catch (_) {}

  const apks = files.filter((f) => f.toLowerCase().endsWith('.apk'));
  const others = files.filter((f) => !f.toLowerCase().endsWith('.apk'));

  const item = (f) => {
    const st = fs.statSync(path.join(DOWNLOAD_DIR, f));
    const mb = (st.size / 1048576).toFixed(1);
    const t = new Date(st.mtimeMs).toLocaleString('zh-CN');
    return `<li><a href="/download/${encodeURIComponent(f)}">${f}</a><span>${mb} MB · ${t}</span></li>`;
  };

  const apkList = apks.length
    ? '<ul>' + apks.map(item).join('') + '</ul>'
    : `<div class="empty"><strong>还没有安装包</strong>
         <p>CI 构建完成后会自动出现在这里。<br>
         若一直没有，检查仓库是否配置了 <code>UPLOAD_TOKEN</code>。</p></div>`;

  const otherList = others.length
    ? `<h2>其他文件</h2><ul>${others.map(item).join('')}</ul>`
    : '';

  return `<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>下载</title><style>
body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:#0b1020;color:#e8ecff;padding:24px;line-height:1.7;margin:0}
h1{font-size:21px;margin:0 0 4px}
h2{font-size:15px;margin:28px 0 8px;opacity:.6;font-weight:500}
.sub{opacity:.5;font-size:13px;margin:0 0 18px}
ul{list-style:none;padding:0;margin:0}
li{padding:14px 16px;margin:10px 0;border-radius:12px;background:rgba(140,180,255,.07);border:1px solid rgba(140,180,255,.14)}
a{color:#6ea8ff;font-size:17px;text-decoration:none;display:block;word-break:break-all}
span{opacity:.45;font-size:12px}
.empty{padding:26px 18px;border-radius:12px;border:1px dashed rgba(140,180,255,.25);background:rgba(140,180,255,.04)}
.empty strong{font-size:15px}
.empty p{opacity:.5;font-size:13px;margin:8px 0 0}
code{background:rgba(255,255,255,.1);padding:1px 5px;border-radius:4px;font-size:12px}
.tip{margin-top:26px;font-size:12px;opacity:.4;line-height:1.8}
</style>
<h1>下载</h1><p class="sub">点文件名即可下载</p>
${apkList}${otherList}
<div class="tip">安装提示：Android 首次安装需允许「安装未知来源应用」。<br>
这是调试版（debug），用于真机验证，不是正式发布包。</div>`;
}

function handler(req, res) {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);

  if (urlPath === '/download' || urlPath === '/download/') {
    const html = renderDownloadPage();
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Length': Buffer.byteLength(html),
      'Cache-Control': 'no-store',
    });
    return res.end(html);
  }

  if (urlPath === '/') urlPath = '/index.html';

  const filePath = path.normalize(path.join(ROOT, urlPath));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('forbidden');
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('not found');
    }
    const ext = path.extname(filePath).toLowerCase();
    const immutable = ext === '.wasm' || ext === '.task';
    const etag = `"${data.length}-${fs.statSync(filePath).mtimeMs.toString(36)}"`;

    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, { ETag: etag, 'Cache-Control': 'no-cache' });
      return res.end();
    }
    const headers = {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Vary': 'Accept-Encoding',
      // 开启跨源隔离，让 MediaPipe 能用多线程 WASM
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
      'Cross-Origin-Resource-Policy': 'same-origin',
      'ETag': etag,
      'Cache-Control': immutable
        ? 'public, max-age=31536000, immutable'
        : 'no-cache',
    };

    const accept = String(req.headers['accept-encoding'] || '');
    const enc = getEncoded(filePath, data);
    let body = data;

    if (enc && /\bbr\b/.test(accept) && enc.br) {
      body = enc.br;
      headers['Content-Encoding'] = 'br';
    } else if (enc && /\bgzip\b/.test(accept) && enc.gz) {
      body = enc.gz;
      headers['Content-Encoding'] = 'gzip';
    }

    headers['Content-Length'] = body.length;
    res.writeHead(200, headers);
    res.end(body);
  });
}

const creds = {
  key: fs.readFileSync(path.join(CERT, 'key.pem')),
  cert: fs.readFileSync(path.join(CERT, 'cert.pem')),
};

warmCompression();

https.createServer(creds, handler).listen(HTTPS_PORT, '0.0.0.0', () => {
  console.log(`[HTTPS] https://${PUBLIC_IP}:${HTTPS_PORT}`);
  console.log(`[HTTPS] https://127.0.0.1:${HTTPS_PORT}`);
});

http.createServer(handler).listen(PLAIN_HTTP_PORT, '127.0.0.1', () => {
  console.log(`[HTTP ] http://127.0.0.1:${PLAIN_HTTP_PORT}  (本机调试用)`);
});

http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://x');
  const u = decodeURIComponent(url.pathname);

  /* ---- 上传 APK（CI 用）---- */
  if (req.method === 'POST' && u === '/upload') {
    const auth = String(req.headers['authorization'] || '').replace(/^Bearer\s+/i, '');
    const token = auth || url.searchParams.get('token') || '';
    if (token !== UPLOAD_TOKEN) {
      res.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('unauthorized');
    }
    const rawName = url.searchParams.get('name') || `app-${Date.now()}.apk`;
    const name = rawName.replace(/[^\w.\-]/g, '_');
    const dest = path.join(DOWNLOAD_DIR, name);
    let bytes = 0;
    const ws = fs.createWriteStream(dest);
    req.on('data', (c) => { bytes += c.length; });
    req.pipe(ws);
    ws.on('finish', () => {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, file: name, bytes, url: `http://${PUBLIC_IP}/${name}` }));
    });
    ws.on('error', () => {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('write error');
    });
    return;
  }

  /* ---- 下载列表 ---- */
  if ((req.method === 'GET' || req.method === 'HEAD') &&
      (u === '/' || u === '/index.html' || u === '/download' || u === '/download/')) {
    // 只列下载页，主页面仍然跳 HTTPS
    if (u === '/download' || u === '/download/' || req.headers['x-want-download'] === '1') {
      const html = renderDownloadPage();
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Length': Buffer.byteLength(html),
      });
      return res.end(html);
    }
  }

  /* ---- APK 直接下载 ---- */
  if (req.method === 'GET' && /\.(apk|zip|json|txt|md)$/i.test(u)) {
    // 下载页的链接是 /download/<file>，这里要剥掉前缀；
    // 否则会落到 302 → HTTPS，手机上会被自签证书拦住。
    let raw = u.slice(1);
    if (raw.startsWith('download/')) raw = raw.slice('download/'.length);
    const name = decodeURIComponent(raw).replace(/[^\w.\-]/g, '_');
    const file = path.join(DOWNLOAD_DIR, name);
    if (fs.existsSync(file)) {
      const st = fs.statSync(file);
      const ext = path.extname(name).toLowerCase();
      const ctype = ext === '.apk' ? 'application/vnd.android.package-archive'
        : ext === '.zip' ? 'application/zip'
        : ext === '.json' ? 'application/json; charset=utf-8'
        : 'text/plain; charset=utf-8';
      res.writeHead(200, {
        'Content-Type': ctype,
        'Content-Length': st.size,
        'Content-Disposition': `attachment; filename="${name}"`,
        'Cache-Control': 'no-store',
      });
      fs.createReadStream(file).pipe(res);
      return;
    }
  }

  /* ---- 其他一律跳 HTTPS ---- */
  const target = `https://${PUBLIC_IP}:${HTTPS_PORT}${req.url || '/'}`;
  res.writeHead(302, { Location: target });
  res.end(`<a href="${target}">跳转到 HTTPS</a>`);
}).listen(HTTP_PORT, '0.0.0.0', () => {
  console.log(`[HTTP ] http://${PUBLIC_IP}/  -> 302 -> HTTPS`);
  console.log(`[下载] http://${PUBLIC_IP}/download/`);
  console.log(`[上传] curl -X POST -H "Authorization: Bearer ${UPLOAD_TOKEN}" --data-binary @app.apk "http://${PUBLIC_IP}/upload?name=app.apk"`);
  console.log(`       --data-binary @app.apk "http://${PUBLIC_IP}/upload?name=app.apk"`);
  console.log(`[令牌] ${UPLOAD_TOKEN}`);
});
