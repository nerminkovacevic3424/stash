import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'post_card.dart';

/// Search across every saved post: caption, author and notes.
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

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_search);
  }

  @override
  void dispose() {
    widget.store.removeListener(_search);
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final q = _query.text.trim();
    final results = q.isEmpty ? const <Post>[] : await widget.store.repo.posts(query: q, platform: _platform);
    if (mounted && seq == _seq) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Search captions, authors, notes',
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
            onChanged: (p) {
              setState(() => _platform = p);
              _search();
            },
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      q.isEmpty ? 'Search everything you have saved' : 'No saved posts match "$q"',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, i) => PostCard(
                      key: ValueKey(_results[i].id),
                      store: widget.store,
                      post: _results[i],
                      showFolder: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
