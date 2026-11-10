import '../models.dart';

// The same rules live in backend/lib/urls.js and
// ios/StashShare/LinkParser.swift — keep the three in sync.

const _igHosts = {'instagram.com', 'www.instagram.com', 'm.instagram.com', 'instagr.am'};
const _ttHosts = {'tiktok.com', 'www.tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'};
const _ttShortHosts = {'vm.tiktok.com', 'vt.tiktok.com'};

Platform2? _platformOf(String host) {
  if (_igHosts.contains(host)) return Platform2.instagram;
  if (_ttHosts.contains(host)) return Platform2.tiktok;
  return null;
}

Uri? _parse(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null || !(u.isScheme('https') || u.isScheme('http')) || u.host.isEmpty) return null;
  return u;
}

final _urlRe = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
final _trailing = RegExp(r'[).,!?]+$');

/// First Instagram/TikTok URL in the shared text, or null.
String? extractUrl(String? text) {
  if (text == null) return null;
  for (final m in _urlRe.allMatches(text)) {
    final raw = m[0]!.replaceFirst(_trailing, '');
    final u = _parse(raw);
    if (u != null && _platformOf(u.host.toLowerCase()) != null) return raw;
  }
  return null;
}

/// Normalizes a post URL; null if it is not an Instagram/TikTok link.
LinkInfo? canonicalize(String raw) {
  final u = _parse(raw);
  if (u == null) return null;
  final host = u.host.toLowerCase();
  final platform = _platformOf(host);
  if (platform == null) return null;
  final seg = u.pathSegments.where((s) => s.isNotEmpty).toList();

  if (platform == Platform2.instagram) {
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
  }

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
}

final _hashtagRe = RegExp(r'#([\p{L}\p{N}_]+)', unicode: true);

List<String> hashtagsOf(String? text) =>
    text == null ? const [] : _hashtagRe.allMatches(text).map((m) => m[1]!.toLowerCase()).toSet().toList();
