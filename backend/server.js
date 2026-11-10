import http from 'node:http';
import { extractUrl, resolve } from './lib/urls.js';
import { fetchMetadata } from './lib/metadata.js';
import { suggestFolder } from './lib/suggest.js';

const PORT = Number(process.env.PORT || 8787);
const APP_KEY = process.env.APP_KEY || '';
const RATE_LIMIT = 60; // requests per minute per IP
const hits = new Map();

function rateLimited(ip) {
  const now = Date.now();
  const h = hits.get(ip);
  if (!h || now - h.start > 60_000) {
    hits.set(ip, { start: now, n: 1 });
    return false;
  }
  return ++h.n > RATE_LIMIT;
}
setInterval(() => {
  const cutoff = Date.now() - 60_000;
  for (const [ip, h] of hits) if (h.start < cutoff) hits.delete(ip);
}, 60_000).unref();

// Behind a host's load balancer every request arrives from the proxy, so the
// forwarded address is used instead. Only enable where a proxy really sets it.
const TRUST_PROXY = process.env.TRUST_PROXY === '1';
function clientIp(req) {
  const fwd = TRUST_PROXY ? String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim() : '';
  return fwd || req.socket.remoteAddress || '';
}

function send(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > 64 * 1024) throw Object.assign(new Error('body too large'), { status: 413 });
    chunks.push(c);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
    if (body && typeof body === 'object') return body;
  } catch {}
  throw Object.assign(new Error('invalid JSON'), { status: 400 });
}

/** Accepts either a clean `url` or the raw shared `text`. */
function urlFrom(body) {
  const url = extractUrl(typeof body.url === 'string' ? body.url : body.text);
  if (!url) throw Object.assign(new Error('no Instagram or TikTok URL found'), { status: 422 });
  return url;
}

const routes = {
  'POST /v1/resolve': async (body) => {
    const link = await resolve(urlFrom(body));
    return { url: link.url, platform: link.platform, author: link.author, resolved: !link.needsResolve };
  },
  'POST /v1/metadata': async (body) => fetchMetadata(urlFrom(body)),
  'POST /v1/suggest': async (body) => {
    try {
      return await suggestFolder(body); // { description, suggestion }
    } catch (err) {
      console.error('suggest failed:', err?.status ?? '', err?.message);
      return { description: null, suggestion: null }; // the app falls back to last-used / Unsorted
    }
  },
};

const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://x').pathname;
    if (req.method === 'GET' && path === '/health') return send(res, 200, { ok: true });

    const handler = routes[`${req.method} ${path}`];
    if (!handler) return send(res, 404, { error: 'not found' });
    if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) return send(res, 401, { error: 'unauthorized' });
    if (rateLimited(clientIp(req))) return send(res, 429, { error: 'slow down' });

    send(res, 200, await handler(await readJson(req)));
  } catch (err) {
    if (!err.status) console.error(err);
    send(res, err.status || 500, { error: err.status ? err.message : 'internal error' });
  }
});

server.listen(PORT, () => {
  console.log(`stash backend on :${PORT}`);
  if (!process.env.ANTHROPIC_API_KEY) console.log('  ANTHROPIC_API_KEY not set — AI suggestions disabled');
  if (!process.env.META_APP_TOKEN) console.log('  META_APP_TOKEN not set — Instagram uses Open Graph only');
});
