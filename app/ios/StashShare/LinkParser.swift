import Foundation

// The same rules live in lib/services/link_parser.dart, lib/services/suggester.dart
// and backend/lib/urls.js — keep them in sync.

struct LinkInfo {
    let platform: String  // "instagram" | "tiktok" | "youtube" | "facebook" | "x" | "other"
    let url: String
    let author: String?
    let needsResolve: Bool
}

enum LinkParser {
    private static let hosts: [(String, Set<String>)] = [
        ("instagram", ["instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am"]),
        ("tiktok", ["tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com", "vt.tiktok.com"]),
        ("youtube", ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"]),
        (
            "facebook",
            [
                "facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com", "mbasic.facebook.com",
                "fb.watch", "fb.com", "www.fb.com",
            ]
        ),
        ("x", ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]),
    ]
    private static let ttShortHosts: Set = ["vm.tiktok.com", "vt.tiktok.com"]
    private static let tracking: Set = [
        "fbclid", "gclid", "igsh", "igshid", "si", "feature", "ref", "ref_src", "ref_url", "mibextid", "rdid",
        "share_id", "share_url", "sfnsn", "is_from_webapp", "sender_device", "web_id",
    ]

    /// "instagram", "tiktok", "youtube", "facebook", "x" or "other".
    static func platform(ofHost host: String) -> String {
        hosts.first { $0.1.contains(host.lowercased()) }?.0 ?? "other"
    }

    private static func parse(_ raw: String) -> URLComponents? {
        guard let comps = URLComponents(string: raw),
            let scheme = comps.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = comps.host, host.contains(".")
        else { return nil }
        return comps
    }

    /// The link in shared text: a known platform's link if there is one,
    /// otherwise the first web link.
    static func extractUrl(_ text: String?) -> String? {
        guard let text = text,
            let re = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+", options: .caseInsensitive)
        else { return nil }
        let ns = text as NSString
        var first: String?
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var raw = ns.substring(with: match.range)
            while let last = raw.last, ").,!?".contains(last) { raw.removeLast() }
            guard let host = parse(raw)?.host else { continue }
            if platform(ofHost: host) != "other" { return raw }
            if first == nil { first = raw }
        }
        return first
    }

    /// `comps` without tracking parameters or fragment; `keep` limits the query to those names.
    private static func clean(_ comps: URLComponents, host: String? = nil, keep: Set<String>? = nil) -> String {
        var out = URLComponents()
        out.scheme = "https"
        out.host = host ?? comps.host?.lowercased()
        out.path = comps.path
        let items = (comps.queryItems ?? []).filter { item in
            if let keep = keep { return keep.contains(item.name) }
            return !(tracking.contains(item.name) || item.name.hasPrefix("utm_"))
        }
        out.queryItems = items.isEmpty ? nil : items
        return out.string ?? ""
    }

    static func youtubeId(_ comps: URLComponents) -> String? {
        let seg = comps.path.split(separator: "/").map(String.init)
        var id: String?
        if comps.host?.lowercased() == "youtu.be" {
            id = seg.first
        } else if seg.first == "watch" {
            id = comps.queryItems?.first { $0.name == "v" }?.value
        } else if seg.count >= 2, ["shorts", "live", "embed", "v"].contains(seg[0]) {
            id = seg[1]
        }
        guard let found = id, found.range(of: "^[A-Za-z0-9_-]{6,20}$", options: .regularExpression) != nil else {
            return nil
        }
        return found
    }

    /// Normalizes a link so the same post always has the same URL; nil if it is not a web link.
    static func canonicalize(_ raw: String) -> LinkInfo? {
        guard let comps = parse(raw), let host = comps.host?.lowercased() else { return nil }
        let platform = platform(ofHost: host)
        let seg = comps.path.split(separator: "/").map(String.init)
        func link(_ url: String, author: String? = nil, needsResolve: Bool = false) -> LinkInfo {
            LinkInfo(platform: platform, url: url, author: author, needsResolve: needsResolve)
        }

        switch platform {
        case "instagram":
            if let i = seg.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }),
                i + 1 < seg.count, seg.first != "share"
            {
                return link("https://www.instagram.com/\(seg[i] == "reels" ? "reel" : seg[i])/\(seg[i + 1])/")
            }
            return link(
                "https://www.instagram.com/\(seg.joined(separator: "/"))\(seg.isEmpty ? "" : "/")",
                needsResolve: seg.first == "share" || host == "instagr.am")
        case "tiktok":
            if ttShortHosts.contains(host) || seg.first == "t" {
                return link("https://\(host)/\(seg.joined(separator: "/"))", needsResolve: true)
            }
            if seg.count >= 3, seg[0].hasPrefix("@"), ["video", "photo"].contains(seg[1]) {
                return link(
                    "https://www.tiktok.com/\(seg[0])/\(seg[1])/\(seg[2])", author: String(seg[0].dropFirst()).lowercased())
            }
            return link("https://www.tiktok.com/\(seg.joined(separator: "/"))")
        case "youtube":
            guard let id = youtubeId(comps) else { return link(clean(comps, host: "www.youtube.com", keep: ["list"])) }
            return link(
                seg.first == "shorts" ? "https://www.youtube.com/shorts/\(id)" : "https://www.youtube.com/watch?v=\(id)")
        case "facebook":
            if host == "fb.watch" { return link(clean(comps, keep: []), needsResolve: true) }
            return link(
                clean(comps, host: "www.facebook.com", keep: ["v", "story_fbid", "id", "fbid"]),
                needsResolve: seg.first == "share")
        case "x":
            if seg.count >= 3, seg[1] == "status" {
                return link("https://x.com/\(seg[0])/status/\(seg[2])", author: seg[0].lowercased())
            }
            return link(clean(comps, host: "x.com"))
        default:
            return link(clean(comps))
        }
    }

    /// What to call the place a post came from: the platform, or the site's name.
    static func sourceLabel(_ link: LinkInfo) -> String {
        switch link.platform {
        case "instagram": return "Instagram"
        case "tiktok": return "TikTok"
        case "youtube": return "YouTube"
        case "facebook": return "Facebook"
        case "x": return "X"
        default:
            let host = URLComponents(string: link.url)?.host ?? "Web"
            return host.replacingOccurrences(of: "^(www|m|mobile)\\.", with: "", options: .regularExpression)
        }
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
