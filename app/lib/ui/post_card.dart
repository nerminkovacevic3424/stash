import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';
import '../models.dart';
import 'folder_sheets.dart';
import 'widgets.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return '${d.day} ${_months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

String _title(Post post) => post.author != null ? '@${post.author}' : '${post.platform.label} post';

String? _caption(Post post) {
  final c = post.caption?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return c == null || c.isEmpty ? null : c;
}

/// Opens the original post. The https link is a universal/app link, so the
/// Instagram or TikTok app takes it when installed; otherwise the browser does.
Future<void> openPost(BuildContext context, Post post) async {
  final uri = Uri.parse(post.url);
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this post')));
  }
}

enum PostAction { open, move, note, copy, delete }

Future<void> runPostAction(BuildContext context, Store store, Post post, PostAction action) async {
  switch (action) {
    case PostAction.open:
      await openPost(context, post);
    case PostAction.move:
      final target = await pickFolder(context, store, currentId: post.folderId);
      if (target == null) return;
      await store.movePost(post, target.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to ${target.name}')));
      }
    case PostAction.note:
      final note = await _editNote(context, post);
      if (note != null) await store.mutate(() => store.repo.setNote(post.id, note));
    case PostAction.copy:
      await Clipboard.setData(ClipboardData(text: post.url));
    case PostAction.delete:
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this saved post?'),
          content: const Text('It is removed from Stash only. The original post is not affected.'),
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
      if (ok == true) await store.mutate(() => store.repo.deletePost(post.id));
  }
}

Future<String?> _editNote(BuildContext context, Post post) {
  final controller = TextEditingController(text: post.note ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Why did you save this?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
}

class _PostMenu extends StatelessWidget {
  const _PostMenu({required this.store, required this.post, required this.child});
  final Store store;
  final Post post;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopupMenuButton<PostAction>(
    tooltip: 'Post actions',
    padding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    onSelected: (a) => runPostAction(context, store, post, a),
    itemBuilder: (_) => const [
      PopupMenuItem(value: PostAction.open, child: Text('Open original')),
      PopupMenuItem(value: PostAction.move, child: Text('Move to…')),
      PopupMenuItem(value: PostAction.note, child: Text('Edit note')),
      PopupMenuItem(value: PostAction.copy, child: Text('Copy link')),
      PopupMenuItem(value: PostAction.delete, child: Text('Delete')),
    ],
    child: child,
  );
}

/// Visual card for folder grids: tall thumbnail with the author over it,
/// caption and date underneath.
class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.store, required this.post});
  final Store store;
  final Post post;

  /// Height of the text block under the image.
  static const textHeight = 66.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final caption = _caption(post);

    return Semantics(
      button: true,
      label: '${_title(post)}. ${caption ?? ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openPost(context, post),
        onLongPress: () => runPostAction(context, store, post, PostAction.move),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PostImage(url: post.thumbnailUrl, iconSize: 40),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 72,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: 10, top: 10, child: PlatformBadge(post.platform, size: 26)),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _PostMenu(
                        store: store,
                        post: post,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(color: Color(0x59000000), shape: BoxShape.circle),
                          child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Text(
                        _title(post),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: textHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption ?? (post.metaStatus == 0 ? 'Preview loads when you are online' : 'No caption'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.3,
                        fontSize: 13,
                        color: caption == null ? muted : theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(formatDate(post.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                        if (post.note != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.sticky_note_2_outlined, size: 13, color: muted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row, used for search results.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.store, required this.post, this.showFolder = false});
  final Store store;
  final Post post;

  /// Search results show which folder each post lives in.
  final bool showFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final folder = showFolder ? store.folderById(post.folderId) : null;
    final caption = _caption(post);

    return InkWell(
      onTap: () => openPost(context, post),
      onLongPress: () => runPostAction(context, store, post, PostAction.move),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PostThumb(url: post.thumbnailUrl, platform: post.platform, size: 76, radius: 16),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(post),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption ?? (post.metaStatus == 0 ? 'Preview loads when you are online' : post.url),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                  ),
                  if (post.note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${post.note}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [formatDate(post.createdAt), if (folder != null) '${folder.emoji} ${folder.name}'].join('  ·  '),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            _PostMenu(
              store: store,
              post: post,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.more_vert_rounded, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All / Instagram / TikTok.
class PlatformFilter extends StatelessWidget {
  const PlatformFilter({super.key, required this.value, required this.onChanged});
  final Platform2? value;
  final ValueChanged<Platform2?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          for (final (p, label) in [(null, 'All'), (Platform2.instagram, 'Instagram'), (Platform2.tiktok, 'TikTok')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: value == p,
                child: Material(
                  color: value == p ? scheme.onSurface : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onChanged(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: value == p ? scheme.surface : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
