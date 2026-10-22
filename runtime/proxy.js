#!/usr/bin/env node
/* Local HTTPS edge for the Ninja Saga preservation server.
 *
 * The patched Flash client talks to https://ninjasage.test/amf, /clan, /crew,
 * /game_data and /skills.  We terminate TLS here (self-signed cert, Chrome is
 * launched with --ignore-certificate-errors) and reverse-proxy dynamic
 * requests to the Laravel dev server on 127.0.0.1:8000.
 *
 * Static game assets are served straight from Laravel's public/ directory
 * (and from the client asset folders linked into it).  That keeps the PHP
 * built-in server free for AMF calls -- especially important on Windows,
 * where PHP's built-in server cannot use multiple workers.
 */
const https = require("https");
const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const PUBLIC_DIR = path.resolve(ROOT, "ns-server", "Database", "Laragon", "ninjasage", "public");
const CERT = path.join(ROOT, "runtime", "tls", "cert.pem");
const KEY = path.join(ROOT, "runtime", "tls", "key.pem");
const LISTEN_PORT = parseInt(process.env.EDGE_PORT || "8443", 10);
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || "8000", 10);

// Only these URL prefixes may be served from disk.  Everything else
// (/amf, /play, /admin, /skills/..., /enemy/...) goes to Laravel.
const STATIC_PREFIXES = [
  "/client/",
  "/game_data/",
  "/fonts/",
  "/tools/ruffle-web/",
  "/arcade/",
  "/items/",
  "/pets/",
  "/materials/",
  "/npcs/",
  "/enemy/",
  "/mission/",
  "/consumables/",
  "/essentials/",
  "/sounds/",
  "/swfpanels/",
  "/static/",
  "/css/",
  "/js/",
];

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".swf": "application/x-shockwave-flash",
  ".bin": "application/octet-stream",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".wav": "audio/wav",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".pdf": "application/pdf",
};

function isStaticPath(pathname) {
  return STATIC_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

function safeFilePath(pathname) {
  let rel;
  try {
    rel = decodeURIComponent(pathname);
  } catch {
    return null;
  }
  rel = rel.replace(/^\/+/, "");
  if (!rel || rel.includes("\0")) return null;
  // Never serve PHP source or dotfiles.
  if (/(^|\/)\./.test(rel)) return null;
  if (/\.php$/i.test(rel)) return null;

  const candidate = path.resolve(PUBLIC_DIR, rel);
  if (candidate !== PUBLIC_DIR && !candidate.startsWith(PUBLIC_DIR + path.sep)) {
    return null;
  }
  return candidate;
}

function serveStatic(req, res, pathname) {
  if (!isStaticPath(pathname)) return false;
  if (req.method !== "GET" && req.method !== "HEAD") return false;

  const file = safeFilePath(pathname);
  if (!file) return false;

  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    return false;
  }
  if (!stat.isFile()) return false;

  const ext = path.extname(file).toLowerCase();
  const type = MIME[ext] || "application/octet-stream";
  const headers = {
    "Content-Type": type,
    "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=3600",
    "Access-Control-Allow-Origin": "*",
  };

  // Minimal byte-range support (used by some browsers for large SWFs/WASM).
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (m) {
      let start = m[1] === "" ? null : parseInt(m[1], 10);
      let end = m[2] === "" ? null : parseInt(m[2], 10);
      if (start === null && end !== null) {
        // suffix range: last N bytes
        start = Math.max(0, stat.size - end);
        end = stat.size - 1;
      } else if (start !== null && end === null) {
        end = stat.size - 1;
      }
      if (start !== null && end !== null && start <= end && start < stat.size) {
        end = Math.min(end, stat.size - 1);
        res.writeHead(206, {
          ...headers,
          "Content-Range": `bytes ${start}-${end}/${stat.size}`,
          "Content-Length": end - start + 1,
        });
        if (req.method === "HEAD") return res.end();
        return fs.createReadStream(file, { start, end }).pipe(res);
      }
    }
    res.writeHead(416, { ...headers, "Content-Range": `bytes */${stat.size}` });
    return res.end();
  }

  res.writeHead(200, { ...headers, "Content-Length": stat.size });
  if (req.method === "HEAD") return res.end();
  return fs.createReadStream(file).pipe(res);
}

const server = https.createServer(
  { key: fs.readFileSync(KEY), cert: fs.readFileSync(CERT) },
  (req, res) => {
    // The client also talks to ninjasage.id / ns-assets.ninjasage.id (mapped
    // here by Chrome).  Allow those cross-origin loads so the Flash event
    // banners and colour endpoint behave like the original.
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const pathname = (req.url || "/").split("?")[0];
    try {
      if (serveStatic(req, res, pathname)) return;
    } catch (err) {
      console.error("static error:", err.message);
    }

    const headers = { ...req.headers, host: `127.0.0.1:${UPSTREAM_PORT}` };
    headers["x-forwarded-proto"] = "https";
    headers["x-forwarded-host"] = req.headers.host || "ninjasage.test";
    delete headers["accept-encoding"]; // keep proxying simple / byte-exact

    const upstream = http.request(
      {
        host: "127.0.0.1",
        port: UPSTREAM_PORT,
        method: req.method,
        path: req.url,
        headers,
      },
      (up) => {
        const outHeaders = { ...up.headers };
        delete outHeaders["transfer-encoding"];
        res.writeHead(up.statusCode || 502, outHeaders);
        up.pipe(res);
      }
    );

    upstream.on("error", (err) => {
      if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
      res.end("Ninja Saga edge: upstream error: " + err.message);
    });

    req.pipe(upstream);
  }
);

server.on("clientError", (err, socket) => {
  if (socket.writable) socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
});

server.listen(LISTEN_PORT, "127.0.0.1", () => {
  console.log(`Ninja Saga edge listening on https://ninjasage.test:${LISTEN_PORT} (-> :${UPSTREAM_PORT})`);
});
