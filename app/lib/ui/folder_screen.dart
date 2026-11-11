import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'folder_sheets.dart';
import 'post_card.dart';
import 'widgets.dart';

/// A grid of saved posts: one folder, or (with no [folderId]) every post,
/// optionally narrowed to favorites, not-yet-watched posts or one tag.
///
/// Long-press a post to start selecting; the top bar then acts on the whole
/// selection.
class FolderScreen extends StatefulWidget {
  const FolderScreen({
    super.key,
    required this.store,
    this.folderId,
    this.favoritesOnly = false,
    this.unwatchedOnly = false,
    this.tag,
  });
  final Store store;
  final String? folderId;
  final bool favoritesOnly;
  final bool unwatchedOnly;
  final String? tag;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Post>? _posts;
  List<Platform2> _platforms = const [];
  Platform2? _platform;
  final _selected = <String>{};

  Store get store => widget.store;
  bool? get _favorite => widget.favoritesOnly ? true : null;
  bool? get _watched => widget.unwatchedOnly ? false : null;
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    store.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = store.repo;
    final platforms = await repo.platforms(
      folderId: widget.folderId,
      favorite: _favorite,
      watched: _watched,
      tag: widget.tag,
    );
    // A filter whose last post was moved away would otherwise show nothing.
    if (_platform != null && !platforms.contains(_platform)) _platform = null;
    final posts = await repo.posts(
      folderId: widget.folderId,
      platform: _platform,
      favorite: _favorite,
      watched: _watched,
      tag: widget.tag,
    );
    if (mounted) {
      setState(() {
        _platforms = platforms;
        _posts = posts;
        _selected.retainAll(posts.map((p) => p.id));
      });
    }
  }

  void _toggle(Post post) =>
      setState(() => _selected.contains(post.id) ? _selected.remove(post.id) : _selected.add(post.id));

  /// Runs a bulk change on the selection, then leaves selection mode.
  Future<void> _bulk(Future<void> Function(List<String> ids) change, String done) async {
    final ids = _selected.toList();
    await store.mutate(() => change(ids));
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _moveSelected() async {
    final n = _selected.length;
    final target = await pickFolder(context, store);
    if (target == null) return;
    await _bulk((ids) => store.repo.movePosts(ids, target.id), 'Moved $n to ${target.name}');
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $n saved ${n == 1 ? 'post' : 'posts'}?'),
        content: const Text('They are removed from Stash only. The original posts are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _bulk(store.repo.deletePosts, 'Deleted $n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = widget.folderId == null ? null : store.folderById(widget.folderId!);
    if (widget.folderId != null && folder == null) {
      // Deleted (here or on another device) while open.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This folder no longer exists')),
      );
    }
    final posts = _posts;
    final count = folder?.count ?? posts?.length ?? 0;
    final (String title, IconData icon) = widget.tag != null
        ? ('#${widget.tag}', Icons.tag_rounded)
        : widget.favoritesOnly
        ? ('Favorites', Icons.favorite_rounded)
        : widget.unwatchedOnly
        ? ('To watch', Icons.visibility_outlined)
        : (folder?.name ?? 'All posts', Icons.grid_view_rounded);

    final Widget avatar = folder != null
        ? FolderAvatar(emoji: folder.emoji, color: folder.color, size: 40)
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          );

    final AppBar appBar = _selecting
        ? AppBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_selected.clear),
            ),
            title: Text('${_selected.length} selected'),
            actions: [
              IconButton(tooltip: 'Move', icon: const Icon(Icons.drive_file_move_outline), onPressed: _moveSelected),
              IconButton(
                tooltip: 'Mark as watched',
                icon: const Icon(Icons.check_circle_outline_rounded),
                onPressed: () => _bulk((ids) => store.repo.setWatched(ids, true), 'Marked as watched'),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                onPressed: _deleteSelected,
              ),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (v) {
                  if (v == 'all') {
                    setState(() => _selected.addAll((posts ?? const <Post>[]).map((p) => p.id)));
                  } else {
                    _bulk((ids) => store.repo.setFavorites(ids, true), 'Added to favorites');
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'all', child: Text('Select all')),
                  PopupMenuItem(value: 'favorite', child: Text('Add to favorites')),
                ],
              ),
            ],
          )
        : AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '$count ${count == 1 ? 'post' : 'posts'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (folder != null)
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (v) async {
                    if (v == 'send') {
                      await sendFolder(context, store, folder);
                    } else if (v == 'edit') {
                      await editFolderFlow(context, store, folder);
                    } else if (await deleteFolderFlow(context, store, folder) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'send', child: Text('Send folder to someone')),
                    if (!folder.isUnsorted) ...const [
                      PopupMenuItem(value: 'edit', child: Text('Rename, emoji and color')),
                      PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                    ],
                  ],
                ),
            ],
          );

    return PopScope(
      // Back leaves selection mode before it leaves the screen.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: appBar,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlatformFilter(
              value: _platform,
              options: _platforms,
              onChanged: (p) {
                _platform = p;
                _load();
              },
            ),
            Expanded(
              child: posts == null
                  ? const SizedBox.shrink()
                  : posts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          widget.favoritesOnly
                              ? 'No favorites yet. Open a post\'s details and tap the heart.'
                              : widget.unwatchedOnly
                              ? 'All caught up. Everything you saved has been opened.'
                              : 'No posts here yet. Share a video or post to Stash to save it.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, box) {
                        // Two columns on phones, more on wide screens. Rows size to
                        // their content so a description can be expanded in place.
                        final columns = (box.maxWidth / 240).ceil().clamp(2, 6);
                        final rows = (posts.length / columns).ceil();
                        return ListView.builder(
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
                          itemCount: rows,
                          itemBuilder: (_, r) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var c = 0; c < columns; c++) ...[
                                  if (c > 0) const SizedBox(width: 14),
                                  Expanded(
                                    child: r * columns + c < posts.length
                                        ? _tile(posts[r * columns + c])
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Post post) => PostTile(
    key: ValueKey(post.id),
    store: store,
    post: post,
    selected: _selecting ? _selected.contains(post.id) : null,
    onSelect: () => _toggle(post),
  );
}
