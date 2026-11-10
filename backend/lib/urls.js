// URL extraction, platform detection, canonicalization and redirect resolution.
// The same rules live in app/lib/services/link_parser.dart and
// app/ios/StashShare/LinkParser.swift — keep the three in sync.

const IG_HOSTS = new Set(['instagram.com', 'www.instagram.com', 'm.instagram.com', 'instagr.am']);
const TT_HOSTS = new Set(['tiktok.com', 'www.tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com']);
const TT_SHORT_HOSTS = new Set(['vm.tiktok.com', 'vt.tiktok.com']);

const UA = 'StashLinkPreview/1.0 (link preview fetcher)';

export function platformOfHost(host) {
  host = host.toLowerCase();
  if (IG_HOSTS.has(host)) return 'instagram';
  if (TT_HOSTS.has(host)) return 'tiktok';
  return null;
}

function parse(raw) {
  try {
    const u = new URL(raw);
    return u.protocol === 'https:' || u.protocol === 'http:' ? u : null;
  } catch {
    return null;
  }
}

/** First Instagram/TikTok URL found in shared text, or null. */
export function extractUrl(text) {
  if (typeof text !== 'string') return null;
  for (const m of text.matchAll(/https?:\/\/[^\s<>"']+/gi)) {
    const raw = m[0].replace(/[).,!?]+$/, '');
    const u = parse(raw);
    if (u && platformOfHost(u.hostname)) return raw;
  }
  return null;
}

/**
 * Normalizes a post URL. Returns null for URLs that are not Instagram/TikTok.
 * `needsResolve` is true for short/share links whose final URL is only known
 * after following redirects.
 */
export function canonicalize(raw) {
  const u = parse(raw);
  if (!u) return null;
  const host = u.hostname.toLowerCase();
  const platform = platformOfHost(host);
  if (!platform) return null;
  const seg = u.pathname.split('/').filter(Boolean);

  if (platform === 'instagram') {
    const i = seg.findIndex((s) => ['p', 'reel', 'reels', 'tv'].includes(s));
    if (i >= 0 && seg[i + 1] && seg[0] !== 'share') {
      const kind = seg[i] === 'reels' ? 'reel' : seg[i];
      return { platform, url: `https://www.instagram.com/${kind}/${seg[i + 1]}/`, author: null, needsResolve: false };
    }
    const needsResolve = seg[0] === 'share' || host === 'instagr.am';
    return { platform, url: `https://www.instagram.com/${seg.join('/')}${seg.length ? '/' : ''}`, author: null, needsResolve };
  }

  if (TT_SHORT_HOSTS.has(host) || seg[0] === 't') {
    return { platform, url: `https://${host}/${seg.join('/')}`, author: null, needsResolve: true };
  }
  if (seg[0]?.startsWith('@') && ['video', 'photo'].includes(seg[1]) && seg[2]) {
    return {
      platform,
      url: `https://www.tiktok.com/${seg[0]}/${seg[1]}/${seg[2]}`,
      author: seg[0].slice(1).toLowerCase(),
      needsResolve: false,
    };
  }
  return { platform, url: `https://www.tiktok.com/${seg.join('/')}`, author: null, needsResolve: false };
}

/**
 * Follows redirects by hand so every hop can be checked against the host
 * allow-list (this endpoint must not become an open SSRF proxy).
 */
export async function resolve(raw, { maxHops = 5, timeoutMs = 4000 } = {}) {
  let current = canonicalize(raw);
  if (!current) return null;
  let next = raw;
  for (let hop = 0; hop < maxHops && current.needsResolve; hop++) {
    let res;
    try {
      res = await fetch(next, {
        method: 'GET',
        redirect: 'manual',
        headers: { 'user-agent': UA, accept: 'text/html' },
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      break;
    }
    res.body?.cancel().catch(() => {});
    const loc = res.headers.get('location');
    if (!(res.status >= 300 && res.status < 400) || !loc) break;
    const target = new URL(loc, next).toString();
    const c = canonicalize(target);
    if (!c) break; // redirected off-platform (login wall, app store…) — keep what we have
    current = c;
    next = target;
  }
  return current;
}
