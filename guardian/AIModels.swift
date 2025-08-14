import Foundation

enum AIVerdict: String, Codable {
    case on_task, off_task, unsure
}

struct AIRequest: Codable {
    let task: String
    let appName: String
    let bundleID: String
    let windowTitle: String
    let urlHost: String
    let urlPath: String
    let urlDisplay: String
    let domainCategory: String
    let elapsedSeconds: Int
    // new:
    let tone: String        // "buddy" | "coach" | "gentle" | "direct"
    let personaName: String // optional
    let useEmojis: Bool
}

struct AIResponse: Codable {
    let verdict: AIVerdict
    let confidence: Double           // 0.0 - 1.0
    let nudge: String                // short, friendly, contextual
    let rationale: String            // for debug UI; not shown to user
    let allowlistHosts: [String]?    // optional session allowlist suggestions
    let alternatives: [String]?      // optional extras (server can return or ignore)
}
