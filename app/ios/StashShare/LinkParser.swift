import Foundation

// The same rules live in lib/services/link_parser.dart, lib/services/suggester.dart
// and backend/lib/urls.js — keep them in sync.

struct LinkInfo {
    let platform: String  // "instagram" | "tiktok"
    let url: String
    let author: String?
    let needsResolve: Bool
}

enum LinkParser {
    private static let igHosts: Set = ["instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am"]
    private static let ttHosts: Set = ["tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com", "vt.tiktok.com"]
    private static let ttShortHosts: Set = ["vm.tiktok.com", "vt.tiktok.com"]

    private static func platform(ofHost host: String) -> String? {
        if igHosts.contains(host) { return "instagram" }
        if ttHosts.contains(host) { return "tiktok" }
        return nil
    }

    /// First Instagram/TikTok URL in the shared text, or nil.
    static func extractUrl(_ text: String?) -> String? {
        guard let text = text,
            let re = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+", options: .caseInsensitive)
        else { return nil }
        let ns = text as NSString
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var raw = ns.substring(with: match.range)
            while let last = raw.last, ").,!?".contains(last) { raw.removeLast() }
            if let host = URLComponents(string: raw)?.host?.lowercased(), platform(ofHost: host) != nil {
                return raw
            }
        }
        return nil
    }

    /// Normalizes a post URL; nil if it is not an Instagram/TikTok link.
    static func canonicalize(_ raw: String) -> LinkInfo? {
        guard let comps = URLComponents(string: raw),
            let scheme = comps.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = comps.host?.lowercased(),
            let platform = platform(ofHost: host)
        else { return nil }
        let seg = comps.path.split(separator: "/").map(String.init)

        if platform == "instagram" {
            if let i = seg.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }),
                i + 1 < seg.count, seg.first != "share"
            {
                let kind = seg[i] == "reels" ? "reel" : seg[i]
                return LinkInfo(
                    platform: platform, url: "https://www.instagram.com/\(kind)/\(seg[i + 1])/", author: nil,
                    needsResolve: false)
            }
            return LinkInfo(
                platform: platform,
                url: "https://www.instagram.com/\(seg.joined(separator: "/"))\(seg.isEmpty ? "" : "/")",
                author: nil,
                needsResolve: seg.first == "share" || host == "instagr.am")
        }

        if ttShortHosts.contains(host) || seg.first == "t" {
            return LinkInfo(
                platform: platform, url: "https://\(host)/\(seg.joined(separator: "/"))", author: nil, needsResolve: true)
        }
        if seg.count >= 3, seg[0].hasPrefix("@"), ["video", "photo"].contains(seg[1]) {
            return LinkInfo(
                platform: platform, url: "https://www.tiktok.com/\(seg[0])/\(seg[1])/\(seg[2])",
                author: String(seg[0].dropFirst()).lowercased(), needsResolve: false)
        }
        return LinkInfo(
            platform: platform, url: "https://www.tiktok.com/\(seg.joined(separator: "/"))", author: nil,
            needsResolve: false)
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: group))
        }
    }

    static func hashtags(_ text: String?) -> [String] {
        guard let text = text else { return [] }
        var seen = Set<String>()
        return matches("#([\\p{L}\\p{N}_]+)", in: text, group: 1).map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    private static let stopwords: Set = [
        "this", "that", "with", "from", "your", "have", "what", "when", "will", "just", "like", "them", "they", "then",
        "than", "here", "there", "about", "would", "could", "should", "into", "more", "some", "only", "really",
        "because", "these", "those", "being", "been", "were", "make", "made", "follow", "share", "comment", "link",
        "video", "reels", "reel", "tiktok", "instagram", "viral", "fyp", "foryou", "foryoupage", "explore", "trending",
    ]

    /// Keywords for learning and local matching: hashtags weigh 2, caption words 1.
    static func keywords(_ caption: String?) -> [String: Int] {
        guard let caption = caption, !caption.isEmpty else { return [:] }
        var out: [String: Int] = [:]
        for tag in hashtags(caption) where !stopwords.contains(tag) { out[tag] = 2 }
        let plain = caption.replacingOccurrences(
            of: "[#@][\\p{L}\\p{N}_.]+", with: " ", options: .regularExpression
        ).lowercased()
        for word in matches("\\p{L}{4,}", in: plain) {
            if out.count >= 24 { break }
            if !stopwords.contains(word), out[word] == nil { out[word] = 1 }
        }
        return out
    }
}
