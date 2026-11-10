const unsortedId = 'unsorted';

enum Platform2 {
  instagram('Instagram'),
  tiktok('TikTok');

  const Platform2(this.label);
  final String label;

  static Platform2 parse(String? s) => s == 'tiktok' ? tiktok : instagram;
}

class Folder {
  Folder({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.sortOrder,
    this.count = 0,
    this.covers = const [],
  });

  final String id;
  final String name;
  final String emoji;

  /// Index into [folderColors] in ui/theme.dart.
  final int color;
  final int sortOrder;
  final int count;

  /// Thumbnails of the newest posts (up to three), newest first.
  final List<String> covers;

  bool get isUnsorted => id == unsortedId;

  factory Folder.fromRow(Map<String, Object?> r, {List<String> covers = const []}) => Folder(
    id: r['id'] as String,
    name: r['name'] as String,
    emoji: r['emoji'] as String,
    color: r['color'] as int,
    sortOrder: r['sort_order'] as int,
    count: (r['cnt'] as int?) ?? 0,
    covers: covers,
  );
}

class Post {
  Post({
    required this.id,
    required this.url,
    required this.sourceUrl,
    required this.platform,
    required this.folderId,
    required this.createdAt,
    this.author,
    this.authorName,
    this.caption,
    this.thumbnailUrl,
    this.note,
    this.aiDescription,
    this.metaStatus = 0,
    this.needsSuggestion = false,
  });

  final String id;

  /// Canonical post URL (short links are replaced once resolved).
  final String url;

  /// The URL exactly as it was shared, kept for duplicate detection.
  final String sourceUrl;
  final Platform2 platform;
  final String folderId;
  final DateTime createdAt;
  final String? author;
  final String? authorName;
  final String? caption;
  final String? thumbnailUrl;
  final String? note;

  /// One-sentence summary written by the AI from the caption and cover image.
  final String? aiDescription;

  /// 0 = metadata still to fetch, 1 = fetched, 2 = gave up.
  final int metaStatus;
  final bool needsSuggestion;

  factory Post.fromRow(Map<String, Object?> r) => Post(
    id: r['id'] as String,
    url: r['url'] as String,
    sourceUrl: r['source_url'] as String,
    platform: Platform2.parse(r['platform'] as String?),
    folderId: r['folder_id'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    author: r['author'] as String?,
    authorName: r['author_name'] as String?,
    caption: r['caption'] as String?,
    thumbnailUrl: r['thumbnail_url'] as String?,
    note: r['note'] as String?,
    aiDescription: r['ai_description'] as String?,
    metaStatus: r['meta_status'] as int,
    needsSuggestion: r['needs_suggestion'] == 1,
  );
}

/// A parsed share-sheet link.
class LinkInfo {
  const LinkInfo({required this.platform, required this.url, this.author, this.needsResolve = false});
  final Platform2 platform;
  final String url;
  final String? author;
  final bool needsResolve;
}

/// Preview metadata returned by the backend.
class PostMeta {
  const PostMeta({
    required this.url,
    required this.resolved,
    this.author,
    this.authorName,
    this.caption,
    this.thumbnailUrl,
    this.hashtags = const [],
    this.ok = false,
  });

  final String url;
  final bool resolved;
  final String? author;
  final String? authorName;
  final String? caption;
  final String? thumbnailUrl;
  final List<String> hashtags;

  /// False when the backend reached the platform but got nothing useful back.
  final bool ok;

  factory PostMeta.fromJson(Map<String, dynamic> j) => PostMeta(
    url: j['url'] as String,
    resolved: j['resolved'] != false,
    author: j['author'] as String?,
    authorName: j['authorName'] as String?,
    caption: j['caption'] as String?,
    thumbnailUrl: j['thumbnailUrl'] as String?,
    hashtags: ((j['hashtags'] as List?) ?? const []).cast<String>(),
    ok: j['ok'] == true,
  );
}

enum SuggestionSource { author, keywords, ai, lastUsed, unsorted }

/// Either an existing folder ([folderId]) or a proposed new one ([newName]).
class FolderSuggestion {
  const FolderSuggestion.existing(String this.folderId, this.source) : newName = null, newEmoji = null;
  const FolderSuggestion.create(String this.newName, String this.newEmoji)
    : folderId = null,
      source = SuggestionSource.ai;

  final String? folderId;
  final String? newName;
  final String? newEmoji;
  final SuggestionSource source;

  bool get isFallback => source == SuggestionSource.lastUsed || source == SuggestionSource.unsorted;
}

/// What the backend's AI returned for one post.
class AiAnswer {
  const AiAnswer({this.suggestion, this.description});
  static const empty = AiAnswer();

  final FolderSuggestion? suggestion;
  final String? description;
}
