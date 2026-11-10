import Foundation
import UIKit

/// State machine behind the share sheet. Mirrors lib/share/share_controller.dart:
/// show immediately, fill in preview and suggestion as they arrive, and settle
/// the suggestion exactly once — by the first real answer or, after 1.5s, the fallback.
@MainActor
final class ShareModel: ObservableObject {
    enum Stage { case ready, saving, saved, invalid, setupNeeded }

    @Published var stage: Stage = .ready
    @Published var link: LinkInfo?
    @Published var meta: PostMeta?
    @Published var metaLoading = true
    @Published var folders: [Folder] = []
    @Published var suggestion: Suggestion?
    @Published var selected: Folder?
    @Published var newName: String?
    @Published var newEmoji = "📁"
    @Published var userPicked = false
    @Published var duplicate: SavedPost?
    @Published var confirmation = ""

    private let store: SharedStore?
    private let sharedText: String?
    let close: () -> Void
    private var deadline: Task<Void, Never>?
    private var savedPostId: String?
    private var pipelineFinished = false

    init(sharedText: String?, close: @escaping () -> Void) {
        self.sharedText = sharedText
        self.close = close
        self.store = SharedStore()
    }

    var suggesting: Bool { suggestion == nil && !userPicked && duplicate == nil }
    var hasChoice: Bool { selected != nil || newName != nil }
    var choiceName: String { newName ?? selected?.name ?? "" }
    var author: String? { meta?.author ?? link?.author }
    var duplicateFolderName: String { folder(duplicate?.folderId)?.name ?? "your library" }
    var duplicateInPlace: Bool { duplicate != nil && newName == nil && selected?.id == duplicate?.folderId }

    private func folder(_ id: String?) -> Folder? { folders.first { $0.id == id } }

    func start() async {
        guard let store = store else {
            stage = .setupNeeded
            return
        }
        if let saved = store.kv("backend_url"), !saved.isEmpty { Backend.baseURL = saved }
        folders = store.folders()
        guard let raw = LinkParser.extractUrl(sharedText), let l = LinkParser.canonicalize(raw) else {
            stage = .invalid
            return
        }
        link = l
        checkDuplicate(url: l.url)

        if duplicate == nil {
            deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !Task.isCancelled { self?.settle(nil) }
            }
            // TikTok links carry the handle, so known authors resolve with no network.
            if let a = l.author, let id = store.authorFolder(platform: l.platform, author: a) {
                settle(.existing(folderId: id, source: .author))
            }
        }

        var reachable = true
        var m: PostMeta?
        do { m = try await Backend.metadata(url: l.url) } catch { reachable = false }
        meta = m
        metaLoading = false

        if let id = savedPostId {
            // Saved before the preview arrived; attach it now rather than queueing.
            if let m = m { store.applyMeta(postId: id, meta: m) }
            return
        }
        if let m = m, duplicate == nil { checkDuplicate(url: m.url) }
        if duplicate != nil || suggestion != nil { return }

        var s: Suggestion?
        if let m = m {
            if let a = author, let id = store.authorFolder(platform: l.platform, author: a) {
                s = .existing(folderId: id, source: .author)
            } else if let id = store.keywordFolder(Array(LinkParser.keywords(m.caption).keys)) {
                s = .existing(folderId: id, source: .keywords)
            } else if let caption = m.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    s = try await Backend.suggest(
                        link: l, author: author, caption: caption, folders: folders,
                        examples: store.folderExamples(), hints: store.keywordHints())
                } catch { reachable = false }
            }
        }
        // Only an answer inside the budget counts as finished; otherwise the
        // main app's queue retries after the save.
        pipelineFinished = reachable && suggestion == nil
        settle(s)
    }

    private func checkDuplicate(url: String) {
        guard let d = store?.findPost(url: url) else { return }
        duplicate = d
        deadline?.cancel()
        if !userPicked {
            selected = folder(d.folderId)
            newName = nil
        }
    }

    private func settle(_ candidate: Suggestion?) {
        guard suggestion == nil, duplicate == nil, let store = store else { return }
        deadline?.cancel()
        let s: Suggestion
        if let candidate = candidate {
            s = candidate
        } else if let last = store.kv("last_folder"), folder(last) != nil {
            s = .existing(folderId: last, source: .lastUsed)
        } else {
            s = .existing(folderId: unsortedId, source: .unsorted)
        }
        suggestion = s
        guard !userPicked else { return }
        switch s {
        case .existing(let id, _):
            selected = folder(id) ?? folder(unsortedId)
            newName = nil
        case .new(let name, let emoji):
            selected = nil
            newName = name
            newEmoji = emoji
        }
    }

    func pick(_ f: Folder) {
        userPicked = true
        selected = f
        newName = nil
    }

    /// Picks a folder to be created on save (or the existing one of that name).
    func pickNew(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = folders.first(where: { $0.name.lowercased() == name.lowercased() }) {
            pick(existing)
            return
        }
        userPicked = true
        selected = nil
        newName = name
        newEmoji = "📁"
    }

    func save(note: String) {
        guard let store = store, let l = link, hasChoice, stage == .ready else { return }
        stage = .saving
        let target = selected ?? store.createFolder(name: newName ?? "", emoji: newEmoji)

        if let dup = duplicate {
            let moved = target.id != dup.folderId
            if moved { store.movePost(id: dup.id, to: target.id) }
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { store.setNote(postId: dup.id, note: trimmed) }
            confirmation = moved ? "Moved to \(target.name)" : "Already in \(target.name)"
        } else {
            savedPostId = store.insertPost(
                link: l, folderId: target.id, meta: meta, note: note,
                needsSuggestion: !userPicked && (suggestion?.isFallback ?? true) && !pipelineFinished)
            confirmation = "Saved to \(target.name)"
        }
        store.setKv("last_folder", target.id)

        // A manual choice that differs from what we offered is a correction.
        if userPicked, suggestion?.folderId != target.id {
            store.learn(
                platform: l.platform, folderId: target.id, author: author ?? duplicate?.author,
                keywords: LinkParser.keywords(meta?.caption ?? duplicate?.caption),
                rejectedFolderId: suggestion?.folderId)
        }

        stage = .saved
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { [close] in
            try? await Task.sleep(nanoseconds: 950_000_000)
            close()
        }
    }
}
