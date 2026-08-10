// Serves build/web with the headers a real host sends. Node equivalent of
// serve_web.py, for machines without Python.
//
//   flutter build web --release
//   node tool/serve_web.mjs        # then open http://localhost:8099
//
// The cross-origin isolation headers are what let the database use OPFS
// instead of falling back to IndexedDB, and they match vercel.json — so what
// runs here is what runs in production.

import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.argv[2] ?? 8099);
// fileURLToPath rather than `.pathname`, which yields "/C:/…" on Windows.
const ROOT = fileURLToPath(new URL('../build/web/', import.meta.url));

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.symbols': 'application/octet-stream',
};

const NO_CACHE = new Set([
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter_service_worker.js',
]);

createServer(async (req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  let path = url === '/' ? '/index.html' : url;

  // Keep `..` from escaping the build directory.
  let file = join(ROOT, normalize(path).replace(/^(\.\.[/\\])+/, ''));

  let info = await stat(file).catch(() => null);
  if (!info?.isFile()) {
    // Single-page app: unknown paths fall back to the shell, matching the
    // rewrite rule in vercel.json.
    path = '/index.html';
    file = join(ROOT, 'index.html');
    info = await stat(file).catch(() => null);
    if (!info?.isFile()) {
      res.writeHead(404).end('build/web not found — run: flutter build web');
      return;
    }
  }

  res.writeHead(200, {
    'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream',
    'Content-Length': info.size,
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cache-Control': NO_CACHE.has(path) ? 'no-cache' : 'public, max-age=3600',
  });
  createReadStream(file).pipe(res);
}).listen(PORT, () => {
  console.log(`Everything is running at http://localhost:${PORT}`);
});
