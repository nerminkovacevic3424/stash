import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../models.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class FolderDraft {
  const FolderDraft(this.name, this.emoji, this.color);
  final String name;
  final String emoji;
  final int color;
}

/// Create / edit sheet: name, emoji and color.
Future<FolderDraft?> showFolderEditor(BuildContext context, {Folder? folder}) => showModalBottomSheet<FolderDraft>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _FolderEditor(folder: folder),
);

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({this.folder});
  final Folder? folder;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.folder?.name ?? '');
  late String _emoji = widget.folder?.emoji ?? '📁';
  late int _color = widget.folder?.color ?? 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, FolderDraft(name, _emoji, _color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.folder == null ? 'New folder' : 'Edit folder',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FolderAvatar(emoji: _emoji, color: _color, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: widget.folder == null,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Folder name', counterText: ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: folderColors.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Semantics(
                  button: true,
                  selected: i == _color,
                  label: 'Color ${i + 1}',
                  child: GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      width: 36,
                      decoration: BoxDecoration(
                        color: folderColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(color: i == _color ? scheme.onSurface : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 148,
              child: GridView.count(
                crossAxisCount: 8,
                children: [
                  for (final e in folderEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _emoji = e),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: e == _emoji ? scheme.primaryContainer : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _submit,
              child: Text(widget.folder == null ? 'Create folder' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates a folder through the editor; returns it (or null if cancelled).
Future<Folder?> createFolderFlow(BuildContext context, Store store) async {
  final draft = await showFolderEditor(context);
  if (draft == null) return null;
  late Folder folder;
  await store.mutate(() async {
    folder = await store.repo.createFolder(draft.name, emoji: draft.emoji, color: draft.color);
  });
  return folder;
}

Future<void> editFolderFlow(BuildContext context, Store store, Folder folder) async {
  final draft = await showFolderEditor(context, folder: folder);
  if (draft == null) return;
  await store.mutate(
    () => store.repo.updateFolder(folder.id, name: draft.name, emoji: draft.emoji, color: draft.color),
  );
}

/// Asks what to do with the folder's posts, then deletes. Returns true if deleted.
Future<bool> deleteFolderFlow(BuildContext context, Store store, Folder folder) async {
  final n = folder.count;
  final bool? deletePosts;
  if (n == 0) {
    final ok = await confirm(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete "${folder.name}"?',
      message: 'This folder is empty.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    deletePosts = ok ? false : null;
  } else {
    final posts = '$n ${n == 1 ? 'post' : 'posts'}';
    deletePosts = await chooseOption<bool>(
      context,
      title: 'Delete "${folder.name}"?',
      message: 'It holds $posts. Choose what happens to ${n == 1 ? 'it' : 'them'}.',
      options: [
        Option(false, Icons.inbox_outlined, 'Keep the posts', 'The folder goes; its $posts move to Unsorted.'),
        Option(
          true,
          Icons.delete_outline_rounded,
          'Delete the posts too',
          'The folder and its $posts are removed from Stash.',
          destructive: true,
        ),
      ],
    );
  }
  if (deletePosts == null) return false;
  final withPosts = deletePosts;
  await store.mutate(() => store.repo.deleteFolder(folder.id, deletePosts: withPosts));
  return true;
}

/// Folder list for "Move to…". Returns the chosen folder.
Future<Folder?> pickFolder(BuildContext context, Store store, {String? currentId}) => showModalBottomSheet<Folder>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Move to', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        for (final f in store.folders)
          ListTile(
            leading: FolderAvatar(emoji: f.emoji, color: f.color, size: 40),
            title: Text(f.name),
            trailing: f.id == currentId ? const Icon(Icons.check_rounded) : null,
            enabled: f.id != currentId,
            onTap: () => Navigator.pop(sheetContext, f),
          ),
        ListTile(
          leading: const SizedBox(width: 40, height: 40, child: Icon(Icons.add_rounded)),
          title: const Text('New folder'),
          onTap: () async {
            final created = await createFolderFlow(sheetContext, store);
            if (created != null && sheetContext.mounted) Navigator.pop(sheetContext, created);
          },
        ),
      ],
    ),
  ),
);

/// Sends a folder as a message: its name, then each post's description and
/// link. Pasting or sharing that message into Stash recreates the folder on
/// the other person's phone. It is a copy, not a live shared folder.
Future<void> sendFolder(BuildContext context, Store store, Folder folder) async {
  final posts = await store.repo.posts(folderId: folder.id);
  if (!context.mounted) return;
  if (posts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This folder is empty')));
    return;
  }
  final text = StringBuffer('📁 ${folder.name} — shared from Stash\n');
  for (final p in posts) {
    final about = (p.aiDescription ?? p.caption)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    text.write('\n');
    if (about != null && about.isNotEmpty) text.writeln(about.length > 120 ? '${about.substring(0, 117)}…' : about);
    text.writeln(p.url);
  }
  try {
    await const MethodChannel('stash/open')
        .invokeMethod<void>('shareText', {'text': text.toString(), 'title': 'Send "${folder.name}"'});
  } catch (_) {
    // No share menu on this platform: put it on the clipboard instead.
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Folder copied. Paste it into a message.')));
    }
  }
}
