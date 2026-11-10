import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../data/repo.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/link_parser.dart';
import '../services/suggester.dart';

enum ShareStage { ready, saving, saved, invalid }

/// State machine behind the share sheet.
///
/// The sheet is shown immediately; the preview and the folder suggestion fill
/// in as they arrive. The suggestion is settled exactly once: by the first
/// real answer, or by the fallback when [Config.suggestionBudget] runs out.
class ShareController extends ChangeNotifier {
  ShareController(this.repo, this.api) : suggester = Suggester(repo, api);

  final Repo repo;
  final Api api;
  final Suggester suggester;

  ShareStage stage = ShareStage.ready;
  LinkInfo? link;
  PostMeta? meta;
  bool metaLoading = true;
  List<Folder> folders = const [];

  /// Null until settled.
  FolderSuggestion? suggestion;

  /// The current choice: an existing folder, or a folder to create on save.
  Folder? selected;
  String? newName;
  String newEmoji = '📁';
  bool userPicked = false;

  /// Set when this link is already saved.
  Post? duplicate;
  Folder? duplicateFolder;

  /// Shown on the confirmation, e.g. "Saved to Recipes".
  String confirmation = '';

  Timer? _deadline;
  String? _savedPostId;
  bool _pipelineFinished = false;
  bool _disposed = false;

  bool get suggesting => suggestion == null && !userPicked && duplicate == null;
  bool get hasChoice => selected != null || newName != null;
  String get choiceName => newName ?? selected?.name ?? '';
  String? get author => meta?.author ?? link?.author;

  /// True when the chosen folder is where the duplicate already lives.
  bool get duplicateInPlace => duplicate != null && newName == null && selected?.id == duplicate!.folderId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    super.dispose();
  }

  Future<void> start(String? sharedText) async {
    folders = await repo.folders();
    final raw = extractUrl(sharedText);
    final l = raw == null ? null : canonicalize(raw);
    if (l == null) {
      stage = ShareStage.invalid;
      _notify();
      return;
    }
    link = l;
    await _checkDuplicate(l.url);
    _notify();

    if (duplicate == null) {
      _deadline = Timer(Config.suggestionBudget, () => _settle(null));
      // TikTok links carry the handle, so known authors resolve with no network.
      if (l.author != null) {
        final s = await suggester.local(platform: l.platform, author: l.author);
        if (s != null) await _settle(s);
      }
    }

    PostMeta? m;
    var reachable = true;
    try {
      m = await api.metadata(l.url, timeout: const Duration(seconds: 6));
    } on Unreachable {
      reachable = false;
    }
    meta = m;
    metaLoading = false;
    _notify();

    if (_savedPostId != null) {
      // Saved before the preview arrived; attach it now rather than queueing.
      if (m != null) await repo.applyMeta(_savedPostId!, m);
      return;
    }
    if (m != null && duplicate == null) await _checkDuplicate(m.url);
    if (duplicate != null || suggestion != null) return;

    FolderSuggestion? s;
    if (m != null) {
      s = await suggester.local(platform: l.platform, author: author, caption: m.caption);
      if (s == null && suggestion == null) {
        try {
          s = await suggester.ai(platform: l.platform, author: author, caption: m.caption);
        } on Unreachable {
          reachable = false;
        }
      }
    }
    // Only an answer that arrived inside the budget counts as "finished";
    // otherwise the queue gets to try again after the save.
    _pipelineFinished = reachable && suggestion == null;
    await _settle(s);
  }

  Future<void> _checkDuplicate(String url) async {
    final d = await repo.findByUrl([url]);
    if (d == null) return;
    duplicate = d;
    duplicateFolder = _folder(d.folderId);
    _deadline?.cancel();
    if (!userPicked) {
      selected = duplicateFolder;
      newName = null;
    }
  }

  Folder? _folder(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _settle(FolderSuggestion? s) async {
    if (suggestion != null || duplicate != null) return;
    s ??= await suggester.fallback();
    if (suggestion != null || duplicate != null) return; // lost the race while awaiting
    _deadline?.cancel();
    suggestion = s;
    if (!userPicked) {
      selected = s.folderId == null ? null : _folder(s.folderId!) ?? _folder(unsortedId);
      newName = s.newName;
      newEmoji = s.newEmoji ?? '📁';
    }
    _notify();
  }

  void pick(Folder folder) {
    userPicked = true;
    selected = folder;
    newName = null;
    _notify();
  }

  /// Picks a folder to be created on save (or the existing one of that name).
  void pickNew(String name) {
    name = name.trim();
    if (name.isEmpty) return;
    for (final f in folders) {
      if (f.name.toLowerCase() == name.toLowerCase()) return pick(f);
    }
    userPicked = true;
    selected = null;
    newName = name;
    newEmoji = '📁';
    _notify();
  }

  Future<void> save(String note) async {
    final l = link;
    if (l == null || !hasChoice || stage != ShareStage.ready) return;
    stage = ShareStage.saving;
    _notify();

    final folder = selected ?? await repo.createFolder(newName!, emoji: newEmoji);
    final dup = duplicate;
    if (dup != null) {
      final moved = folder.id != dup.folderId;
      if (moved) await repo.movePosts([dup.id], folder.id);
      if (note.trim().isNotEmpty) await repo.setNote(dup.id, note);
      confirmation = moved ? 'Moved to ${folder.name}' : 'Already in ${folder.name}';
    } else {
      _savedPostId = await repo.insertPost(
        link: l,
        sourceUrl: l.url,
        folderId: folder.id,
        meta: meta,
        note: note,
        // Filed by fallback before a real suggestion could be made (offline,
        // slow network): let the queue re-file it later.
        needsSuggestion: !userPicked && (suggestion?.isFallback ?? true) && !_pipelineFinished,
      );
      confirmation = 'Saved to ${folder.name}';
    }
    await repo.setKv('last_folder', folder.id);

    // A manual choice that differs from what we offered is a correction.
    if (userPicked && suggestion?.folderId != folder.id) {
      await suggester.learnFromChoice(
        platform: l.platform,
        chosenFolderId: folder.id,
        suggested: suggestion,
        author: author ?? dup?.author,
        caption: meta?.caption ?? dup?.caption,
      );
    }
    stage = ShareStage.saved;
    _notify();
  }
}
