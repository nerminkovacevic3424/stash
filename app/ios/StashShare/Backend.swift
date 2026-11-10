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

    /// Asks the AI to describe the post and pick (or propose) a folder for it.
    static func suggest(
        link: LinkInfo, author: String?, caption: String?, thumbnailUrl: String?, folders: [Folder],
        examples: [String: [String]], hints: [[String: String]]
    ) async throws -> (suggestion: Suggestion?, description: String?) {
        let body: [String: Any] = [
            "platform": link.platform,
            "author": author ?? NSNull(),
            "caption": caption ?? NSNull(),
            "thumbnailUrl": thumbnailUrl ?? NSNull(),
            "hashtags": LinkParser.hashtags(caption),
            "folders": folders.filter { $0.id != unsortedId }.map {
                ["id": $0.id, "name": $0.name, "examples": examples[$0.id] ?? []] as [String: Any]
            },
            "hints": hints,
        ]
        guard let data = try await post("/v1/suggest", body: body, timeout: 12),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, nil) }
        let text = (json["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (text?.isEmpty ?? true) ? nil : text
        var suggestion: Suggestion?
        if let s = json["suggestion"] as? [String: Any], let kind = s["kind"] as? String {
            if kind == "existing", let id = s["folderId"] as? String, folders.contains(where: { $0.id == id }) {
                suggestion = .existing(folderId: id, source: .ai)
            } else if kind == "new", let name = s["name"] as? String {
                suggestion = .new(name: name, emoji: s["emoji"] as? String ?? "📁")
            }
        }
        return (suggestion, description)
    }
}
