import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'post_card.dart';
import 'widgets.dart';

/// Everything about one saved post, with its actions: the cover, who posted
/// it, the AI summary, the original caption, your note.
Future<void> showPostDetails(BuildContext context, Store store, Post post) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => _PostDetails(
    store: store,
    post: post,
    // Actions run against the screen underneath, after the sheet has closed.
    onAction: (action) {
      Navigator.pop(sheetContext);
      runPostAction(context, store, post, action);
    },
  ),
);

class _PostDetails extends StatelessWidget {
  const _PostDetails({required this.store, required this.post, required this.onAction});
  final Store store;
  final Post post;
  final ValueChanged<PostAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final folder = store.folderById(post.folderId);
    final caption = post.caption?.trim();

    Widget label(String text, {IconData? icon}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: scheme.primary), const SizedBox(width: 5)],
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: icon != null ? scheme.primary : muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 112,
                    height: 140,
                    child: PostImage(url: post.thumbnailUrl, platform: post.platform, iconSize: 34),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PlatformBadge(post.platform, size: 22),
                          const SizedBox(width: 8),
                          Text(post.platform.label, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.author != null ? '@${post.author}' : '${post.platform.label} post',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(_savedLabel(post.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                      const SizedBox(height: 12),
                      if (folder != null)
                        Material(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onAction(PostAction.move),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(folder.emoji, style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      folder.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(Icons.expand_more_rounded, size: 18, color: muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (post.aiDescription != null) ...[
              const SizedBox(height: 20),
              label('AI summary', icon: Icons.auto_awesome_rounded),
              Text(post.aiDescription!, style: theme.textTheme.titleMedium?.copyWith(height: 1.35)),
            ],
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: 18),
              label('Caption'),
              Text(
                caption,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.4),
              ),
            ],
            const SizedBox(height: 18),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onAction(PostAction.note),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined, size: 20, color: muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          post.note ?? 'Add a note',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: post.note == null ? muted : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => onAction(PostAction.open),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text('Open in ${post.platform.label}'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Action(icon: Icons.drive_file_move_outline, label: 'Move', onTap: () => onAction(PostAction.move)),
                _Action(icon: Icons.link_rounded, label: 'Copy link', onTap: () => onAction(PostAction.copy)),
                _Action(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: scheme.error,
                  onTap: () => onAction(PostAction.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Saved today", "Saved 3 days ago", "Saved on 29 Oct".
String _savedLabel(DateTime d) {
  final text = formatDate(d);
  return RegExp(r'^\d+ [A-Z]').hasMatch(text) ? 'Saved on $text' : 'Saved ${text.toLowerCase()}';
}
