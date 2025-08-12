import Foundation

enum TitleNormalizer {
    // Common separators apps use to append their name
    private static let splitTokens: [String] = [
        " - ", " — ", " – ", " | ", " · "
    ]

    // App names (and variants) we want to strip if they appear as suffixes
    private static let appSuffixes: Set<String> = [
        "Google Chrome",
        "Chrome",
        "Safari",
        "Brave",
        "Brave Browser",
        "Arc",
        "Microsoft Edge",
        "Edge"
    ]

    // Some apps put the useful part *after* their name; we can flip for these
    private static let reverseOrderBundles: Set<String> = [
        // add any apps that format like "AppName — Document"
    ]

    /// Cleans window titles like:
    ///   "YouTube - Google Chrome" → "YouTube"
    ///   "LeetCode — Safari" → "LeetCode"
    ///   "README.md — Visual Studio Code" (unchanged by default)
    static func clean(appName: String?, bundleID: String?, rawTitle: String) -> String {
        let title = squishWhitespace(rawTitle)
        guard !title.isEmpty else { return "" }

        // 1) If title contains a known split token, try to drop a trailing app name segment.
        for token in splitTokens {
            if title.contains(token) {
                let parts = title.components(separatedBy: token).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let cleaned = dropAppSuffix(from: parts, appName: appName) {
                    return cleaned
                }
            }
        }

        // 2) Some apps might prefix their name; allow optional reversal (none by default)
        if let bid = bundleID, reverseOrderBundles.contains(bid) {
            for token in splitTokens {
                if title.contains(token) {
                    let parts = title.components(separatedBy: token).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count >= 2 {
                        // flip first/last
                        let flipped = parts.reversed().joined(separator: token)
                        return squishWhitespace(flipped)
                    }
                }
            }
        }

        // 3) Fallback: strip exact app name if it appears at the very end after a dash
        if let app = appName, let trimmed = stripTrailingAppName(title, appName: app) {
            return trimmed
        }

        return title
    }

    // MARK: - Helpers

    private static func dropAppSuffix(from parts: [String], appName: String?) -> String? {
        guard parts.count >= 2 else { return nil }
        let last = parts.last!.trimmingCharacters(in: .whitespaces)
        let lastLower = last.lowercased()
        let appLower = (appName ?? "").lowercased()

        // If the last segment is the app name or an alias, drop it.
        if !appLower.isEmpty, lastLower == appLower { return parts.dropLast().joined(separator: " - ") }
        if appSuffixes.contains(last) { return parts.dropLast().joined(separator: " - ") }

        // Also handle patterns like "Something – Safari Technology Preview"
        if lastLower.hasPrefix("safari") || lastLower.hasPrefix("google chrome") ||
            lastLower.hasPrefix("brave") || lastLower.hasPrefix("arc") ||
            lastLower.hasPrefix("microsoft edge") || lastLower == "edge" {
            return parts.dropLast().joined(separator: " - ")
        }

        return nil
    }

    private static func stripTrailingAppName(_ title: String, appName: String) -> String? {
        // Matches " — App", " - App", " | App"
        let patterns = [
            " — \(NSRegularExpression.escapedPattern(for: appName))$",
            " - \(NSRegularExpression.escapedPattern(for: appName))$",
            " \\| \(NSRegularExpression.escapedPattern(for: appName))$"
        ]
        for pat in patterns {
            if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if re.firstMatch(in: title, options: [], range: range) != nil {
                    let cleaned = re.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
                    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private static func squishWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
