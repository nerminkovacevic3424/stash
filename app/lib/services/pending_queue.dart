import '../data/repo.dart';
import 'api.dart';
import 'suggester.dart';

/// Finishes work the share sheet could not do in its 1.5 seconds:
///
///  * posts saved offline (or before the preview loaded) get their metadata;
///  * every post gets an AI description;
///  * posts that were filed into a fallback folder are sorted by content,
///    into an existing folder or a new one the AI proposes.
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

      for (final post in await repo.pendingAi()) {
        final answer = await suggester.ai(
          platform: post.platform,
          author: post.author,
          caption: post.caption,
          thumbnailUrl: post.thumbnailUrl,
        );
        await repo.setAi(post.id, answer.description);
        if (answer.description != null) changed = true;

        if (post.needsSuggestion) {
          // What the user taught us wins over the AI's opinion.
          final s =
              await suggester.local(
                platform: post.platform,
                author: post.author,
                caption: post.caption,
                excludePostId: post.id,
              ) ??
              answer.suggestion;
          final target = s == null
              ? null
              : s.folderId ?? (await repo.createFolder(s.newName!, emoji: s.newEmoji ?? '📁')).id;
          if (target != null && target != post.folderId) {
            await repo.movePosts([post.id], target);
            changed = true;
          }
          await repo.clearNeedsSuggestion(post.id);
        }
      }
    } on Unreachable {
      // Still offline; try again next time.
    } finally {
      _running = false;
    }
    return changed;
  }
}
