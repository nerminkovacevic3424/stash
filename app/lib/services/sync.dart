import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/repo.dart';

const _folderCols = ['id', 'name', 'emoji', 'color', 'sort_order', 'created_at', 'updated_at'];
const _postCols = [
  'id',
  'url',
  'source_url',
  'platform',
  'author',
  'author_name',
  'caption',
  'thumbnail_url',
  'note',
  'ai_description',
  'favorite',
  'watched',
  'tags',
  'ai_points',
  'ai_place',
  'folder_id',
  'created_at',
  'updated_at',
];

/// Optional multi-device sync through Supabase (see supabase/schema.sql).
///
/// Local SQLite stays the source of truth. Each sync pulls rows changed on the
/// server since the last cursor, keeps whichever copy has the newer
/// `updated_at` (last write wins, deletes are tombstones), then pushes rows
/// flagged `dirty`.
class SyncService {
  SyncService(this.repo);
  final Repo repo;
  bool _busy = false;

  bool get enabled => Config.syncConfigured;
  SupabaseClient get _c => Supabase.instance.client;
  User? get user => enabled ? _c.auth.currentUser : null;

  static Future<void> init() async {
    if (Config.syncConfigured) {
      await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseKey);
    }
  }

  Future<void> signIn(String email, String password) => _c.auth.signInWithPassword(email: email, password: password);

  /// Returns false when the project requires e-mail confirmation first.
  Future<bool> signUp(String email, String password) async =>
      (await _c.auth.signUp(email: email, password: password)).session != null;

  Future<void> signOut() => _c.auth.signOut();

  /// Returns true when local data changed. Throws on network/auth errors.
  Future<bool> sync() async {
    final uid = user?.id;
    if (uid == null || _busy) return false;
    _busy = true;
    try {
      if (await repo.kv('sync_uid') != uid) {
        // First sync for this account on this device: upload everything.
        await repo.db.update('folders', {'dirty': 1});
        await repo.db.update('posts', {'dirty': 1});
        await repo.setKv('sync_uid', uid);
      }
      var changed = await _pull('folders', uid, _folderCols);
      changed = await _pull('posts', uid, _postCols) || changed;
      await _push('folders', uid, _folderCols);
      await _push('posts', uid, _postCols);
      await repo.setKv('last_sync', DateTime.now().toIso8601String());
      return changed;
    } finally {
      _busy = false;
    }
  }

  Future<bool> _pull(String table, String uid, List<String> cols) async {
    final key = 'sync_cursor_${table}_$uid';
    final cursor = await repo.kv(key) ?? '1970-01-01T00:00:00Z';
    var maxSeen = cursor;
    var changed = false;
    for (var from = 0; ; from += 500) {
      final rows = await _c
          .from(table)
          .select()
          .gt('server_updated_at', cursor)
          .order('server_updated_at')
          .range(from, from + 499);
      for (final remote in rows) {
        maxSeen = remote['server_updated_at'] as String;
        changed = await _apply(table, remote, cols) || changed;
      }
      if (rows.length < 500) break;
    }
    await repo.setKv(key, maxSeen);
    return changed;
  }

  Future<bool> _apply(String table, Map<String, dynamic> remote, List<String> cols) async {
    final db = repo.db;
    final id = remote['id'] as String;
    final local = await db.query(table, columns: ['updated_at'], where: 'id = ?', whereArgs: [id]);
    if (local.isNotEmpty && (local.first['updated_at'] as int) >= (remote['updated_at'] as int)) return false;

    final deleted = remote['deleted'] == true;
    final row = <String, Object?>{for (final c in cols) c: remote[c], 'deleted': deleted ? 1 : 0, 'dirty': 0};
    if (table == 'posts') {
      row['meta_status'] = (remote['caption'] ?? remote['thumbnail_url']) != null ? 1 : 0;
      row['ai_status'] = remote['ai_description'] != null ? 1 : 0;
      row['extract_status'] = remote['ai_points'] != null || remote['ai_place'] != null ? 1 : 0;
      if (!deleted) {
        // Both devices saved the same link independently: keep the incoming copy.
        await db.update(
          'posts',
          {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch, 'dirty': 1},
          where: 'deleted = 0 AND url = ? AND id != ?',
          whereArgs: [remote['url'], id],
        );
      }
    }
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> _push(String table, String uid, List<String> cols) async {
    final db = repo.db;
    final dirty = await db.query(table, where: 'dirty = 1');
    for (var i = 0; i < dirty.length; i += 200) {
      final chunk = dirty.sublist(i, (i + 200).clamp(0, dirty.length));
      await _c.from(table).upsert([
        for (final r in chunk) {for (final c in cols) c: r[c], 'deleted': r['deleted'] == 1, 'user_id': uid},
      ], onConflict: 'user_id,id');
      final b = db.batch();
      for (final r in chunk) {
        // Leave the flag set if the row was edited while the upload ran.
        b.update(table, {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [r['id'], r['updated_at']]);
      }
      await b.commit(noResult: true);
    }
  }
}
