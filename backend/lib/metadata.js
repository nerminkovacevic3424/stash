import { resolve } from './urls.js';

const TIMEOUT_MS = 4000;
const CACHE_TTL_MS = 60 * 60 * 1000;
const CACHE_MAX = 2000;
const cache = new Map(); // url -> { at, value }

// Identify honestly as a link-preview bot. Sites that refuse bots simply yield no
// preview, and the app saves the bare URL instead.
export const BOT_UA = 'StashLinkPreview/1.0 (link preview fetcher)';

async function getJson(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS), headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

function decodeEntities(s) {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

function metaTag(html, property) {
  const tag = html.match(new RegExp(`<meta[^>]+(?:property|name)=["']${property}["'][^>]*>`, 'i'))?.[0];
  const content = tag?.match(/content=["']([^"']*)["']/i)?.[1] ?? tag?.match(/content="([^"]*)"/i)?.[1];
  return content ? decodeEntities(content).trim() : null;
}

export function hashtagsOf(text) {
  if (!text) return [];
  return [...new Set([...text.matchAll(/#([\p{L}\p{N}_]+)/gu)].map((m) => m[1].toLowerCase()))].slice(0, 30);
}

async function tiktok(url) {
  const d = await getJson(`https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`);
  const fromUrl = d.author_url?.match(/@([^/?]+)/)?.[1];
  return {
    author: (d.author_unique_id || fromUrl || '').toLowerCase() || null,
    authorName: d.author_name || null,
    caption: d.title || null,
    thumbnailUrl: d.thumbnail_url || null,
  };
}

async function instagramOembed(url) {
  const token = process.env.META_APP_TOKEN;
  if (!token) return {};
  const d = await getJson(
    `https://graph.facebook.com/v22.0/instagram_oembed?url=${encodeURIComponent(url)}&access_token=${encodeURIComponent(token)}`,
  );
  // Newer "Meta oEmbed Read" responses omit author/thumbnail; the embed html
  // still carries the caption and handle, so mine it as well.
  const html = typeof d.html === 'string' ? d.html : '';
  const handle = html.match(/instagram\.com\/([A-Za-z0-9._]+)\/?\?utm_source=ig_embed/)?.[1];
  return {
    author: (d.author_name || handle || '').toLowerCase() || null,
    authorName: d.author_name || null,
    caption: d.title || null,
    thumbnailUrl: d.thumbnail_url || null,
  };
}

async function openGraph(url, platform) {
  const res = await fetch(url, {
    signal: AbortSignal.timeout(TIMEOUT_MS),
    redirect: 'manual', // a redirect here means a login wall
    headers: { 'user-agent': BOT_UA, accept: 'text/html' },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const html = (await res.text()).slice(0, 400_000);
  const title = metaTag(html, 'og:title');
  const desc = metaTag(html, 'og:description');
  const thumbnailUrl = metaTag(html, 'og:image');
  if (platform !== 'instagram') return { author: null, authorName: null, caption: desc || title, thumbnailUrl };
  // og:title:        Display Name on Instagram: "caption…"
  // og:description:  12K likes, 340 comments - handle on March 3, 2025: "caption…"
  // og:url:          https://www.instagram.com/handle/reel/CODE/
  const handle = metaTag(html, 'og:url')?.match(/instagram\.com\/([A-Za-z0-9._]+)\/(?:p|reel|tv)\//)?.[1];
  const t = title?.match(/^(.*?) on Instagram:\s*["“]?([\s\S]*?)["”]?$/);
  const d = desc?.match(/-\s*([A-Za-z0-9._]+) on [^:]+:\s*["“]?([\s\S]*?)["”]?\.?$/);
  return {
    author: (handle || d?.[1])?.toLowerCase() || null,
    authorName: t?.[1] || null,
    caption: t?.[2] || d?.[2] || desc || title || null,
    thumbnailUrl,
  };
}

const merge = (a, b) => Object.fromEntries(['author', 'authorName', 'caption', 'thumbnailUrl'].map((k) => [k, a[k] || b[k] || null]));

/** Resolves short links, then fetches preview metadata. Never throws. */
export async function fetchMetadata(rawUrl) {
  const link = await resolve(rawUrl);
  if (!link) return null;

  const hit = cache.get(link.url);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

  let meta = {};
  try {
    const oembed = link.platform === 'tiktok' ? tiktok : instagramOembed;
    meta = await oembed(link.url).catch(() => ({}));
    if (!meta.caption || !meta.thumbnailUrl) {
      meta = merge(meta, await openGraph(link.url, link.platform).catch(() => ({})));
    }
  } catch {
    meta = {};
  }

  const value = {
    url: link.url,
    platform: link.platform,
    resolved: !link.needsResolve,
    author: meta.author || link.author || null,
    authorName: meta.authorName || null,
    caption: meta.caption || null,
    thumbnailUrl: meta.thumbnailUrl || null,
    hashtags: hashtagsOf(meta.caption),
    ok: Boolean(meta.caption || meta.thumbnailUrl || meta.author),
  };
  if (value.ok) {
    if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
    cache.set(link.url, { at: Date.now(), value });
  }
  return value;
}
