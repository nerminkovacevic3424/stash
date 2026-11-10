import '../data/repo.dart';
import '../models.dart';
import 'api.dart';
import 'link_parser.dart';

const _stopwords = {
  'this',
  'that',
  'with',
  'from',
  'your',
  'have',
  'what',
  'when',
  'will',
  'just',
  'like',
  'them',
  'they',
  'then',
  'than',
  'here',
  'there',
  'about',
  'would',
  'could',
  'should',
  'into',
  'more',
  'some',
  'only',
  'really',
  'because',
  'these',
  'those',
  'being',
  'been',
  'were',
  'make',
  'made',
  'follow',
  'share',
  'comment',
  'link',
  'video',
  'reels',
  'reel',
  'tiktok',
  'instagram',
  'viral',
  'fyp',
  'foryou',
  'foryoupage',
  'explore',
  'trending',
};

final _wordRe = RegExp(r'[\p{L}]{4,}', unicode: true);

/// Keywords for learning and local matching: hashtags weigh 2, caption words 1.
Map<String, int> keywordsOf(String? caption) {
  if (caption == null || caption.isEmpty) return const {};
  final out = <String, int>{};
  for (final h in hashtagsOf(caption)) {
    if (!_stopwords.contains(h)) out[h] = 2;
  }
  final plain = caption.replaceAll(RegExp(r'[#@][\p{L}\p{N}_.]+', unicode: true), ' ').toLowerCase();
  for (final m in _wordRe.allMatches(plain)) {
    if (out.length >= 24) break;
    final w = m[0]!;
    if (!_stopwords.contains(w)) out.putIfAbsent(w, () => 1);
  }
  return out;
}

/// Implements the suggestion order: author → learned keywords → LLM → fallback.
class Suggester {
  Suggester(this.repo, this.api);
  final Repo repo;
  final Api api;

  /// Instant, offline: a correction or history for this author, then learned keywords.
  Future<FolderSuggestion?> local({
    required Platform2 platform,
    String? author,
    String? caption,
    String? excludePostId,
  }) async {
    if (author != null && author.isNotEmpty) {
      final id =
          await repo.authorRule(platform, author) ??
          await repo.authorHistory(platform, author, excludePostId: excludePostId);
      if (id != null) return FolderSuggestion.existing(id, SuggestionSource.author);
    }
    final scores = await repo.keywordScores(keywordsOf(caption).keys.toList());
    // Only trust keywords when there is real evidence and a clear winner.
    if (scores.isNotEmpty && scores.first.value >= 3 && (scores.length == 1 || scores.first.value > scores[1].value)) {
      return FolderSuggestion.existing(scores.first.key, SuggestionSource.keywords);
    }
    return null;
  }

  /// LLM pick via the backend. Throws [Unreachable] when offline.
  Future<FolderSuggestion?> ai({required Platform2 platform, String? author, String? caption}) async {
    if (caption == null || caption.trim().isEmpty) return null;
    return api.suggest(
      platform: platform,
      author: author,
      caption: caption,
      hashtags: hashtagsOf(caption),
      folders: await repo.folders(),
      examples: await repo.folderExamples(),
      hints: await repo.keywordHints(),
    );
  }

  Future<FolderSuggestion> fallback() async {
    final last = await repo.kv('last_folder');
    if (last != null && await repo.folder(last) != null) {
      return FolderSuggestion.existing(last, SuggestionSource.lastUsed);
    }
    return const FolderSuggestion.existing(unsortedId, SuggestionSource.unsorted);
  }

  /// Call after a save where the user picked the folder by hand.
  Future<void> learnFromChoice({
    required Platform2 platform,
    required String chosenFolderId,
    required FolderSuggestion? suggested,
    String? author,
    String? caption,
  }) => repo.learn(
    platform: platform,
    folderId: chosenFolderId,
    author: author,
    keywords: keywordsOf(caption),
    rejectedFolderId: suggested?.folderId,
  );
}
