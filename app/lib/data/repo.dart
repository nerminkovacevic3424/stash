import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../models.dart';

/// The schema is shared with the iOS Share Extension, which opens the same
/// file directly (ios/StashShare/SharedStore.swift). Keep both in sync.
const schema = <String>[
  '''CREATE TABLE IF NOT EXISTS folders(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    emoji TEXT NOT NULL DEFAULT '📁',
    color INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    dirty INTEGER NOT NULL DEFAULT 1)''',
  '''CREATE TABLE IF NOT EXISTS posts(
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    source_url TEXT NOT NULL,
    platform TEXT NOT NULL,
    author TEXT,
    author_name TEXT,
    caption TEXT,
    thumbnail_url TEXT,
    note TEXT,
    folder_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    meta_status INTEGER NOT NULL DEFAULT 0,
    meta_attempts INTEGER NOT NULL DEFAULT 0,
    needs_suggestion INTEGER NOT NULL DEFAULT 0,
    ai_description TEXT,
    ai_status INTEGER NOT NULL DEFAULT 0,
    favorite INTEGER NOT NULL DEFAULT 0,
    deleted INTEGER NOT NULL DEFAULT 0,
    dirty INTEGER NOT NULL DEFAULT 1)''',
  'CREATE INDEX IF NOT EXISTS posts_folder ON posts(folder_id, created_at)',
  'CREATE INDEX IF NOT EXISTS posts_url ON posts(url)',
  'CREATE INDEX IF NOT EXISTS posts_author ON posts(platform, author)',
  // Learned from manual corrections; device-local, never synced.
  '''CREATE TABLE IF NOT EXISTS author_rules(
    platform TEXT NOT NULL,
    author TEXT NOT NULL,
    folder_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(platform, author))''',
  '''CREATE TABLE IF NOT EXISTS keyword_rules(
    keyword TEXT NOT NULL,
    folder_id TEXT NOT NULL,
    weight INTEGER NOT NULL,
    PRIMARY KEY(keyword, folder_id))''',
  'CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT)',
  "INSERT OR IGNORE INTO folders(id, name, emoji, color, sort_order, created_at, updated_at) VALUES('unsorted', 'Unsorted', '📥', 0, -1, 0, 0)",
];

int _now() => DateTime.now().millisecondsSinceEpoch;

final _rng = Random.secure();
String newId() => List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

class Repo {
  Repo(this.db);
  final Database db;

  static Future<String> defaultPath() async {
    if (Platform.isIOS) {
      try {
        final dir = await PathProviderFoundation().getContainerPath(appGroupIdentifier: Config.appGroupId);
        if (dir != null) return p.join(dir, 'stash.db');
      } catch (_) {
        // App Group not configured yet; fall through to the app's own sandbox.
      }
    }
    return p.join(await getDatabasesPath(), 'stash.db');
  }

  static Future<Repo> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? await defaultPath(),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          // The share sheet runs in another process and writes the same file.
          for (final pragma in const ['PRAGMA journal_mode=WAL', 'PRAGMA busy_timeout=3000']) {
            try {
              await db.rawQuery(pragma);
            } catch (_) {}
          }
        },
        onOpen: (db) async {
          for (final sql in schema) {
            await db.execute(sql);
          }
          // Columns added after the first release.
          final have = {for (final c in await db.rawQuery('PRAGMA table_info(posts)')) c['name']};
          if (!have.contains('ai_description')) await db.execute('ALTER TABLE posts ADD COLUMN ai_description TEXT');
          if (!have.contains('ai_status')) {
            await db.execute('ALTER TABLE posts ADD COLUMN ai_status INTEGER NOT NULL DEFAULT 0');
          }
          if (!have.contains('favorite')) {
            await db.execute('ALTER TABLE posts ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
          }
        },
      ),
    );
    return Repo(db);
  }

  // ---- key/value ----

  Future<String?> kv(String key) async {
    final r = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setKv(String key, String? value) =>
      db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- folders ----

  Future<List<Folder>> folders() async {
    final rows = await db.rawQuery('''
      SELECT f.*, (SELECT COUNT(*) FROM posts p WHERE p.folder_id = f.id AND p.deleted = 0) AS cnt
      FROM folders f WHERE f.deleted = 0 ORDER BY f.sort_order, f.created_at''');
    final coverRows = await db.rawQuery('''
      SELECT folder_id, thumbnail_url FROM (
        SELECT folder_id, thumbnail_url, ROW_NUMBER() OVER (PARTITION BY folder_id ORDER BY created_at DESC) AS n
        FROM posts WHERE deleted = 0 AND thumbnail_url IS NOT NULL)
      WHERE n <= 3 ORDER BY n''');
    final covers = <String, List<String>>{};
    for (final r in coverRows) {
      covers.putIfAbsent(r['folder_id'] as String, () => []).add(r['thumbnail_url'] as String);
    }
    return [for (final r in rows) Folder.fromRow(r, covers: covers[r['id']] ?? const [])];
  }

  Future<Folder?> folder(String id) async {
    final r = await db.query('folders', where: 'id = ? AND deleted = 0', whereArgs: [id]);
    return r.isEmpty ? null : Folder.fromRow(r.first);
  }

  /// Returns the existing folder when one already has this name.
  Future<Folder> createFolder(String name, {String emoji = '📁', int? color}) async {
    name = name.trim();
    final existing = await db.query('folders', where: 'deleted = 0 AND name = ? COLLATE NOCASE', whereArgs: [name]);
    if (existing.isNotEmpty) return Folder.fromRow(existing.first);
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM folders'))!;
    final now = _now();
    final row = {
      'id': newId(),
      'name': name,
      'emoji': emoji,
      'color': color ?? n % 8,
      'sort_order': n,
      'created_at': now,
      'updated_at': now,
    };
    await db.insert('folders', row);
    return Folder.fromRow(row);
  }

  Future<void> updateFolder(String id, {String? name, String? emoji, int? color}) => db.update(
    'folders',
    {'name': ?name?.trim(), 'emoji': ?emoji, 'color': ?color, 'updated_at': _now(), 'dirty': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Deletes a folder; its posts are deleted too, or moved to Unsorted.
  Future<void> deleteFolder(String id, {required bool deletePosts}) async {
    if (id == unsortedId) return;
    final now = _now();
    await db.transaction((t) async {
      await t.update(
        'posts',
        deletePosts
            ? {'deleted': 1, 'updated_at': now, 'dirty': 1}
            : {'folder_id': unsortedId, 'updated_at': now, 'dirty': 1},
        where: 'folder_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      await t.update('folders', {'deleted': 1, 'updated_at': now, 'dirty': 1}, where: 'id = ?', whereArgs: [id]);
      await t.delete('author_rules', where: 'folder_id = ?', whereArgs: [id]);
      await t.delete('keyword_rules', where: 'folder_id = ?', whereArgs: [id]);
    });
  }

  Future<void> reorderFolders(List<String> ids) async {
    final now = _now();
    final b = db.batch();
    for (var i = 0; i < ids.length; i++) {
      b.update('folders', {'sort_order': i, 'updated_at': now, 'dirty': 1}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await b.commit(noResult: true);
  }

  // ---- posts ----

  Future<List<Post>> posts({String? folderId, Platform2? platform, String? query, int? limit, bool? favorite}) async {
    final where = ['deleted = 0'];
    final args = <Object?>[];
    if (favorite != null) where.add('favorite = ${favorite ? 1 : 0}');
    if (folderId != null) {
      where.add('folder_id = ?');
      args.add(folderId);
    }
    if (platform != null) {
      where.add('platform = ?');
      args.add(platform.name);
    }
    final q = query?.trim() ?? '';
    if (q.isNotEmpty) {
      final like = '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.add(
        "(ai_description LIKE ? ESCAPE '\\' OR caption LIKE ? ESCAPE '\\' OR author LIKE ? ESCAPE '\\' OR author_name LIKE ? ESCAPE '\\' OR note LIKE ? ESCAPE '\\')",
      );
      args.addAll([like, like, like, like, like]);
    }
    final rows = await db.query(
      'posts',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Post.fromRow).toList();
  }

  /// The saved post matching any of [urls] (canonical or as-shared), if any.
  Future<Post?> findByUrl(Iterable<String> urls) async {
    final list = urls.toSet().toList();
    if (list.isEmpty) return null;
    final marks = List.filled(list.length, '?').join(',');
    final r = await db.query(
      'posts',
      where: 'deleted = 0 AND (url IN ($marks) OR source_url IN ($marks))',
      whereArgs: [...list, ...list],
      limit: 1,
    );
    return r.isEmpty ? null : Post.fromRow(r.first);
  }

  Future<String> insertPost({
    required LinkInfo link,
    required String sourceUrl,
    required String folderId,
    PostMeta? meta,
    String? note,
    bool needsSuggestion = false,
    String? aiDescription,
    bool aiDone = false,
  }) async {
    final id = newId();
    final now = _now();
    await db.insert('posts', {
      'id': id,
      'url': meta?.url ?? link.url,
      'source_url': sourceUrl,
      'platform': link.platform.name,
      'author': meta?.author ?? link.author,
      'author_name': meta?.authorName,
      'caption': meta?.caption,
      'thumbnail_url': meta?.thumbnailUrl,
      'note': _blankToNull(note),
      'folder_id': folderId,
      'created_at': now,
      'updated_at': now,
      'meta_status': meta != null && meta.ok ? 1 : 0,
      'needs_suggestion': needsSuggestion ? 1 : 0,
      'ai_description': aiDescription,
      'ai_status': aiDone ? 1 : 0,
    });
    return id;
  }

  /// Stores fetched metadata. If resolving a short link reveals that the post
  /// was already saved under its canonical URL, the newer copy is dropped.
  Future<void> applyMeta(String postId, PostMeta meta) async {
    final now = _now();
    final dup = await db.query(
      'posts',
      columns: ['id'],
      where: 'deleted = 0 AND url = ? AND id != ?',
      whereArgs: [meta.url, postId],
      limit: 1,
    );
    if (dup.isNotEmpty) {
      await db.update('posts', {'deleted': 1, 'updated_at': now, 'dirty': 1}, where: 'id = ?', whereArgs: [postId]);
      return;
    }
    await db.rawUpdate(
      '''UPDATE posts SET url = ?, author = COALESCE(?, author), author_name = COALESCE(?, author_name),
           caption = COALESCE(?, caption), thumbnail_url = COALESCE(?, thumbnail_url),
           meta_status = ?, meta_attempts = meta_attempts + 1, updated_at = ?, dirty = 1
         WHERE id = ?''',
      [meta.url, meta.author, meta.authorName, meta.caption, meta.thumbnailUrl, meta.ok ? 1 : 0, now, postId],
    );
    await _giveUpIfStale(postId);
  }

  /// The backend answered but had nothing for this post.
  Future<void> metaFailed(String postId) async {
    await db.rawUpdate('UPDATE posts SET meta_attempts = meta_attempts + 1 WHERE id = ?', [postId]);
    await _giveUpIfStale(postId);
  }

  // Stop retrying posts the platform will not describe (private, removed…).
  Future<void> _giveUpIfStale(String postId) => db.rawUpdate(
    'UPDATE posts SET meta_status = 2 WHERE id = ? AND meta_status = 0 AND meta_attempts >= 5',
    [postId],
  );

  Future<void> movePosts(Iterable<String> ids, String folderId) async {
    final now = _now();
    final b = db.batch();
    for (final id in ids) {
      b.update(
        'posts',
        {'folder_id': folderId, 'needs_suggestion': 0, 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await b.commit(noResult: true);
  }

  /// The platforms that have posts in this scope, most used first.
  Future<List<Platform2>> platforms({String? folderId, bool? favorite}) async {
    final where = [
      'deleted = 0',
      if (folderId != null) 'folder_id = ?',
      if (favorite != null) 'favorite = ${favorite ? 1 : 0}',
    ];
    final rows = await db.rawQuery(
      'SELECT platform FROM posts WHERE ${where.join(' AND ')} GROUP BY platform ORDER BY COUNT(*) DESC',
      [?folderId],
    );
    return [for (final r in rows) Platform2.parse(r['platform'] as String?)];
  }

  /// Total and favorite post counts, for the home screen.
  Future<(int, int)> counts() async {
    final r = (await db.rawQuery('SELECT COUNT(*) AS n, COALESCE(SUM(favorite), 0) AS f FROM posts WHERE deleted = 0'))
        .first;
    return (r['n'] as int, r['f'] as int);
  }

  Future<void> setFavorite(String id, bool favorite) => db.update(
    'posts',
    {'favorite': favorite ? 1 : 0, 'updated_at': _now(), 'dirty': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> setNote(String id, String? note) => db.update(
    'posts',
    {'note': _blankToNull(note), 'updated_at': _now(), 'dirty': 1},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deletePost(String id) =>
      db.update('posts', {'deleted': 1, 'updated_at': _now(), 'dirty': 1}, where: 'id = ?', whereArgs: [id]);

  Future<void> clearNeedsSuggestion(String id) =>
      db.update('posts', {'needs_suggestion': 0}, where: 'id = ?', whereArgs: [id]);

  Future<List<Post>> pendingMeta() async => (await db.query(
    'posts',
    where: 'deleted = 0 AND meta_status = 0',
    orderBy: 'created_at',
  )).map(Post.fromRow).toList();

  /// Posts with metadata that the AI has not looked at yet.
  Future<List<Post>> pendingAi() async => (await db.query(
    'posts',
    where: 'deleted = 0 AND ai_status = 0 AND meta_status != 0',
    orderBy: 'created_at',
  )).map(Post.fromRow).toList();

  /// Records the AI's description (may be null) and marks the post as seen.
  Future<void> setAi(String postId, String? description) => db.rawUpdate(
    'UPDATE posts SET ai_description = COALESCE(?, ai_description), ai_status = 1, updated_at = ?, dirty = 1 WHERE id = ?',
    [description, _now(), postId],
  );

  // ---- suggestion inputs & learning ----

  Future<String?> authorRule(Platform2 platform, String author) async {
    final r = await db.rawQuery(
      '''SELECT r.folder_id FROM author_rules r JOIN folders f ON f.id = r.folder_id AND f.deleted = 0
         WHERE r.platform = ? AND r.author = ?''',
      [platform.name, author.toLowerCase()],
    );
    return r.isEmpty ? null : r.first['folder_id'] as String;
  }

  /// The folder this author's posts were saved to most often (ties: most recent).
  Future<String?> authorHistory(Platform2 platform, String author, {String? excludePostId}) async {
    final r = await db.rawQuery(
      '''SELECT p.folder_id FROM posts p JOIN folders f ON f.id = p.folder_id AND f.deleted = 0
         WHERE p.deleted = 0 AND p.platform = ? AND p.author = ? AND p.folder_id != 'unsorted' AND p.id != ?
         GROUP BY p.folder_id ORDER BY COUNT(*) DESC, MAX(p.created_at) DESC LIMIT 1''',
      [platform.name, author.toLowerCase(), excludePostId ?? ''],
    );
    return r.isEmpty ? null : r.first['folder_id'] as String;
  }

  /// Summed learned weight per folder for [keywords], best first.
  Future<List<MapEntry<String, int>>> keywordScores(List<String> keywords) async {
    if (keywords.isEmpty) return [];
    final marks = List.filled(keywords.length, '?').join(',');
    final r = await db.rawQuery('''SELECT k.folder_id, SUM(k.weight) AS score FROM keyword_rules k
         JOIN folders f ON f.id = k.folder_id AND f.deleted = 0
         WHERE k.keyword IN ($marks) GROUP BY k.folder_id ORDER BY score DESC''', keywords);
    return [for (final row in r) MapEntry(row['folder_id'] as String, row['score'] as int)];
  }

  /// Records a manual folder choice so future suggestions follow it.
  /// [keywords] maps keyword -> weight; [rejectedFolderId] is the suggestion
  /// the user overrode, whose matching keyword rules are weakened.
  Future<void> learn({
    required Platform2 platform,
    required String folderId,
    String? author,
    Map<String, int> keywords = const {},
    String? rejectedFolderId,
  }) async {
    if (folderId == unsortedId) return;
    await db.transaction((t) async {
      if (author != null && author.isNotEmpty) {
        await t.insert('author_rules', {
          'platform': platform.name,
          'author': author.toLowerCase(),
          'folder_id': folderId,
          'updated_at': _now(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final e in keywords.entries) {
        await t.rawInsert(
          '''INSERT INTO keyword_rules(keyword, folder_id, weight) VALUES(?, ?, ?)
             ON CONFLICT(keyword, folder_id) DO UPDATE SET weight = MIN(weight + excluded.weight, 50)''',
          [e.key, folderId, e.value],
        );
        if (rejectedFolderId != null && rejectedFolderId != folderId) {
          await t.rawUpdate('UPDATE keyword_rules SET weight = weight - 1 WHERE keyword = ? AND folder_id = ?', [
            e.key,
            rejectedFolderId,
          ]);
        }
      }
      await t.delete('keyword_rules', where: 'weight <= 0');
    });
  }

  /// Up to three recent captions per folder, as context for the LLM.
  Future<Map<String, List<String>>> folderExamples() async {
    final r = await db.rawQuery('''
      SELECT folder_id, caption FROM (
        SELECT folder_id, caption, ROW_NUMBER() OVER (PARTITION BY folder_id ORDER BY created_at DESC) AS n
        FROM posts WHERE deleted = 0 AND caption IS NOT NULL AND caption != '')
      WHERE n <= 3''');
    final out = <String, List<String>>{};
    for (final row in r) {
      out.putIfAbsent(row['folder_id'] as String, () => []).add(row['caption'] as String);
    }
    return out;
  }

  /// The strongest learned keyword → folder pairs, as hints for the LLM.
  Future<List<Map<String, String>>> keywordHints() async {
    final r = await db.rawQuery('''
      SELECT k.keyword, k.folder_id FROM keyword_rules k JOIN folders f ON f.id = k.folder_id AND f.deleted = 0
      ORDER BY k.weight DESC LIMIT 40''');
    return [
      for (final row in r) {'keyword': row['keyword'] as String, 'folderId': row['folder_id'] as String},
    ];
  }
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
