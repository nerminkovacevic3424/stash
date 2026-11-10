import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'folder_sheets.dart';
import 'post_card.dart';
import 'widgets.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.store, required this.folderId});
  final Store store;
  final String folderId;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<Post>? _posts;
  Platform2? _platform;

  Store get store => widget.store;

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
    final posts = await store.repo.posts(folderId: widget.folderId, platform: _platform);
    if (mounted) setState(() => _posts = posts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = store.folderById(widget.folderId);
    if (folder == null) {
      // Deleted (here or on another device) while open.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This folder no longer exists')),
      );
    }
    final posts = _posts;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            FolderAvatar(emoji: folder.emoji, color: folder.color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${folder.count} ${folder.count == 1 ? 'post' : 'posts'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!folder.isUnsorted)
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
                        _platform == null
                            ? 'No posts here yet. Share one from Instagram or TikTok.'
                            : 'No ${_platform!.label} posts in this folder.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      // Two columns on phones, more on wide screens; thumbnails stay 4:5.
                      final columns = (box.maxWidth / 240).ceil().clamp(2, 6);
                      final width = (box.maxWidth - 40 - 14 * (columns - 1)) / columns;
                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.paddingOf(context).bottom),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: width * 1.25 + PostTile.textHeight,
                        ),
                        itemCount: posts.length,
                        itemBuilder: (_, i) => PostTile(key: ValueKey(posts[i].id), store: store, post: posts[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
