import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models.dart';
import 'widgets.dart';

class ReorderScreen extends StatefulWidget {
  const ReorderScreen({super.key, required this.store});
  final Store store;

  @override
  State<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends State<ReorderScreen> {
  late final List<Folder> _folders = [...widget.store.folders];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reorder folders')),
    body: ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _folders.length,
      onReorderItem: (from, to) {
        setState(() => _folders.insert(to, _folders.removeAt(from)));
        widget.store.mutate(() => widget.store.repo.reorderFolders([for (final f in _folders) f.id]));
      },
      itemBuilder: (_, i) {
        final f = _folders[i];
        return ListTile(
          key: ValueKey(f.id),
          leading: FolderAvatar(emoji: f.emoji, color: f.color, size: 40),
          title: Text(f.name),
          trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
        );
      },
    ),
  );
}
