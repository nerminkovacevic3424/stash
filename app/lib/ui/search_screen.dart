import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import '../services/api.dart';
import 'post_card.dart';

/// Search across every saved post. Typing matches words in descriptions,
/// captions, tags, authors and notes at once; "Search by meaning" asks the AI
/// to find posts that fit what you are after even when the words differ.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.store});
  final Store store;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Post> _results = const [];
  Platform2? _platform;
  int _seq = 0;

  /// Null until asked; then the AI's matches for [_aiQuery].
  List<Post>? _ai;
  String _aiQuery = '';
  bool _aiBusy = false;
  bool _aiFailed = false;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_search);
  }

  @override
  void dispose() {
    store.removeListener(_search);
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final q = _query.text.trim();
    final results = q.isEmpty ? const <Post>[] : await store.repo.posts(query: q, platform: _platform);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = results;
      if (q != _aiQuery) {
        _ai = null;
        _aiFailed = false;
      }
    });
  }

  Future<void> _askAi() async {
    final q = _query.text.trim();
    if (q.length < 3 || _aiBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _aiBusy = true;
      _aiFailed = false;
    });
    final library = await store.repo.posts(limit: 400);
    List<String>? ids;
    try {
      ids = await store.api.search(q, [
        for (final p in library)
          {
            'id': p.id,
            'text': [
              p.aiDescription ?? p.caption?.replaceAll(RegExp(r'\s+'), ' ') ?? '',
              if (p.tags.isNotEmpty) p.tags.join(', '),
              ?store.folderById(p.folderId)?.name,
              ?p.author,
              ?p.note,
            ].join(' · '),
          },
      ]);
    } on Unreachable {
      ids = null;
    }
    if (!mounted) return;
    final byId = {for (final p in library) p.id: p};
    setState(() {
      _aiBusy = false;
      _aiQuery = q;
      _aiFailed = ids == null;
      _ai = ids == null ? null : [for (final id in ids) ?byId[id]];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final q = _query.text.trim();
    final ai = _ai;
    final aiIds = {for (final p in ai ?? const <Post>[]) p.id};
    // The AI's picks come first; plain matches it did not pick follow.
    final rest = [
      for (final p in _results)
        if (!aiIds.contains(p.id)) p,
    ];

    Widget header(String text, {IconData? icon}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: scheme.primary), const SizedBox(width: 6)],
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: icon != null ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _search(),
          onSubmitted: (_) => _askAi(),
          decoration: InputDecoration(
            hintText: 'Search, or describe what you want',
            filled: false,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _query.clear();
                      _search();
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlatformFilter(
            value: _platform,
            options: store.platforms,
            onChanged: (p) {
              setState(() => _platform = p);
              _search();
            },
          ),
          Expanded(
            child: q.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Type a word, or describe what you are after, like "something quick for dinner".',
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (ai == null && q.length >= 3)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                          child: Material(
                            color: scheme.primaryContainer.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _aiBusy ? null : _askAi,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    if (_aiBusy)
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2.5),
                                      )
                                    else
                                      Icon(Icons.auto_awesome_rounded, size: 20, color: scheme.primary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _aiBusy
                                            ? 'Looking through your saves…'
                                            : _aiFailed
                                            ? 'Could not reach the AI. Tap to try again.'
                                            : 'Search by meaning',
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (ai != null) ...[
                        header(
                          ai.isEmpty ? 'The AI found nothing that fits' : 'Best matches',
                          icon: Icons.auto_awesome_rounded,
                        ),
                        for (final p in ai)
                          PostCard(key: ValueKey('ai-${p.id}'), store: store, post: p, showFolder: true),
                      ],
                      if (rest.isNotEmpty) ...[
                        if (ai != null) header('Also contains "$q"'),
                        for (final p in rest) PostCard(key: ValueKey(p.id), store: store, post: p, showFolder: true),
                      ],
                      if (rest.isEmpty && ai == null && !_aiBusy)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('No saved post contains "$q".', textAlign: TextAlign.center, style: muted),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
