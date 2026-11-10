import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'link_parser.dart';

/// Fetches a post's preview (cover image, author, caption) straight from the
/// phone.
///
/// Instagram and TikTok answer ordinary devices far more readily than they
/// answer cloud servers, so this is tried before the backend. It only reads
/// what the platforms publish for link previews and embeds. The same parsing
/// lives in backend/lib/metadata.js.
class DeviceMeta {
  DeviceMeta({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _ua = 'StashLinkPreview/1.0 (link preview fetcher)';
  static const _timeout = Duration(seconds: 5);

  /// Null when [rawUrl] is not an Instagram/TikTok link. Throws when the
  /// network is down.
  Future<PostMeta?> fetch(String rawUrl) async {
    final link = await _resolve(rawUrl);
    if (link == null) return null;

    var meta = const PreviewFields();
    if (link.platform == Platform2.tiktok) {
      meta = meta.or(await _try(() async => parseTikTokOembed(await _get(_oembed(link.url)))));
      if (!meta.complete) meta = meta.or(await _try(() async => parseTikTokPage(await _get(link.url))));
    } else {
      meta = meta.or(await _try(() async => parseInstagramPage(await _get(link.url))));
      if (!meta.complete) {
        meta = meta.or(await _try(() async => parseInstagramEmbed(await _get('${link.url}embed/captioned/'))));
      }
    }

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

  static String _oembed(String url) => 'https://www.tiktok.com/oembed?url=${Uri.encodeQueryComponent(url)}';

  /// A page that answers but has nothing useful is not an error; a dead
  /// network is, and is rethrown so the caller can tell "offline" apart.
  Future<PreviewFields> _try(Future<PreviewFields> Function() f) async {
    try {
      return await f();
    } on _HttpStatus {
      return const PreviewFields();
    } on FormatException {
      return const PreviewFields();
    }
  }

  Future<http.StreamedResponse> _send(String url) {
    final req = http.Request('GET', Uri.parse(url))
      ..followRedirects = false
      ..headers['user-agent'] = _ua
      ..headers['accept'] = 'text/html,application/json';
    return _client.send(req).timeout(_timeout);
  }

  Future<String> _get(String url) async {
    final res = await _send(url);
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
      if (c == null) break;
      current = c;
      next = target;
    }
    return current;
  }
}

class _HttpStatus implements Exception {}

class PreviewFields {
  const PreviewFields({this.author, this.authorName, this.caption, this.thumbnailUrl});
  final String? author;
  final String? authorName;
  final String? caption;
  final String? thumbnailUrl;

  bool get complete => caption != null && thumbnailUrl != null;

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
