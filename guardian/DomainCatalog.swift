import Foundation

enum DomainCategory: String, Codable, CaseIterable {
    case coding, docs, learning, video, social, search, email, messaging, shopping
    case news, music, gaming, finance, cloud, ai, productivity, storage, other
}

final class DomainCatalog {
    static let shared = DomainCatalog()

    // Core domain → category map (can be overridden by JSON on disk)
    private var map: [String: DomainCategory] = defaultMap

    private init() {
        loadOverridesFromDisk() // optional user overrides
    }

    /// Return a category for a given host + path.
    /// Tries exact host, then progressively strips leftmost subdomains (e.g. a.b.c.com → c.com).
    /// Falls back to simple heuristics (e.g. youtube.com → video, google.com/search → search).
    func category(forHost host: String, path: String = "/") -> DomainCategory {
        let h = host.lowercased()

        // 1) Exact host
        if let c = map[h] { return c }

        // 2) Try suffixes (strip leftmost subdomains)
        let parts = h.split(separator: ".").map(String.init)
        if parts.count >= 3 {
            for i in 1..<(parts.count - 1) {
                let suffix = parts[i...].joined(separator: ".")
                if let c = map[suffix] { return c }
            }
        }

        // 3) Heuristics
        switch h {
        case "youtube.com", "m.youtube.com", "youtu.be":
            return .video
        case "google.com":
            if path.hasPrefix("/search") { return .search }
            return .productivity
        case "bing.com", "duckduckgo.com":
            return .search
        default:
            break
        }

        return .other
    }

    /// Allow setting/overriding at runtime (for user settings UI later).
    func setOverride(host: String, category: DomainCategory) {
        map[host.lowercased()] = category
    }

    // MARK: - Persistence (optional overrides)

    private static let overridesFilename = "domain_catalog.json"

    private func overridesURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Guardian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.overridesFilename)
    }

    private func loadOverridesFromDisk() {
        guard let url = overridesURL(), let data = try? Data(contentsOf: url) else { return }
        // Expected JSON: { "host.name": "categoryString", ... }
        if let raw = try? JSONDecoder().decode([String:String].self, from: data) {
            for (k, v) in raw {
                if let cat = DomainCategory(rawValue: v) {
                    map[k.lowercased()] = cat
                }
            }
        }
    }

    // You can export current catalog to help users create an overrides file.
    func exportCurrentCatalogJSON() -> Data? {
        let raw = map.mapValues { $0.rawValue }
        return try? JSONEncoder().encode(raw)
    }

    // MARK: - Seed data

    private static let defaultMap: [String: DomainCategory] = [
        // Coding / Dev
        "leetcode.com": .coding,
        "github.com": .coding,
        "gitlab.com": .coding,
        "bitbucket.org": .coding,
        "stackoverflow.com": .coding,
        "stackexchange.com": .coding,
        "codeforces.com": .coding,
        "hackerrank.com": .coding,
        "geeksforgeeks.org": .coding,
        "replit.com": .coding,

        // Docs / Productivity
        "docs.google.com": .docs,
        "drive.google.com": .storage,
        "notion.so": .docs,
        "notion.site": .docs,
        "confluence.atlassian.com": .docs,
        "dropbox.com": .storage,
        "onedrive.live.com": .storage,
        "evernote.com": .docs,
        "linear.app": .productivity,
        "jira.atlassian.com": .productivity,
        "asana.com": .productivity,
        "clickup.com": .productivity,
        "figma.com": .productivity,

        // AI / Assistants
        "chat.openai.com": .ai,
        "openai.com": .ai,
        "claude.ai": .ai,
        "perplexity.ai": .ai,
        "poe.com": .ai,
        "gemini.google.com": .ai,
        "x.ai": .ai,
        "chatgpt.com": .ai,
        "aistudio.google.com": .ai,

        // Social / Forums
        "twitter.com": .social,
        "x.com": .social,
        "facebook.com": .social,
        "instagram.com": .social,
        "tiktok.com": .social,
        "reddit.com": .social,
        "threads.net": .social,
        "bluesky.social": .social,
        "linkedin.com": .social, // could be productivity depending on user, but default to social

        // Video / Music / Gaming
        "youtube.com": .video,
        "youtu.be": .video,
        "netflix.com": .video,
        "hulu.com": .video,
        "spotify.com": .music,
        "twitch.tv": .video,
        "steampowered.com": .gaming,

        // Messaging / Email
        "mail.google.com": .email,
        "outlook.live.com": .email,
        "discord.com": .messaging,
        "slack.com": .messaging,
        "whatsapp.com": .messaging,
        "messenger.com": .messaging,
        "telegram.org": .messaging,

        // News
        "nytimes.com": .news,
        "wsj.com": .news,
        "bloomberg.com": .news,
        "bbc.com": .news,
        "theverge.com": .news,
        "techcrunch.com": .news,

        // Finance
        "robinhood.com": .finance,
        "coinbase.com": .finance,
        "chase.com": .finance,
        "bankofamerica.com": .finance,

        // Cloud / Dev Tools
        "console.aws.amazon.com": .cloud,
        "cloud.google.com": .cloud,
        "azure.microsoft.com": .cloud,
        "vercel.com": .cloud,
        "supabase.com": .cloud
    ]
}
