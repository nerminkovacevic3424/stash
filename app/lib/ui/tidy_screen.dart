import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import '../services/api.dart';
import 'widgets.dart';

/// Asks the AI to look over the library and propose clean-ups: folders that
/// are really the same topic, and Unsorted posts that have an obvious home.
/// Nothing changes until the user applies a suggestion.
class TidyScreen extends StatefulWidget {
  const TidyScreen({super.key, required this.store});
  final Store store;

  @override
  State<TidyScreen> createState() => _TidyScreenState();
}

enum _State { loading, ready, failed }

class _TidyScreenState extends State<TidyScreen> {
  _State _state = _State.loading;
  List<FolderMerge> _merges = [];
  List<PostMove> _moves = [];

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    setState(() => _state = _State.loading);
    final repo = store.repo;
    final folders = await repo.folders();
    final examples = await repo.folderExamples();
    final unsorted = await repo.posts(folderId: unsortedId, limit: 80);
    Map<String, dynamic>? answer;
    try {
      answer = await store.api.tidy({
        'folders': [
          for (final f in folders)
            if (!f.isUnsorted) {'id': f.id, 'name': f.name, 'count': f.count, 'examples': examples[f.id] ?? const []},
        ],
        'unsorted': [
          for (final p in unsorted) {'id': p.id, 'text': p.aiDescription ?? p.caption ?? ''},
        ],
      });
    } on Unreachable {
      answer = null;
    }
    if (!mounted) return;
    if (answer == null) {
      setState(() => _state = _State.failed);
      return;
    }
    Folder? folder(Object? id) => folders.where((f) => f.id == id).firstOrNull;
    Post? post(Object? id) => unsorted.where((p) => p.id == id).firstOrNull;
    setState(() {
      _merges = [
        for (final m in (answer!['merges'] as List?) ?? const [])
          if (m is Map && folder(m['fromId']) != null && folder(m['intoId']) != null)
            FolderMerge(folder(m['fromId'])!, folder(m['intoId'])!, '${m['reason'] ?? ''}'),
      ];
      _moves = [
        for (final m in (answer['moves'] as List?) ?? const [])
          if (m is Map && post(m['postId']) != null && folder(m['folderId']) != null)
            PostMove(post(m['postId'])!, folder(m['folderId'])!),
      ];
      _state = _State.ready;
    });
  }

  Future<void> _applyMerge(FolderMerge m) async {
    await store.mutate(() => store.repo.mergeFolders(m.from.id, m.into.id));
    if (mounted) setState(() => _merges.remove(m));
  }

  Future<void> _applyMoves(List<PostMove> moves) async {
    await store.mutate(() async {
      for (final m in moves) {
        await store.repo.movePosts([m.post.id], m.folder.id);
      }
    });
    if (mounted) setState(() => _moves.removeWhere(moves.contains));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4);

    Widget message(IconData icon, String title, String body, {Widget? action}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: muted),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );

    final Widget body = switch (_state) {
      _State.loading => message(
        Icons.auto_awesome_rounded,
        'Looking over your library',
        'This takes a few seconds.',
        action: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
      ),
      _State.failed => message(
        Icons.cloud_off_rounded,
        'Could not reach the AI',
        'Check your connection and the server in Settings, then try again.',
        action: FilledButton.tonal(onPressed: _ask, child: const Text('Try again')),
      ),
      _State.ready when _merges.isEmpty && _moves.isEmpty => message(
        Icons.check_circle_rounded,
        'Nothing to tidy',
        'Your folders each cover their own topic and nothing in Unsorted has an obvious home.',
      ),
      _State.ready => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_merges.isNotEmpty) ...[
            Text('Folders that overlap', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final m in _merges)
              _Suggestion(
                onApply: () => _applyMerge(m),
                onSkip: () => setState(() => _merges.remove(m)),
                applyLabel: 'Merge',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FolderAvatar(emoji: m.from.emoji, color: m.from.color, size: 34),
                        const SizedBox(width: 8),
                        Flexible(child: Text(m.from.name, style: theme.textTheme.titleSmall)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, size: 18, color: scheme.onSurfaceVariant),
                        ),
                        FolderAvatar(emoji: m.into.emoji, color: m.into.color, size: 34),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            m.into.name,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (m.reason.isNotEmpty) ...[const SizedBox(height: 8), Text(m.reason, style: muted)],
                    const SizedBox(height: 4),
                    Text(
                      '${m.from.count} ${m.from.count == 1 ? 'post moves' : 'posts move'} into ${m.into.name}; '
                      '${m.from.name} is removed.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
          if (_moves.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Unsorted posts with a home',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_moves.length > 1)
                  TextButton(onPressed: () => _applyMoves([..._moves]), child: Text('Move all ${_moves.length}')),
              ],
            ),
            const SizedBox(height: 6),
            for (final m in _moves)
              _Suggestion(
                onApply: () => _applyMoves([m]),
                onSkip: () => setState(() => _moves.remove(m)),
                applyLabel: 'Move',
                child: Row(
                  children: [
                    PostThumb(url: m.post.thumbnailUrl, platform: m.post.platform, size: 52, radius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.post.aiDescription ?? m.post.caption ?? m.post.url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '→ ${m.folder.emoji} ${m.folder.name}',
                            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Tidy up')),
      body: body,
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.child, required this.onApply, required this.onSkip, required this.applyLabel});
  final Widget child;
  final VoidCallback onApply;
  final VoidCallback onSkip;
  final String applyLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                child: const Text('Skip'),
              ),
              TextButton(onPressed: onApply, child: Text(applyLabel)),
            ],
          ),
        ],
      ),
    );
  }
}
