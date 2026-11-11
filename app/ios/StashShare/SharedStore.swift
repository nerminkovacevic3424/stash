import Foundation
import SQLite3

/// Must match the App Group on both targets and `Config.appGroupId` in lib/config.dart.
let appGroupId = "group.com.example.stash"

let unsortedId = "unsorted"

struct Folder: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let color: Int
}

struct SavedPost {
    let id: String
    let folderId: String
    let author: String?
    let caption: String?
}

/// Direct access to the SQLite file the Flutter app uses (lib/data/repo.dart).
/// The schema below is a copy of the Dart one — change both together.
final class SharedStore {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let schema = [
        """
        CREATE TABLE IF NOT EXISTS folders(
          id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL DEFAULT '📁',
          color INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)
        """,
        """
        CREATE TABLE IF NOT EXISTS posts(
          id TEXT PRIMARY KEY, url TEXT NOT NULL, source_url TEXT NOT NULL, platform TEXT NOT NULL,
          author TEXT, author_name TEXT, caption TEXT, thumbnail_url TEXT, note TEXT,
          folder_id TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          meta_status INTEGER NOT NULL DEFAULT 0, meta_attempts INTEGER NOT NULL DEFAULT 0,
          needs_suggestion INTEGER NOT NULL DEFAULT 0,
          ai_description TEXT, ai_status INTEGER NOT NULL DEFAULT 0,
          favorite INTEGER NOT NULL DEFAULT 0,
          deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1)
        """,
        "CREATE INDEX IF NOT EXISTS posts_folder ON posts(folder_id, created_at)",
        "CREATE INDEX IF NOT EXISTS posts_url ON posts(url)",
        "CREATE INDEX IF NOT EXISTS posts_author ON posts(platform, author)",
        """
        CREATE TABLE IF NOT EXISTS author_rules(
          platform TEXT NOT NULL, author TEXT NOT NULL, folder_id TEXT NOT NULL,
          updated_at INTEGER NOT NULL, PRIMARY KEY(platform, author))
        """,
        """
        CREATE TABLE IF NOT EXISTS keyword_rules(
          keyword TEXT NOT NULL, folder_id TEXT NOT NULL, weight INTEGER NOT NULL,
          PRIMARY KEY(keyword, folder_id))
        """,
        "CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT)",
        """
        INSERT OR IGNORE INTO folders(id, name, emoji, color, sort_order, created_at, updated_at)
        VALUES('unsorted', 'Unsorted', '📥', 0, -1, 0, 0)
        """,
    ]

    /// Nil when the App Group is not set up on this target.
    init?() {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        let path = dir.appendingPathComponent("stash.db").path
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 3000)
        _ = query("PRAGMA journal_mode=WAL")
        for sql in Self.schema { run(sql) }
        // Columns added after the first release (same migration as repo.dart).
        let columns = Set(query("PRAGMA table_info(posts)").compactMap { $0["name"] as? String })
        if !columns.contains("ai_description") { run("ALTER TABLE posts ADD COLUMN ai_description TEXT") }
        if !columns.contains("ai_status") { run("ALTER TABLE posts ADD COLUMN ai_status INTEGER NOT NULL DEFAULT 0") }
        if !columns.contains("favorite") { run("ALTER TABLE posts ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0") }
        // sqflite tracks its schema version here; set it so the app does not re-run onCreate.
        if (query("PRAGMA user_version").first?["user_version"] as? Int64 ?? 0) == 0 {
            run("PRAGMA user_version = 1")
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - Plumbing

    @discardableResult
    func query(_ sql: String, _ args: [Any?] = []) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("stash sqlite: %@", String(cString: sqlite3_errmsg(db)))
            return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let n = Int32(i + 1)
            switch arg {
            case let s as String: sqlite3_bind_text(stmt, n, s, -1, Self.transient)
            case let v as Int: sqlite3_bind_int64(stmt, n, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, n, v)
            case let b as Bool: sqlite3_bind_int64(stmt, n, b ? 1 : 0)
            default: sqlite3_bind_null(stmt, n)
            }
        }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, c)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, c))
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }

    func run(_ sql: String, _ args: [Any?] = []) { query(sql, args) }

    private var now: Int { Int(Date().timeIntervalSince1970 * 1000) }

    private static func newId() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private func folder(from row: [String: Any]) -> Folder {
        Folder(
            id: row["id"] as? String ?? "",
            name: row["name"] as? String ?? "",
            emoji: row["emoji"] as? String ?? "📁",
            color: Int(row["color"] as? Int64 ?? 0)
        )
    }

    // MARK: - Folders

    func folders() -> [Folder] {
        query("SELECT id, name, emoji, color FROM folders WHERE deleted = 0 ORDER BY sort_order, created_at")
            .map(folder(from:))
    }

    /// Returns the existing folder when one already has this name.
    func createFolder(name: String, emoji: String) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let row = query(
            "SELECT id, name, emoji, color FROM folders WHERE deleted = 0 AND name = ? COLLATE NOCASE", [trimmed]
        ).first {
            return folder(from: row)
        }
        let order = Int(query("SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM folders").first?["n"] as? Int64 ?? 1)
        let created = Folder(id: Self.newId(), name: trimmed, emoji: emoji, color: order % 8)
        run(
            "INSERT INTO folders(id, name, emoji, color, sort_order, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)",
            [created.id, created.name, created.emoji, created.color, order, now, now]
        )
        return created
    }

    // MARK: - Posts

    func findPost(url: String) -> SavedPost? {
        query(
            "SELECT id, folder_id, author, caption FROM posts WHERE deleted = 0 AND (url = ? OR source_url = ?) LIMIT 1",
            [url, url]
        ).first.map {
            SavedPost(
                id: $0["id"] as? String ?? "",
                folderId: $0["folder_id"] as? String ?? unsortedId,
                author: $0["author"] as? String,
                caption: $0["caption"] as? String
            )
        }
    }

    func insertPost(
        link: LinkInfo, folderId: String, meta: PostMeta?, note: String, needsSuggestion: Bool,
        aiDescription: String?, aiDone: Bool
    ) -> String {
        let id = Self.newId()
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        run(
            """
            INSERT INTO posts(id, url, source_url, platform, author, author_name, caption, thumbnail_url, note,
              folder_id, created_at, updated_at, meta_status, needs_suggestion, ai_description, ai_status)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                id, meta?.url ?? link.url, link.url, link.platform, meta?.author ?? link.author, meta?.authorName,
                meta?.caption, meta?.thumbnailUrl, cleanNote.isEmpty ? nil : cleanNote, folderId, now, now,
                (meta?.ok ?? false) ? 1 : 0, needsSuggestion, aiDescription, aiDone,
            ]
        )
        return id
    }

    /// Attaches metadata that arrived after the post was saved.
    func applyMeta(postId: String, meta: PostMeta) {
        run(
            """
            UPDATE posts SET url = ?, author = COALESCE(?, author), author_name = COALESCE(?, author_name),
              caption = COALESCE(?, caption), thumbnail_url = COALESCE(?, thumbnail_url),
              meta_status = ?, meta_attempts = meta_attempts + 1, updated_at = ?, dirty = 1
            WHERE id = ?
            """,
            [meta.url, meta.author, meta.authorName, meta.caption, meta.thumbnailUrl, (meta.ok ?? false) ? 1 : 0, now, postId]
        )
    }

    func movePost(id: String, to folderId: String) {
        run(
            "UPDATE posts SET folder_id = ?, needs_suggestion = 0, updated_at = ?, dirty = 1 WHERE id = ?",
            [folderId, now, id]
        )
    }

    func setNote(postId: String, note: String) {
        run("UPDATE posts SET note = ?, updated_at = ?, dirty = 1 WHERE id = ?", [note, now, postId])
    }

    // MARK: - Key/value

    func kv(_ key: String) -> String? {
        query("SELECT value FROM kv WHERE key = ?", [key]).first?["value"] as? String
    }

    func setKv(_ key: String, _ value: String) {
        run("INSERT OR REPLACE INTO kv(key, value) VALUES(?, ?)", [key, value])
    }

    // MARK: - Suggestion inputs and learning

    func authorFolder(platform: String, author: String) -> String? {
        let a = author.lowercased()
        if let id = query(
            """
            SELECT r.folder_id FROM author_rules r JOIN folders f ON f.id = r.folder_id AND f.deleted = 0
            WHERE r.platform = ? AND r.author = ?
            """, [platform, a]
        ).first?["folder_id"] as? String {
            return id
        }
        return query(
            """
            SELECT p.folder_id FROM posts p JOIN folders f ON f.id = p.folder_id AND f.deleted = 0
            WHERE p.deleted = 0 AND p.platform = ? AND p.author = ? AND p.folder_id != 'unsorted'
            GROUP BY p.folder_id ORDER BY COUNT(*) DESC, MAX(p.created_at) DESC LIMIT 1
            """, [platform, a]
        ).first?["folder_id"] as? String
    }

    /// The folder learned keywords point to, if the evidence is strong and unambiguous.
    func keywordFolder(_ keywords: [String]) -> String? {
        guard !keywords.isEmpty else { return nil }
        let marks = Array(repeating: "?", count: keywords.count).joined(separator: ",")
        let rows = query(
            """
            SELECT k.folder_id, SUM(k.weight) AS score FROM keyword_rules k
            JOIN folders f ON f.id = k.folder_id AND f.deleted = 0
            WHERE k.keyword IN (\(marks)) GROUP BY k.folder_id ORDER BY score DESC
            """, keywords.map { $0 as Any? }
        )
        guard let top = rows.first, let score = top["score"] as? Int64, score >= 3 else { return nil }
        if rows.count > 1, let second = rows[1]["score"] as? Int64, second >= score { return nil }
        return top["folder_id"] as? String
    }

    func learn(platform: String, folderId: String, author: String?, keywords: [String: Int], rejectedFolderId: String?) {
        guard folderId != unsortedId else { return }
        if let author = author, !author.isEmpty {
            run(
                "INSERT OR REPLACE INTO author_rules(platform, author, folder_id, updated_at) VALUES(?, ?, ?, ?)",
                [platform, author.lowercased(), folderId, now]
            )
        }
        for (keyword, weight) in keywords {
            run(
                """
                INSERT INTO keyword_rules(keyword, folder_id, weight) VALUES(?, ?, ?)
                ON CONFLICT(keyword, folder_id) DO UPDATE SET weight = MIN(weight + excluded.weight, 50)
                """, [keyword, folderId, weight]
            )
            if let rejected = rejectedFolderId, rejected != folderId {
                run("UPDATE keyword_rules SET weight = weight - 1 WHERE keyword = ? AND folder_id = ?", [keyword, rejected])
            }
        }
        run("DELETE FROM keyword_rules WHERE weight <= 0")
    }

    /// Up to three recent captions per folder, as context for the LLM.
    func folderExamples() -> [String: [String]] {
        var out: [String: [String]] = [:]
        let rows = query(
            """
            SELECT folder_id, caption FROM (
              SELECT folder_id, caption, ROW_NUMBER() OVER (PARTITION BY folder_id ORDER BY created_at DESC) AS n
              FROM posts WHERE deleted = 0 AND caption IS NOT NULL AND caption != '')
            WHERE n <= 3
            """
        )
        for row in rows {
            if let id = row["folder_id"] as? String, let caption = row["caption"] as? String {
                out[id, default: []].append(caption)
            }
        }
        return out
    }

    func keywordHints() -> [[String: String]] {
        query(
            """
            SELECT k.keyword, k.folder_id FROM keyword_rules k JOIN folders f ON f.id = k.folder_id AND f.deleted = 0
            ORDER BY k.weight DESC LIMIT 40
            """
        ).compactMap {
            guard let k = $0["keyword"] as? String, let f = $0["folder_id"] as? String else { return nil }
            return ["keyword": k, "folderId": f]
        }
    }
}
