import '../models.dart';

// Rules for the named platforms also live in backend/lib/urls.js and
// ios/StashShare/LinkParser.swift — keep the three in sync.

const _hosts = <Platform2, Set<String>>{
  Platform2.instagram: {'instagram.com', 'www.instagram.com', 'm.instagram.com', 'instagr.am'},
  Platform2.tiktok: {'tiktok.com', 'www.tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'},
  Platform2.youtube: {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'},
  Platform2.facebook: {
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'web.facebook.com',
    'mbasic.facebook.com',
    'fb.watch',
    'fb.com',
    'www.fb.com',
  },
  Platform2.x: {'x.com', 'www.x.com', 'twitter.com', 'www.twitter.com', 'mobile.twitter.com'},
};
const _ttShortHosts = {'vm.tiktok.com', 'vt.tiktok.com'};

/// Query parameters that only track where a link was shared from.
const _tracking = {
  'fbclid',
  'gclid',
  'igsh',
  'igshid',
  'si',
  'feature',
  'ref',
  'ref_src',
  'ref_url',
  'mibextid',
  'rdid',
  'share_id',
  'share_url',
  'sfnsn',
  'is_from_webapp',
  'sender_device',
  'web_id',
};

Platform2 platformOfHost(String host) {
  host = host.toLowerCase();
  for (final e in _hosts.entries) {
    if (e.value.contains(host)) return e.key;
  }
  return Platform2.other;
}

Uri? _parse(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null || !(u.isScheme('https') || u.isScheme('http')) || u.host.isEmpty || !u.host.contains('.')) return null;
  return u;
}

final _urlRe = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
final _trailing = RegExp(r'[).,!?]+$');

/// The link in shared text: a known platform's link if there is one,
/// otherwise the first web link. Null when the text holds no link.
String? extractUrl(String? text) {
  if (text == null) return null;
  String? first;
  for (final m in _urlRe.allMatches(text)) {
    final raw = m[0]!.replaceFirst(_trailing, '');
    final u = _parse(raw);
    if (u == null) continue;
    if (platformOfHost(u.host) != Platform2.other) return raw;
    first ??= raw;
  }
  return first;
}

/// Every distinct link in [text], normalized, in order.
List<LinkInfo> extractLinks(String? text) {
  if (text == null) return const [];
  final seen = <String>{};
  final out = <LinkInfo>[];
  for (final m in _urlRe.allMatches(text)) {
    final link = canonicalize(m[0]!.replaceFirst(_trailing, ''));
    if (link != null && seen.add(link.url)) out.add(link);
  }
  return out;
}

/// [u] without tracking parameters or fragment; [keep] limits the query to
/// those names when given.
String _clean(Uri u, {String? host, Set<String>? keep}) {
  final q = <String, String>{
    for (final e in u.queryParameters.entries)
      if (keep != null ? keep.contains(e.key) : !(_tracking.contains(e.key) || e.key.startsWith('utm_')))
        e.key: e.value,
  };
  return Uri(
    scheme: 'https',
    host: host ?? u.host.toLowerCase(),
    path: u.path,
    queryParameters: q.isEmpty ? null : q,
  ).toString();
}

/// Normalizes a link so the same post always has the same URL.
/// Null only when [raw] is not a web link at all.
LinkInfo? canonicalize(String raw) {
  final u = _parse(raw);
  if (u == null) return null;
  final host = u.host.toLowerCase();
  final platform = platformOfHost(host);
  final seg = u.pathSegments.where((s) => s.isNotEmpty).toList();

  switch (platform) {
    case Platform2.instagram:
      final i = seg.indexWhere(const {'p', 'reel', 'reels', 'tv'}.contains);
      if (i >= 0 && i + 1 < seg.length && seg.first != 'share') {
        final kind = seg[i] == 'reels' ? 'reel' : seg[i];
        return LinkInfo(platform: platform, url: 'https://www.instagram.com/$kind/${seg[i + 1]}/');
      }
      return LinkInfo(
        platform: platform,
        url: 'https://www.instagram.com/${seg.join('/')}${seg.isEmpty ? '' : '/'}',
        needsResolve: (seg.isNotEmpty && seg.first == 'share') || host == 'instagr.am',
      );

    case Platform2.tiktok:
      if (_ttShortHosts.contains(host) || (seg.isNotEmpty && seg.first == 't')) {
        return LinkInfo(platform: platform, url: 'https://$host/${seg.join('/')}', needsResolve: true);
      }
      if (seg.length >= 3 && seg[0].startsWith('@') && const {'video', 'photo'}.contains(seg[1])) {
        return LinkInfo(
          platform: platform,
          url: 'https://www.tiktok.com/${seg[0]}/${seg[1]}/${seg[2]}',
          author: seg[0].substring(1).toLowerCase(),
        );
      }
      return LinkInfo(platform: platform, url: 'https://www.tiktok.com/${seg.join('/')}');

    case Platform2.youtube:
      final id = youtubeId(u);
      if (id != null) {
        final shorts = seg.isNotEmpty && seg.first == 'shorts';
        return LinkInfo(
          platform: platform,
          url: shorts ? 'https://www.youtube.com/shorts/$id' : 'https://www.youtube.com/watch?v=$id',
        );
      }
      return LinkInfo(
        platform: platform,
        url: _clean(u, host: 'www.youtube.com', keep: const {'list'}),
      );

    case Platform2.facebook:
      if (host == 'fb.watch') {
        return LinkInfo(
          platform: platform,
          url: _clean(u, keep: const {}),
          needsResolve: true,
        );
      }
      return LinkInfo(
        platform: platform,
        url: _clean(u, host: 'www.facebook.com', keep: const {'v', 'story_fbid', 'id', 'fbid'}),
        needsResolve: seg.isNotEmpty && seg.first == 'share',
      );

    case Platform2.x:
      final author = seg.length >= 3 && seg[1] == 'status' ? seg[0].toLowerCase() : null;
      return LinkInfo(
        platform: platform,
        url: author != null ? 'https://x.com/${seg[0]}/status/${seg[2]}' : _clean(u, host: 'x.com'),
        author: author,
      );

    case Platform2.other:
      return LinkInfo(platform: platform, url: _clean(u));
  }
}

/// The video id in a YouTube link of any shape, if it has one.
String? youtubeId(Uri u) {
  final seg = u.pathSegments.where((s) => s.isNotEmpty).toList();
  String? id;
  if (u.host.toLowerCase() == 'youtu.be') {
    id = seg.isEmpty ? null : seg.first;
  } else if (seg.isNotEmpty && seg.first == 'watch') {
    id = u.queryParameters['v'];
  } else if (seg.length >= 2 && const {'shorts', 'live', 'embed', 'v'}.contains(seg.first)) {
    id = seg[1];
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id) ? id : null;
}

/// What to call the place a post came from: the platform, or the site's name.
String sourceLabel(Platform2 platform, String url) {
  if (platform != Platform2.other) return platform.label;
  final host = Uri.tryParse(url)?.host ?? '';
  return host.isEmpty ? 'Web' : host.replaceFirst(RegExp(r'^(www|m|mobile)\.'), '');
}

final _hashtagRe = RegExp(r'#([\p{L}\p{N}_]+)', unicode: true);

List<String> hashtagsOf(String? text) =>
    text == null ? const [] : _hashtagRe.allMatches(text).map((m) => m[1]!.toLowerCase()).toSet().toList();
