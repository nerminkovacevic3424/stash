import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'folder_sheets.dart';
import 'post_card.dart';
import 'widgets.dart';

/// A grid of saved posts: one folder, or (with no [folderId]) every post,
/// optionally narrowed to favorites.
class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.store, this.folderId, this.favoritesOnly = false});
  final Store store;
  final String? folderId;
  final bool favoritesOnly;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Post>? _posts;
  List<Platform2> _platforms = const [];
  Platform2? _platform;

  Store get store => widget.store;
  bool? get _favorite => widget.favoritesOnly ? true : null;

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
    final platforms = await store.repo.platforms(folderId: widget.folderId, favorite: _favorite);
    // A filter whose last post was moved away would otherwise show nothing.
    if (_platform != null && !platforms.contains(_platform)) _platform = null;
    final posts = await store.repo.posts(folderId: widget.folderId, platform: _platform, favorite: _favorite);
    if (mounted) {
      setState(() {
        _platforms = platforms;
        _posts = posts;
      });
    }
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
    final title = folder?.name ?? (widget.favoritesOnly ? 'Favorites' : 'All posts');

    final Widget avatar = folder != null
        ? FolderAvatar(emoji: folder.emoji, color: folder.color, size: 40)
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(
              widget.favoritesOnly ? Icons.favorite_rounded : Icons.grid_view_rounded,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          );

    return Scaffold(
      appBar: AppBar(
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
          if (folder != null && !folder.isUnsorted)
            PopupMenuButton<String>(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (v) async {
                if (v == 'edit') {
                  await editFolderFlow(context, store, folder);
                } else if (await deleteFolderFlow(context, store, folder) && context.mounted) {
                  Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Rename, emoji and color')),
                PopupMenuItem(value: 'delete', child: Text('Delete folder')),
              ],
            ),
        ],
      ),
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
                                      ? PostTile(
                                          key: ValueKey(posts[r * columns + c].id),
                                          store: store,
                                          post: posts[r * columns + c],
                                        )
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
    );
  }
}
