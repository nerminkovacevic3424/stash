import Foundation

struct PostMeta: Decodable {
    let url: String
    let author: String?
    let authorName: String?
    let caption: String?
    let thumbnailUrl: String?
    let ok: Bool?
}

enum Suggestion {
    case existing(folderId: String, source: Source)
    case new(name: String, emoji: String)

    enum Source { case author, keywords, ai, lastUsed, unsorted }

    var folderId: String? {
        if case .existing(let id, _) = self { return id }
        return nil
    }

    var isFallback: Bool {
        if case .existing(_, let source) = self { return source == .lastUsed || source == .unsorted }
        return false
    }
}

/// Thrown when the backend could not be reached (offline, timeout, 5xx).
struct Unreachable: Error {}

enum Backend {
    /// Set `StashBackendURL` (and optionally `StashAppKey`) in the extension's Info.plist.
    /// Overridden by the address saved in the app's Settings, when there is one.
    static var baseURL =
        (Bundle.main.object(forInfoDictionaryKey: "StashBackendURL") as? String) ?? "http://127.0.0.1:8787"
    private static let appKey = (Bundle.main.object(forInfoDictionaryKey: "StashAppKey") as? String) ?? ""

    private static func post(_ path: String, body: [String: Any], timeout: TimeInterval) async throws -> Data? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !appKey.isEmpty { request.setValue(appKey, forHTTPHeaderField: "x-app-key") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Unreachable()
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        if status >= 500 || status == 429 { throw Unreachable() }
        return status == 200 ? data : nil
    }

    /// Resolves short links and fetches preview metadata.
    static func metadata(url: String) async throws -> PostMeta? {
        guard let data = try await post("/v1/metadata", body: ["url": url], timeout: 6) else { return nil }
        return try? JSONDecoder().decode(PostMeta.self, from: data)
    }

    /// Asks the LLM for a folder. Nil when it has no opinion.
    static func suggest(
        link: LinkInfo, author: String?, caption: String, folders: [Folder], examples: [String: [String]],
        hints: [[String: String]]
    ) async throws -> Suggestion? {
        let body: [String: Any] = [
            "platform": link.platform,
            "author": author ?? NSNull(),
            "caption": caption,
            "hashtags": LinkParser.hashtags(caption),
            "folders": folders.filter { $0.id != unsortedId }.map {
                ["id": $0.id, "name": $0.name, "examples": examples[$0.id] ?? []] as [String: Any]
            },
            "hints": hints,
        ]
        guard let data = try await post("/v1/suggest", body: body, timeout: 6),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let s = json["suggestion"] as? [String: Any],
            let kind = s["kind"] as? String
        else { return nil }
        if kind == "existing", let id = s["folderId"] as? String, folders.contains(where: { $0.id == id }) {
            return .existing(folderId: id, source: .ai)
        }
        if kind == "new", let name = s["name"] as? String {
            return .new(name: name, emoji: s["emoji"] as? String ?? "📁")
        }
        return nil
    }
}
