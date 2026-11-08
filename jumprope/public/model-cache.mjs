/**
 * 模型文件缓存：用 Cache Storage 绕开浏览器对大文件的 HTTP 缓存策略。
 * Chrome 对 5MB 左右的 .task 基本不缓存，每次都会完整重新下载。
 */
export const MODEL_URL = './models/pose_landmarker_lite.task';
const MODEL_CACHE = 'jr-model-v1';

export function humanSize(n) {
  return n > 1048576 ? (n / 1048576).toFixed(1) + 'MB' : Math.round(n / 1024) + 'KB';
}

export async function fetchWithProgress(url, onProgress = () => {}) {
  const res = await fetch(url);
  if (!res.ok) throw new Error('模型下载失败 ' + res.status);
  const total = Number(res.headers.get('content-length')) || 0;
  if (!res.body || !total) return res;

  const reader = res.body.getReader();
  const chunks = [];
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    received += value.length;
    onProgress(received, total);
  }
  const buf = new Uint8Array(received);
  let off = 0;
  for (const c of chunks) { buf.set(c, off); off += c.length; }

  return new Response(buf, {
    headers: {
      'Content-Type': res.headers.get('content-type') || 'application/octet-stream',
      'Content-Length': String(received),
    },
  });
}

export async function getModelAsset(onProgress = () => {}) {
  let cached = null;
  try {
    const cache = await caches.open(MODEL_CACHE);
    cached = await cache.match(MODEL_URL);
  } catch (_) { /* 无 Cache API */ }

  if (cached) {
    const blob = await cached.blob();
    onProgress(1, 1, true);
    return URL.createObjectURL(blob);
  }

  const res = await fetchWithProgress(MODEL_URL, onProgress);
  try {
    const cache = await caches.open(MODEL_CACHE);
    await cache.put(MODEL_URL, res.clone());
  } catch (_) { /* 存不进去也不影响使用 */ }
  const blob = await res.blob();
  return URL.createObjectURL(blob);
}

