import Foundation

struct ParsedURL: Equatable {
    let original: String
    let host: String                 // e.g., "leetcode.com"
    let path: String                 // full path without query/fragment, leading "/"
    let pathShort: String            // first 1–2 segments, e.g., "/problems/two-sum"
    let display: String              // host + pathShort, e.g., "leetcode.com/problems/two-sum"
    let canonical: String            // host + path (no scheme/query/fragment)
}

enum URLUtils {
    /// Normalize a URL string into stable parts for display and scoring.
    static func normalize(_ input: String?) -> ParsedURL? {
        guard var s = input?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        // If string has no scheme but looks like a host, try adding "https://"
        if URL(string: s)?.host == nil, s.contains(".") && !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "https://" + s
        }

        guard var comps = URLComponents(string: s), var host = comps.host?.lowercased() else { return nil }

        // Strip "www."
        if host.hasPrefix("www.") { host.removeFirst(4) }

        // Remove default ports
        comps.port = nil

        // Keep only selected query params for known sites; else drop all
        let keepKeys = keepQueryKeys(for: host)
        if let items = comps.queryItems, !items.isEmpty {
            let kept = items.filter { item in
                if let name = item.name.lowercased() as String? {
                    if keepKeys.contains(name) { return true }
                    // drop common trackers
                    if name.hasPrefix("utm_") || name == "gclid" || name == "fbclid" || name == "mc_eid" { return false }
                }
                return false
            }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // Drop fragment
        comps.fragment = nil

        // Build clean URL from components (scheme-less)
        let fullPath = normalizedPath(from: comps.percentEncodedPath)
        let shortPath = shortPath(from: fullPath)

        // Canonical and display strings
        let canonical = host + fullPath
        let display = host + shortPath

        return ParsedURL(
            original: input ?? "",
            host: host,
            path: fullPath,
            pathShort: shortPath,
            display: display,
            canonical: canonical
        )
    }

    // MARK: - Helpers

    private static func normalizedPath(from percentEncodedPath: String) -> String {
        // Percent-decoding helps rules, but keep it safe
        let decoded = percentEncodedPath.removingPercentEncoding ?? percentEncodedPath
        // Ensure single leading slash, collapse duplicate slashes, trim trailing slash (except root)
        var p = decoded
        if !p.hasPrefix("/") { p = "/" + p }
        while p.contains("//") { p = p.replacingOccurrences(of: "//", with: "/") }
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private static func shortPath(from path: String, keepSegments: Int = 2) -> String {
        guard path != "/" else { return "" }
        let segs = path.split(separator: "/").map(String.init)
        if segs.isEmpty { return "" }
        let kept = segs.prefix(keepSegments).joined(separator: "/")
        return kept.isEmpty ? "" : "/" + kept
    }

    /// Return query parameter keys we should preserve for known hosts.
    private static func keepQueryKeys(for host: String) -> Set<String> {
        switch host {
        case "youtube.com", "m.youtube.com", "youtu.be":
            return ["v", "list", "t"] // video id, playlist id, timestamp
        case "google.com":
            return ["q"] // search query
        default:
            return []    // drop everything else by default
        }
    }
}
