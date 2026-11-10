import '../data/repo.dart';
import 'api.dart';
import 'suggester.dart';

/// Finishes work the share sheet could not: posts saved offline (or closed
/// before the preview loaded) get their metadata here, and posts that were
/// filed into a fallback folder get a real suggestion.
///
/// Run on launch, on resume and when connectivity returns.
class PendingQueue {
  PendingQueue(this.repo, this.api, this.suggester);
  final Repo repo;
  final Api api;
  final Suggester suggester;
  bool _running = false;

  /// Returns true when any post changed.
  Future<bool> process() async {
    if (_running) return false;
    _running = true;
    var changed = false;
    try {
      for (final post in await repo.pendingMeta()) {
        final meta = await api.metadata(post.url);
        if (meta == null) {
          await repo.metaFailed(post.id);
        } else {
          await repo.applyMeta(post.id, meta);
          changed = true;
        }
      }

      for (final post in await repo.pendingSuggestion()) {
        final s =
            await suggester.local(
              platform: post.platform,
              author: post.author,
              caption: post.caption,
              excludePostId: post.id,
            ) ??
            await suggester.ai(platform: post.platform, author: post.author, caption: post.caption);
        // Only ever move into a folder the user already has; never create
        // folders behind their back.
        final target = s?.folderId;
        if (target != null && target != post.folderId) {
          await repo.movePosts([post.id], target);
          changed = true;
        }
        await repo.clearNeedsSuggestion(post.id);
      }
    } on Unreachable {
      // Still offline; try again next time.
    } finally {
      _running = false;
    }
    return changed;
  }
}
