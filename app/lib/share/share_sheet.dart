import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/link_parser.dart';
import '../services/reminders.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'share_controller.dart';

const _channel = MethodChannel('stash/share');

/// Root of the Android share activity (Dart entrypoint `shareMain`).
/// The window is transparent, so the app that shared stays visible behind.
class ShareApp extends StatelessWidget {
  const ShareApp({super.key, required this.repo, this.api});
  final Repo repo;
  final Api? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    color: Colors.transparent,
    home: ShareSheet(repo: repo, api: api),
  );
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key, required this.repo, this.api, this.sharedText, this.onClose});
  final Repo repo;
  final Api? api;

  /// Overrides for tests; in the app these come from the platform channel.
  final String? sharedText;
  final VoidCallback? onClose;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late final ShareController c = ShareController(widget.repo, widget.api ?? Api());
  final _note = TextEditingController();
  final _newFolder = TextEditingController();
  bool _visible = false;
  bool _pickerOpen = false;
  bool _noteOpen = false;
  bool _creating = false;
  bool _closing = false;
  bool _reminderSet = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _visible = true));
  }

  Future<void> _start() async {
    // Wake the server and open the connection while the preview loads, so
    // the AI request that follows does not pay for either.
    unawaited(c.api.ping());
    var text = widget.sharedText;
    if (text == null) {
      try {
        text = await _channel.invokeMethod<String>('getSharedText');
      } catch (_) {}
    }
    await c.start(text);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (c.stage == ShareStage.saved && !_closing) {
      HapticFeedback.mediumImpact();
      final id = c.savedPostId;
      if (id != null && c.remindAt != null && !_reminderSet) {
        _reminderSet = true;
        unawaited(
          Reminders.schedule(
            id,
            c.remindAt!,
            title: 'Saved for later${c.author != null ? ': @${c.author}' : ''}',
            body: c.aiDescription ?? c.meta?.caption,
          ),
        );
      }
      Timer(const Duration(milliseconds: 950), _close);
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (mounted) setState(() => _visible = false);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (widget.onClose != null) return widget.onClose!();
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      await SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    _note.dispose();
    _newFolder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetColor = theme.bottomSheetTheme.backgroundColor!;
    final media = MediaQuery.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const ColoredBox(color: Color(0x73000000)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                offset: _visible ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560, maxHeight: media.size.height * 0.9),
                  child: Material(
                    color: sheetColor,
                    elevation: 12,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: media.viewInsets.bottom + media.padding.bottom),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                          child: _content(theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme) {
    final handle = Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
      ),
    );

    if (c.stage == ShareStage.saved) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          handle,
          const SizedBox(height: 12),
          Icon(Icons.check_circle_rounded, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(c.confirmation, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 28),
        ],
      );
    }

    if (c.stage == ShareStage.invalid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          handle,
          Text('Nothing to save here', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Stash saves links. Share a video or post from Instagram, TikTok, YouTube, Facebook or any site.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(onPressed: _close, child: const Text('Close')),
        ],
      );
    }

    final link = c.link;
    if (link == null) return Column(mainAxisSize: MainAxisSize.min, children: [handle, const SizedBox(height: 120)]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        handle,
        if (c.isBulk)
          _BulkPreview(count: c.bulk.length)
        else
          _Preview(link: link, meta: c.meta, loading: c.metaLoading, aiDescription: c.aiDescription),
        if (c.duplicate != null) ...[
          const SizedBox(height: 14),
          _DuplicateBanner(folderName: c.duplicateFolder?.name ?? 'your library'),
        ],
        const SizedBox(height: 18),
        _FolderChip(controller: c, open: _pickerOpen, onTap: () => setState(() => _pickerOpen = !_pickerOpen)),
        if (_pickerOpen) ...[const SizedBox(height: 12), _picker(theme)],
        const SizedBox(height: 6),
        if (_noteOpen && !c.isBulk)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: TextField(
              controller: _note,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Why are you saving this?'),
            ),
          ),
        if (!c.isBulk)
          Row(
            children: [
              if (!_noteOpen) ...[
                TextButton.icon(
                  onPressed: () => setState(() => _noteOpen = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add note'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              _remindButton(theme),
            ],
          ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: c.hasChoice && c.stage == ShareStage.ready ? () => c.save(_note.text) : null,
          child: c.stage == ShareStage.saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(_saveLabel()),
        ),
      ],
    );
  }

  Widget _remindButton(ThemeData theme) {
    final when = c.remindAt;
    return TextButton.icon(
      onPressed: () async {
        final picked = await pickReminder(context, current: when);
        if (picked == null) return;
        setState(() => c.remindAt = picked == clearReminder ? null : picked);
      },
      icon: Icon(when == null ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, size: 18),
      label: Text(when == null ? 'Remind me' : reminderLabel(when)),
      style: TextButton.styleFrom(
        foregroundColor: when == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  String _saveLabel() {
    if (c.isBulk) return 'Save ${c.bulk.length} links';
    if (c.duplicate == null) return 'Save';
    return c.duplicateInPlace ? 'Keep in ${c.choiceName}' : 'Move to ${c.choiceName}';
  }

  Widget _picker(ThemeData theme) {
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 168),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in c.folders)
              ChoiceChip(
                label: Text('${f.emoji}  ${f.name}'),
                selected: c.newName == null && c.selected?.id == f.id,
                showCheckmark: false,
                onSelected: (_) {
                  c.pick(f);
                  setState(() => _pickerOpen = false);
                },
              ),
            if (_creating)
              SizedBox(
                width: 220,
                height: 44,
                child: TextField(
                  controller: _newFolder,
                  autofocus: true,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _createFolder(),
                  decoration: InputDecoration(
                    hintText: 'Folder name',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: IconButton(
                      tooltip: 'Use this folder',
                      icon: Icon(Icons.check_rounded, color: scheme.primary),
                      onPressed: _createFolder,
                    ),
                  ),
                ),
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New folder'),
                onPressed: () => setState(() => _creating = true),
              ),
          ],
        ),
      ),
    );
  }

  void _createFolder() {
    if (_newFolder.text.trim().isEmpty) return;
    c.pickNew(_newFolder.text);
    _newFolder.clear();
    setState(() {
      _creating = false;
      _pickerOpen = false;
    });
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.link, required this.meta, required this.loading, this.aiDescription});
  final LinkInfo link;
  final PostMeta? meta;
  final bool loading;

  /// Replaces the raw caption once the AI has described the post.
  final String? aiDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final author = meta?.author ?? link.author;
    final caption = aiDescription ?? meta?.caption;
    return Row(
      children: [
        PostThumb(url: meta?.thumbnailUrl, platform: link.platform, size: 64, radius: 16),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (author != null)
                Text(
                  '@$author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                )
              else if (loading)
                const Skeleton(width: 110)
              else
                Text(
                  link.platform == Platform2.other
                      ? sourceLabel(link.platform, link.url)
                      : '${link.platform.label} post',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 5),
              if (caption != null && caption.isNotEmpty)
                ExpandableText(
                  caption.replaceAll(RegExp(r'\s+'), ' '),
                  ai: aiDescription != null,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.3),
                )
              else if (loading)
                const Skeleton(width: 200)
              else
                Text(
                  Uri.parse(link.url).host + Uri.parse(link.url).path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BulkPreview extends StatelessWidget {
  const _BulkPreview({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.collections_bookmark_outlined, color: scheme.onPrimaryContainer, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count links', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                'Saved together. Previews and descriptions fill in when you open Stash.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.folderName});
  final String folderName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.bookmark_added_rounded, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Already saved in $folderName. Pick another folder to move it.',
              style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visual focus of the sheet: where this post is about to go.
class _FolderChip extends StatelessWidget {
  const _FolderChip({required this.controller, required this.open, required this.onTap});
  final ShareController controller;
  final bool open;
  final VoidCallback onTap;

  String _label() {
    final c = controller;
    if (c.isBulk) return c.newName != null ? 'Into a new folder' : 'Into';
    if (c.duplicate != null && !c.userPicked) return 'Saved in';
    if (c.userPicked) return c.newName != null ? 'New folder' : 'Save to';
    if (c.newName != null) return 'Suggested new folder';
    return switch (c.suggestion?.source) {
      SuggestionSource.lastUsed => 'Last used',
      SuggestionSource.unsorted => 'Save to',
      _ => 'Suggested',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final loading = c.suggesting;
    final byAi = !loading && !c.userPicked && c.duplicate == null && c.suggestion?.source == SuggestionSource.ai;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              if (loading)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              else
                FolderAvatar(emoji: c.selected?.emoji ?? c.newEmoji, color: c.selected?.color ?? 0, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (byAi) ...[
                          Icon(Icons.auto_awesome_rounded, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          loading ? 'Finding the best folder…' : (byAi ? 'Suggested by AI' : _label()),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: byAi ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: byAi ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (loading)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Skeleton(width: 120, height: 14))
                    else
                      Text(
                        c.choiceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              Text('Change', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.expand_more_rounded, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
