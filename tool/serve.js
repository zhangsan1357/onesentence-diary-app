// build/web 静态服务器 + 同源 API 代理（零依赖）：node tool/serve.js [port]
// 晨 19 §5.13：/api/* 反向代理到后端（与生产 nginx 同源拓扑一致）——
// web 预览真栈联调不依赖 CORS；服务端地址填本预览源（如 http://127.0.0.1:8123）。
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'build', 'web');
const port = Number(process.argv[2] || 8123);
// 代理目标（可用第三参覆盖）：node tool/serve.js 8123 http://127.0.0.1:9060
const apiTarget = process.argv[3] || 'http://127.0.0.1:9060';
const mime = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.woff2': 'font/woff2',
  '.webp': 'image/webp', '.ico': 'image/x-icon',
};

function proxy(req, res) {
  const url = new URL(req.url, apiTarget);
  const upstream = http.request(
    {
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: req.method,
      headers: { ...req.headers, host: url.host },
    },
    (ur) => {
      res.writeHead(ur.statusCode || 502, ur.headers);
      ur.pipe(res);
    },
  );
  upstream.on('error', () => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ code: 502, message: '代理目标不可达', data: null }));
  });
  req.pipe(upstream);
}

http.createServer((req, res) => {
  // 同源代理：/api/* → 后端（流式转发请求/响应体，媒体上传下载均可用）
  if (req.url.startsWith('/api/')) {
    proxy(req, res);
    return;
  }
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/' || p === '') p = '/index.html';
  const file = path.join(root, p);
  if (!file.startsWith(root)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) {
      // SPA 兜底回 index.html
      fs.readFile(path.join(root, 'index.html'), (e2, idx) => {
        if (e2) { res.writeHead(404); res.end('not found'); return; }
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(idx);
      });
      return;
    }
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () =>
  console.log(`serving build/web at http://127.0.0.1:${port} (api → ${apiTarget})`));
