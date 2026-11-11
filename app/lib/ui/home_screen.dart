import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../models.dart';
import '../services/link_parser.dart';
import '../share/share_sheet.dart';
import 'account_screen.dart';
import 'dialogs.dart';
import 'folder_screen.dart';
import 'folder_sheets.dart';
import 'logo.dart';
import 'post_details.dart';
import 'post_card.dart';
import 'reorder_screen.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'tidy_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});
  final Store store;

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _folderActions(BuildContext context, Folder folder) async {
    if (folder.isUnsorted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '${folder.emoji}  ${folder.name}',
              subtitle: '${folder.count} ${folder.count == 1 ? 'post' : 'posts'}',
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename, emoji and color'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert_rounded),
              title: const Text('Reorder folders'),
              onTap: () => Navigator.pop(context, 'reorder'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
              title: Text('Delete folder', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        await editFolderFlow(context, store, folder);
      case 'reorder':
        _push(context, ReorderScreen(store: store));
      case 'delete':
        await deleteFolderFlow(context, store, folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final folders = store.folders;
        final total = folders.fold<int>(0, (n, f) => n + f.count);
        // Unsorted only earns a tile once something is in it.
        final visible = [
          for (final f in folders)
            if (!f.isUnsorted || f.count > 0) f,
        ];
        final empty = total == 0 && visible.isEmpty;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                await store.reload();
                await store.background();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                      child: Row(
                        children: [
                          const StashLogo(size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stash',
                                  style: theme.textTheme.headlineLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                if (!empty)
                                  Text(
                                    '$total saved ${total == 1 ? 'post' : 'posts'}',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add a link',
                            icon: const Icon(Icons.add_link_rounded),
                            onPressed: () => addLinkFlow(context, store),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            onSelected: (v) => _push(context, switch (v) {
                              'reorder' => ReorderScreen(store: store),
                              'tidy' => TidyScreen(store: store),
                              _ => AccountScreen(store: store),
                            }),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'tidy', child: Text('Tidy up with AI')),
                              PopupMenuItem(value: 'reorder', child: Text('Reorder folders')),
                              PopupMenuItem(value: 'account', child: Text('Settings')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!empty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: _SearchPill(onTap: () => _push(context, SearchScreen(store: store))),
                      ),
                    ),
                  if (!empty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _QuickTile(
                                icon: Icons.grid_view_rounded,
                                label: 'All posts',
                                count: store.total,
                                onTap: () => _push(context, FolderScreen(store: store)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickTile(
                                icon: Icons.visibility_outlined,
                                iconColor: const Color(0xFFF76B15),
                                label: 'To watch',
                                count: store.unwatched,
                                onTap: () => _push(context, FolderScreen(store: store, unwatchedOnly: true)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickTile(
                                icon: Icons.favorite_rounded,
                                iconColor: const Color(0xFFE5484D),
                                label: 'Favorites',
                                count: store.favorites,
                                onTap: () => _push(context, FolderScreen(store: store, favoritesOnly: true)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!empty && store.tags.length >= 3)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          itemCount: store.tags.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final tag = store.tags[i];
                            return ActionChip(
                              label: Text('#${tag.key}  ${tag.value}'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _push(context, FolderScreen(store: store, tag: tag.key)),
                            );
                          },
                        ),
                      ),
                    ),
                  if (empty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onCreate: () => createFolderFlow(context, store)),
                    )
                  else ...[
                    if (store.recent.length >= 3) ...[
                      const SliverToBoxAdapter(child: _SectionHeader('Recently saved')),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 150,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: store.recent.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, i) => _RecentTile(store: store, post: store.recent[i]),
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        'Folders',
                        trailing: TextButton.icon(
                          onPressed: () => createFolderFlow(context, store),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New'),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 32 + MediaQuery.paddingOf(context).bottom),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.84,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _FolderTile(
                          folder: visible[i],
                          onTap: () => _push(context, FolderScreen(store: store, folderId: visible[i].id)),
                          onLongPress: () => _folderActions(context, visible[i]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paste a link (the clipboard is offered if it holds one) and file it with
/// the same sheet the share menu uses.
Future<void> addLinkFlow(BuildContext context, Store store) async {
  String? clip;
  try {
    clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } catch (_) {}
  if (!context.mounted) return;
  final text = await promptText(
    context,
    title: 'Add a link',
    message: 'Paste a video or post link. A folder someone sent you from Stash works too.',
    hint: 'https://…',
    initial: extractUrl(clip) ?? '',
    confirmLabel: 'Continue',
    maxLines: 4,
    keyboardType: TextInputType.url,
  );
  if (text == null || !context.mounted) return;
  if (extractUrl(text) == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That does not look like a link')));
    return;
  }
  await Navigator.push(
    context,
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (routeContext, _, _) => ShareSheet(
        repo: store.repo,
        api: store.api,
        sharedText: text,
        onClose: () => Navigator.of(routeContext).pop(),
      ),
    ),
  );
  await store.reload();
  unawaited(store.background());
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.count, required this.onTap, this.iconColor});
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$label, $count',
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: iconColor ?? scheme.primary),
                    const Spacer(),
                    Text('$count', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Search saved posts',
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(
                  'Search, or describe what you want',
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
    child: SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.store, required this.post});
  final Store store;
  final Post post;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: postTitle(post),
    child: GestureDetector(
      onTap: () => openPost(context, store, post),
      onLongPress: () => showPostDetails(context, store, post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 112,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PostImage(url: post.thumbnailUrl, platform: post.platform),
              Positioned(left: 8, top: 8, child: PlatformBadge(post.platform, size: 22)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap, required this.onLongPress});
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${folder.name}, ${folder.count} posts',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox.expand(child: _Cover(folder: folder)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(
                children: [
                  Text(folder.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 1, 4, 0),
              child: Text(
                '${folder.count} ${folder.count == 1 ? 'post' : 'posts'}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collage of the folder's newest thumbnails; the emoji on its color when empty.
class _Cover extends StatelessWidget {
  const _Cover({required this.folder});
  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final covers = folder.covers;
    final tint = folderColor(folder.color);
    if (covers.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.12)],
          ),
        ),
        child: Center(child: Text(folder.emoji, style: const TextStyle(fontSize: 46))),
      );
    }
    const gap = 3.0;
    Widget img(int i) => PostImage(url: covers[i], iconSize: 22);
    if (covers.length == 1) return img(0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: img(0)),
        const SizedBox(width: gap),
        Expanded(
          flex: 2,
          child: covers.length == 2
              ? img(1)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: img(1)),
                    const SizedBox(height: gap),
                    Expanded(child: img(2)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Text(
              n,
              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save your first post', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          step('1', 'Open a video in Instagram, TikTok, YouTube or Facebook'),
          step('2', 'Tap Share, then choose Stash'),
          step('3', 'Tap Save. Stash picks the folder'),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create a folder'),
          ),
        ],
      ),
    );
  }
}
