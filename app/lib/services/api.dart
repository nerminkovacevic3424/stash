import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';

/// Thrown when the backend could not be reached (offline, timeout, 5xx).
class Unreachable implements Exception {}

/// kv key holding a server address entered in Settings.
const backendUrlKey = 'backend_url';

class Api {
  Api({http.Client? client, String? baseUrl}) : _client = client ?? http.Client() {
    this.baseUrl = baseUrl ?? Config.backendUrl;
  }

  final http.Client _client;
  String _base = '';

  /// Where the backend lives. Set at build time, or changed in Settings
  /// (stored under [backendUrlKey]) so one build can point at any server.
  String get baseUrl => _base;
  set baseUrl(String value) {
    final v = value.trim();
    _base = (v.isEmpty ? Config.backendUrl : v).replaceFirst(RegExp(r'/+$'), '');
  }

  /// True when the server answers its health check.
  Future<bool> ping() async {
    try {
      final res = await _client.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, Object?> body, Duration timeout) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_base$path'),
            headers: {'content-type': 'application/json', if (Config.appKey.isNotEmpty) 'x-app-key': Config.appKey},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw Unreachable();
    }
    if (res.statusCode >= 500 || res.statusCode == 429) throw Unreachable();
    if (res.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    return json is Map<String, dynamic> ? json : null;
  }

  /// Resolves short links and fetches preview metadata.
  Future<PostMeta?> metadata(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    final j = await _post('/v1/metadata', {'url': url}, timeout);
    return j == null ? null : PostMeta.fromJson(j);
  }

  /// Asks the LLM for a folder. Null when it has no opinion.
  Future<FolderSuggestion?> suggest({
    required Platform2 platform,
    required String? author,
    required String? caption,
    required List<String> hashtags,
    required List<Folder> folders,
    required Map<String, List<String>> examples,
    required List<Map<String, String>> hints,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final j = await _post('/v1/suggest', {
      'platform': platform.name,
      'author': author,
      'caption': caption,
      'hashtags': hashtags,
      'folders': [
        for (final f in folders)
          if (!f.isUnsorted) {'id': f.id, 'name': f.name, 'examples': examples[f.id] ?? const <String>[]},
      ],
      'hints': hints,
    }, timeout);
    final s = j?['suggestion'];
    if (s is! Map) return null;
    if (s['kind'] == 'existing' && folders.any((f) => f.id == s['folderId'])) {
      return FolderSuggestion.existing(s['folderId'] as String, SuggestionSource.ai);
    }
    if (s['kind'] == 'new' && s['name'] is String) {
      return FolderSuggestion.create(s['name'] as String, (s['emoji'] as String?) ?? '📁');
    }
    return null;
  }
}
