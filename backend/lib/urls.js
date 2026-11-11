// URL extraction, platform detection, canonicalization and redirect resolution.
// The same rules live in app/lib/services/link_parser.dart and
// app/ios/StashShare/LinkParser.swift — keep the three in sync.
//
// Unlike the app, the server only ever fetches from the platforms named here.
// Links to any other site are previewed on the phone, so this service cannot
// be used to make requests to arbitrary addresses.

const HOSTS = {
  instagram: ['instagram.com', 'www.instagram.com', 'm.instagram.com', 'instagr.am'],
  tiktok: ['tiktok.com', 'www.tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'],
  youtube: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'],
  facebook: [
    'facebook.com', 'www.facebook.com', 'm.facebook.com', 'web.facebook.com', 'mbasic.facebook.com', 'fb.watch',
    'fb.com', 'www.fb.com',
  ],
  x: ['x.com', 'www.x.com', 'twitter.com', 'www.twitter.com', 'mobile.twitter.com'],
};
const TT_SHORT_HOSTS = new Set(['vm.tiktok.com', 'vt.tiktok.com']);

const UA = 'StashLinkPreview/1.0 (link preview fetcher)';

export function platformOfHost(host) {
  host = host.toLowerCase();
  for (const [platform, hosts] of Object.entries(HOSTS)) if (hosts.includes(host)) return platform;
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

/** First link to a supported platform found in shared text, or null. */
export function extractUrl(text) {
  if (typeof text !== 'string') return null;
  for (const m of text.matchAll(/https?:\/\/[^\s<>"']+/gi)) {
    const raw = m[0].replace(/[).,!?]+$/, '');
    const u = parse(raw);
    if (u && platformOfHost(u.hostname)) return raw;
  }
  return null;
}

/** `u` on `host`, keeping only the query parameters named in `keep`. */
function clean(u, host, keep) {
  const q = new URLSearchParams();
  for (const [k, v] of u.searchParams) if (keep.includes(k)) q.set(k, v);
  const qs = q.toString();
  return `https://${host}${u.pathname}${qs ? `?${qs}` : ''}`;
}

export function youtubeId(u) {
  const seg = u.pathname.split('/').filter(Boolean);
  let id = null;
  if (u.hostname.toLowerCase() === 'youtu.be') id = seg[0];
  else if (seg[0] === 'watch') id = u.searchParams.get('v');
  else if (['shorts', 'live', 'embed', 'v'].includes(seg[0])) id = seg[1];
  return id && /^[A-Za-z0-9_-]{6,20}$/.test(id) ? id : null;
}

/**
 * Normalizes a post URL. Returns null for links to sites other than the
 * supported platforms. `needsResolve` is true for short/share links whose
 * final URL is only known after following redirects.
 */
export function canonicalize(raw) {
  const u = parse(raw);
  if (!u) return null;
  const host = u.hostname.toLowerCase();
  const platform = platformOfHost(host);
  if (!platform) return null;
  const seg = u.pathname.split('/').filter(Boolean);
  const link = (url, extra = {}) => ({ platform, url, author: null, needsResolve: false, ...extra });

  switch (platform) {
    case 'instagram': {
      const i = seg.findIndex((s) => ['p', 'reel', 'reels', 'tv'].includes(s));
      if (i >= 0 && seg[i + 1] && seg[0] !== 'share') {
        return link(`https://www.instagram.com/${seg[i] === 'reels' ? 'reel' : seg[i]}/${seg[i + 1]}/`);
      }
      return link(`https://www.instagram.com/${seg.join('/')}${seg.length ? '/' : ''}`, {
        needsResolve: seg[0] === 'share' || host === 'instagr.am',
      });
    }
    case 'tiktok':
      if (TT_SHORT_HOSTS.has(host) || seg[0] === 't') return link(`https://${host}/${seg.join('/')}`, { needsResolve: true });
      if (seg[0]?.startsWith('@') && ['video', 'photo'].includes(seg[1]) && seg[2]) {
        return link(`https://www.tiktok.com/${seg[0]}/${seg[1]}/${seg[2]}`, { author: seg[0].slice(1).toLowerCase() });
      }
      return link(`https://www.tiktok.com/${seg.join('/')}`);
    case 'youtube': {
      const id = youtubeId(u);
      if (!id) return link(clean(u, 'www.youtube.com', ['list']));
      return link(seg[0] === 'shorts' ? `https://www.youtube.com/shorts/${id}` : `https://www.youtube.com/watch?v=${id}`);
    }
    case 'facebook':
      if (host === 'fb.watch') return link(clean(u, host, []), { needsResolve: true });
      return link(clean(u, 'www.facebook.com', ['v', 'story_fbid', 'id', 'fbid']), { needsResolve: seg[0] === 'share' });
    case 'x':
      if (seg[1] === 'status' && seg[2]) {
        return link(`https://x.com/${seg[0]}/status/${seg[2]}`, { author: seg[0].toLowerCase() });
      }
      return link(clean(u, 'x.com', []));
  }
  return null;
}

/**
 * Follows redirects by hand so every hop can be checked: a short link may
 * only lead to the platform it started on.
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
    if (!c || c.platform !== current.platform) break; // wandered off to a login wall or app store
    current = c;
    next = target;
  }
  return current;
}
