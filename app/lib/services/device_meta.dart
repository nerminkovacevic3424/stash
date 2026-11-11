import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'link_parser.dart';

/// Fetches a post's preview (cover image, author, caption) straight from the
/// phone.
///
/// The platforms answer ordinary devices far more readily than they
/// answer cloud servers, so this is tried before the backend. It only reads
/// what the platforms publish for link previews and embeds. The same parsing
/// lives in backend/lib/metadata.js.
class DeviceMeta {
  DeviceMeta({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _ua = 'StashLinkPreview/1.0 (link preview fetcher)';
  static const _timeout = Duration(seconds: 5);

  /// Null when [rawUrl] is not a web link. Throws when the network is down.
  Future<PostMeta?> fetch(String rawUrl) async {
    final link = await _resolve(rawUrl);
    if (link == null) return null;

    var meta = const PreviewFields();
    switch (link.platform) {
      case Platform2.tiktok:
        meta = meta.or(
          await _try(() async => parseTikTokOembed(await _get(_oembed('www.tiktok.com/oembed', link.url)))),
        );
        if (!meta.complete) meta = meta.or(await _try(() async => parseTikTokPage(await _get(link.url))));
      case Platform2.instagram:
        meta = meta.or(await _try(() async => parseInstagramPage(await _get(link.url))));
        if (!meta.complete) {
          meta = meta.or(await _try(() async => parseInstagramEmbed(await _get('${link.url}embed/captioned/'))));
        }
      case Platform2.youtube:
        meta = meta.or(
          await _try(
            () async => parseYouTubeOembed(await _get('${_oembed('www.youtube.com/oembed', link.url)}&format=json')),
          ),
        );
        // Every video has a cover at a fixed address, even when oEmbed is refused.
        final id = youtubeId(Uri.parse(link.url));
        if (meta.thumbnailUrl == null && id != null) {
          meta = meta.or(PreviewFields(thumbnailUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg'));
        }
        if (meta.caption == null) {
          meta = meta.or(await _try(() async => parseGenericPage(await _get(link.url, follow: true))));
        }
      case Platform2.x:
        meta = meta.or(
          await _try(
            () async => parseXOembed(await _get('${_oembed('publish.twitter.com/oembed', link.url)}&omit_script=1')),
          ),
        );
        if (!meta.complete) {
          meta = meta.or(await _try(() async => parseGenericPage(await _get(link.url, follow: true))));
        }
      case Platform2.facebook:
      case Platform2.other:
        meta = meta.or(await _try(() async => parseGenericPage(await _get(link.url, follow: true))));
    }

    if (_boilerplate.contains(meta.caption?.toLowerCase())) meta = meta.withoutCaption();

    return PostMeta(
      url: link.url,
      resolved: !link.needsResolve,
      author: meta.author ?? link.author,
      authorName: meta.authorName,
      caption: meta.caption,
      thumbnailUrl: meta.thumbnailUrl,
      hashtags: hashtagsOf(meta.caption),
      ok: meta.caption != null || meta.thumbnailUrl != null,
    );
  }

  static String _oembed(String endpoint, String url) => 'https://$endpoint?url=${Uri.encodeQueryComponent(url)}';

  /// A page that answers but has nothing useful is not an error; a dead
  /// network is, and is rethrown so the caller can tell "offline" apart.
  Future<PreviewFields> _try(Future<PreviewFields> Function() f) async {
    try {
      return await f();
    } on _HttpStatus {
      return const PreviewFields();
    } on FormatException {
      return const PreviewFields();
    } on TimeoutException {
      // A site that is slow to answer is not the same as being offline.
      return const PreviewFields();
    }
  }

  Future<http.StreamedResponse> _send(String url, {bool follow = false}) {
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = follow
      ..headers['user-agent'] = _ua
      ..headers['accept'] = 'text/html,application/json';
    return _client.send(req).timeout(_timeout);
  }

  Future<String> _get(String url, {bool follow = false}) async {
    final res = await _send(url, follow: follow);
    if (res.statusCode != 200) {
      await res.stream.drain<void>().catchError((_) {});
      throw _HttpStatus();
    }
    return res.stream.bytesToString().timeout(_timeout);
  }

  /// Follows short/share links, checking every hop stays on the platform.
  Future<LinkInfo?> _resolve(String raw) async {
    var current = canonicalize(raw);
    if (current == null) return null;
    var next = raw;
    for (var hop = 0; hop < 5 && current!.needsResolve; hop++) {
      final res = await _send(next);
      await res.stream.drain<void>().catchError((_) {});
      final loc = res.headers['location'];
      if (res.statusCode < 300 || res.statusCode >= 400 || loc == null) break;
      final target = Uri.parse(next).resolve(loc).toString();
      final c = canonicalize(target);
      if (c == null || c.platform != current.platform) break; // wandered off to a login page or store
      current = c;
      next = target;
    }
    return current;
  }
}

class _HttpStatus implements Exception {}

/// Titles a platform serves when it shows a login wall instead of the post.
const _boilerplate = {
  'facebook',
  'instagram',
  'tiktok',
  'tiktok - make your day',
  'youtube',
  'x',
  'log in or sign up to view',
  'log into facebook',
};

class PreviewFields {
  const PreviewFields({this.author, this.authorName, this.caption, this.thumbnailUrl});
  final String? author;
  final String? authorName;
  final String? caption;
  final String? thumbnailUrl;

  bool get complete => caption != null && thumbnailUrl != null;

  PreviewFields withoutCaption() => PreviewFields(author: author, authorName: authorName, thumbnailUrl: thumbnailUrl);

  PreviewFields or(PreviewFields o) => PreviewFields(
    author: author ?? o.author,
    authorName: authorName ?? o.authorName,
    caption: caption ?? o.caption,
    thumbnailUrl: thumbnailUrl ?? o.thumbnailUrl,
  );
}

Object? _dig(Object? node, List<String> path) {
  for (final key in path) {
    if (node is! Map) return null;
    node = node[key];
  }
  return node;
}

String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

String _decodeEntities(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String? _metaTag(String html, String property) {
  final tag = RegExp(
    '<meta[^>]+(?:property|name)=["\']$property["\'][^>]*>',
    caseSensitive: false,
  ).firstMatch(html)?[0];
  if (tag == null) return null;
  final content = RegExp(r'content="([^"]*)"', caseSensitive: false).firstMatch(tag)?[1];
  return content == null ? null : _nonEmpty(_decodeEntities(content));
}

PreviewFields parseTikTokOembed(String body) {
  final d = jsonDecode(body);
  if (d is! Map) return const PreviewFields();
  final fromUrl = RegExp(r'@([^/?]+)').firstMatch('${d['author_url'] ?? ''}')?[1];
  return PreviewFields(
    author: (_nonEmpty(d['author_unique_id']) ?? fromUrl)?.toLowerCase(),
    authorName: _nonEmpty(d['author_name']),
    caption: _nonEmpty(d['title']),
    thumbnailUrl: _nonEmpty(d['thumbnail_url']),
  );
}

/// TikTok ships the post's details as JSON inside the public page.
PreviewFields parseTikTokPage(String html) {
  final json = RegExp(r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>([\s\S]*?)</script>').firstMatch(html)?[1];
  if (json == null) return const PreviewFields();
  final root = jsonDecode(json);
  final item = _dig(root, const ['__DEFAULT_SCOPE__', 'webapp.video-detail', 'itemInfo', 'itemStruct']);
  if (item is! Map) return const PreviewFields();
  final author = item['author'];
  final video = item['video'];
  return PreviewFields(
    author: author is Map ? _nonEmpty(author['uniqueId'])?.toLowerCase() : null,
    authorName: author is Map ? _nonEmpty(author['nickname']) : null,
    caption: _nonEmpty(item['desc']),
    thumbnailUrl: video is Map ? _nonEmpty(video['cover']) ?? _nonEmpty(video['originCover']) : null,
  );
}

/// Open Graph tags on the Instagram post page.
PreviewFields parseInstagramPage(String html) {
  final title = _metaTag(html, 'og:title');
  final desc = _metaTag(html, 'og:description');
  // og:title:  Display Name on Instagram: "caption…"
  // og:url:    https://www.instagram.com/handle/reel/CODE/
  final handle = RegExp(r'instagram\.com/([A-Za-z0-9._]+)/(?:p|reel|tv)/')
      .firstMatch(_metaTag(html, 'og:url') ?? '')?[1];
  final t = title == null ? null : RegExp(r'^(.*?) on Instagram:\s*["“]?([\s\S]*?)["”]?$').firstMatch(title);
  return PreviewFields(
    author: handle?.toLowerCase(),
    authorName: _nonEmpty(t?[1]),
    caption: _nonEmpty(t?[2]) ?? desc,
    thumbnailUrl: _metaTag(html, 'og:image'),
  );
}

/// Instagram's public embed page (what an iframe embed loads). It carries the
/// cover image, handle and caption even when the post page does not.
PreviewFields parseInstagramEmbed(String html) {
  final imgTag = RegExp(r'<img[^>]+class="EmbeddedMediaImage"[^>]*>').firstMatch(html)?[0];
  final img = imgTag == null ? null : RegExp(r'src="([^"]+)"').firstMatch(imgTag)?[1];
  final handle =
      RegExp(r'class="UsernameText"[^>]*>([^<]+)<').firstMatch(html)?[1] ??
      RegExp(r'class="CaptionUsername"[^>]*>([^<]+)<').firstMatch(html)?[1];
  final block =
      RegExp(r'<div class="Caption">([\s\S]*?)<div class="CaptionComments"').firstMatch(html)?[1] ??
      RegExp(r'<div class="Caption">([\s\S]*?)</div>').firstMatch(html)?[1];
  String? caption;
  if (block != null) {
    // The block opens with the author's handle as a link; drop it.
    final text = block
        .replaceFirst(RegExp(r'<a class="CaptionUsername"[\s\S]*?</a>'), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    caption = _nonEmpty(_decodeEntities(text));
  }
  return PreviewFields(
    author: _nonEmpty(handle)?.toLowerCase(),
    caption: caption,
    thumbnailUrl: img == null ? null : _decodeEntities(img),
  );
}

PreviewFields parseYouTubeOembed(String body) {
  final d = jsonDecode(body);
  if (d is! Map) return const PreviewFields();
  final handle = RegExp(r'youtube\.com/@([^/?]+)').firstMatch('${d['author_url'] ?? ''}')?[1];
  final name = _nonEmpty(d['author_name']);
  return PreviewFields(
    author: (handle ?? name)?.toLowerCase(),
    authorName: name,
    caption: _nonEmpty(d['title']),
    thumbnailUrl: _nonEmpty(d['thumbnail_url']),
  );
}

/// X's public embed endpoint returns the post as a small HTML snippet.
PreviewFields parseXOembed(String body) {
  final d = jsonDecode(body);
  if (d is! Map) return const PreviewFields();
  final p = RegExp(r'<p[^>]*>([\s\S]*?)</p>').firstMatch('${d['html'] ?? ''}')?[1];
  final text = p == null
      ? null
      : _nonEmpty(_decodeEntities(p.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '')));
  final handle = RegExp(r'(?:x|twitter)\.com/([^/?]+)').firstMatch('${d['author_url'] ?? ''}')?[1];
  return PreviewFields(author: handle?.toLowerCase(), authorName: _nonEmpty(d['author_name']), caption: text);
}

/// Link-preview tags that almost every site publishes (Open Graph, Twitter
/// cards, or at least a title). Used for Facebook and any other site.
PreviewFields parseGenericPage(String html) {
  final head = html.length > 300000 ? html.substring(0, 300000) : html;
  final title =
      _metaTag(head, 'og:title') ??
      _metaTag(head, 'twitter:title') ??
      _nonEmpty(
        _decodeEntities(RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(head)?[1] ?? ''),
      );
  final desc =
      _metaTag(head, 'og:description') ?? _metaTag(head, 'twitter:description') ?? _metaTag(head, 'description');
  final caption = [title, if (desc != null && desc != title) desc].whereType<String>().join('\n');
  return PreviewFields(
    authorName: _metaTag(head, 'author') ?? _metaTag(head, 'og:site_name'),
    caption: _nonEmpty(caption),
    thumbnailUrl: _metaTag(head, 'og:image') ?? _metaTag(head, 'twitter:image'),
  );
}
