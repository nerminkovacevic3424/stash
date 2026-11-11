import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/pending_queue.dart';
import '../services/suggester.dart';
import '../services/sync.dart';
import 'repo.dart';

/// App-wide state for the main app. Screens listen to it and re-query on change.
class Store extends ChangeNotifier {
  Store(this.repo, {String? backendUrl, Api? api}) : api = api ?? Api(baseUrl: backendUrl) {
    suggester = Suggester(repo, this.api);
    queue = PendingQueue(repo, this.api, suggester);
    sync = SyncService(repo);
    auth = Auth(repo);
  }

  final Repo repo;
  final Api api;
  late final Suggester suggester;
  late final PendingQueue queue;
  late final SyncService sync;
  late final Auth auth;

  List<Folder> folders = const [];

  /// The newest saves across all folders, for the home screen.
  List<Post> recent = const [];

  /// Platforms with at least one saved post, most used first.
  List<Platform2> platforms = const [];
  int total = 0;
  int favorites = 0;
  int unwatched = 0;

  /// Most used AI tags with their post counts.
  List<MapEntry<String, int>> tags = const [];

  Folder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Re-reads from disk. The share sheet writes from another process, so call
  /// this whenever the app comes back to the foreground.
  Future<void> reload() async {
    folders = await repo.folders();
    recent = await repo.posts(limit: 12);
    platforms = await repo.platforms();
    final (all, fav, todo) = await repo.counts();
    total = all;
    favorites = fav;
    unwatched = todo;
    tags = await repo.topTags();
    notifyListeners();
  }

  /// Runs a write, refreshes the UI, then syncs in the background.
  Future<void> mutate(Future<void> Function() write) async {
    await write();
    await reload();
    unawaited(background());
  }

  /// Pending metadata/suggestions, then cloud sync. Safe to call often.
  Future<void> background() async {
    var changed = false;
    try {
      changed = await queue.process();
      changed = await sync.sync() || changed;
    } catch (e) {
      debugPrint('background work failed: $e');
    }
    if (changed) await reload();
  }

  /// Moving a post by hand teaches the suggester, like an override in the share sheet.
  Future<void> movePost(Post post, String folderId) => mutate(() async {
    await repo.movePosts([post.id], folderId);
    await suggester.learnFromChoice(
      platform: post.platform,
      chosenFolderId: folderId,
      suggested: null,
      author: post.author,
      caption: post.caption,
    );
    await repo.setKv('last_folder', folderId);
  });
}
