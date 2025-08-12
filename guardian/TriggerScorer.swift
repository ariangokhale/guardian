import Foundation
import Combine
import AppKit

enum Verdict: String {
    case unknown
    case onTask
    case offTaskCandidate   // locally looks off-task but not persisted yet
    case offTask            // persisted & out of cooldown
}

struct ScorerConfig {
    var graceSeconds: TimeInterval = 20
    var persistenceRequired: Int = 3        // N consecutive off-task polls
    var cooldownSeconds: TimeInterval = 45  // min gap between off-task verdicts
}

final class TriggerScorer: ObservableObject {
    static let shared = TriggerScorer()

    // Inputs (observed)
    private let ctx = ContextManager.shared
    private var session: SessionManager?

    // Outputs (observed in debug UI)
    @Published var verdict: Verdict = .unknown
    @Published var reason: String = ""
    @Published var lastNudgeAt: Date? // when we last *could* have nudged (used for cooldown)
    @Published var consecutiveOffTask: Int = 0

    // Config/state
    var config = ScorerConfig()
    private var cancellables: Set<AnyCancellable> = []
    private var taskKeywords: [String] = []

    // Settings (live-tunable)
    private let settings = SettingsManager.shared

    // Public: bind once per app launch / session object creation
    func bind(to session: SessionManager) {
        self.session = session
        setupBindings(session: session)
    }

    private func setupBindings(session: SessionManager) {
        cancellables.removeAll()

        // Rebuild task keywords when title changes or mode flips
        session.$taskTitle
            .combineLatest(session.$mode)
            .sink { [weak self] (title, mode) in
                guard let self else { return }
                self.taskKeywords = Self.extractKeywords(from: title)
                if mode == .idle {
                    self.reset()
                }
            }
            .store(in: &cancellables)

        // Score every time any relevant context piece changes
        Publishers.CombineLatest4(ctx.$bundleID, ctx.$windowTitleClean, ctx.$urlHost, ctx.$urlCategory)
            .combineLatest(session.$mode, session.$sessionStart)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main) // coalesce bursts
            .sink { [weak self] combined, mode, start in
                guard let self else { return }
                guard mode == .active, let start else {
                    self.verdict = .unknown
                    self.reason = "Session idle"
                    return
                }
                self.scoreOnce(sessionStart: start)
            }
            .store(in: &cancellables)

        // Live-update config from SettingsManager sliders
        settings.$graceSeconds
            .combineLatest(settings.$persistenceRequired, settings.$cooldownSeconds)
            .sink { [weak self] (grace, persist, cool) in
                self?.config.graceSeconds = grace
                self?.config.persistenceRequired = persist
                self?.config.cooldownSeconds = cool
            }
            .store(in: &cancellables)
    }

    private func reset() {
        verdict = .unknown
        reason = ""
        lastNudgeAt = nil
        consecutiveOffTask = 0
    }

    // MARK: - Core scoring

    private func scoreOnce(sessionStart: Date) {
        // 0) Grace period
        let now = Date()
        if now.timeIntervalSince(sessionStart) < config.graceSeconds {
            verdict = .onTask
            reason = "Within grace (\(Int(config.graceSeconds))s)"
            consecutiveOffTask = 0
            return
        }

        // 1) Build features
        let app = ctx.appName.lowercased()
        let title = ctx.windowTitleClean.lowercased()
        let host = ctx.urlHost.lowercased()
        let display = ctx.urlDisplay.lowercased()
        let cat = ctx.urlCategory

        let isBrowser = !host.isEmpty
        let isDevApp = app.contains("xcode")
            || app.contains("code") // VS Code
            || app.contains("cursor")
            || app.contains("terminal")
            || app.contains("iterm")
            || app.contains("intellij")
            || app.contains("pycharm")

        // 2) Quick “likely on-task” checks
        if isDevApp {
            verdict = .onTask
            reason = "Dev app: \(app)"
            consecutiveOffTask = 0
            return
        }
        if cat == .coding || cat == .docs || cat == .productivity || cat == .ai || cat == .cloud || cat == .search || cat == .storage {
            if containsDistractor(title: title, host: host) == false {
                verdict = .onTask
                reason = "Work category: \(cat.rawValue)"
                consecutiveOffTask = 0
                return
            }
        }

        // 3) Keyword match against title/url for task relevance
        let hasKeywordHit = Self.matchesAnyKeyword(taskKeywords, in: title) || Self.matchesAnyKeyword(taskKeywords, in: display)

        // 4) Off-task heuristic
        var looksOffTask = false
        var why = ""

        switch cat {
        case .social, .video, .music, .gaming, .shopping, .news:
            if !hasKeywordHit {
                looksOffTask = true
                why = "Category \(cat.rawValue) w/o task match"
            }
        default:
            if !isBrowser && !isDevApp {
                if title.isEmpty || !hasKeywordHit {
                    looksOffTask = true
                    why = "Non-browser app with no task signal"
                }
            } else if cat == .other && !hasKeywordHit {
                looksOffTask = true
                why = "Other site w/o task match"
            }
        }

        // Special: YouTube edge
        if host.contains("youtube") && !hasKeywordHit {
            looksOffTask = true
            why = "YouTube no task match"
        }

        // 5) Persistence & cooldown -> verdict
        if looksOffTask {
            consecutiveOffTask += 1
            if consecutiveOffTask >= config.persistenceRequired {
                if let last = lastNudgeAt, now.timeIntervalSince(last) < config.cooldownSeconds {
                    verdict = .offTaskCandidate
                    reason = "\(why) (cooldown)"
                } else {
                    verdict = .offTask
                    reason = why
                    lastNudgeAt = now
                    consecutiveOffTask = config.persistenceRequired
                }
            } else {
                verdict = .offTaskCandidate
                reason = "\(why) (\(consecutiveOffTask)/\(config.persistenceRequired))"
            }
        } else {
            consecutiveOffTask = 0
            verdict = .onTask
            reason = hasKeywordHit ? "Task keyword match" : "Neutral"
        }
    }

    // MARK: - Text helpers

    private static func extractKeywords(from s: String) -> [String] {
        let lowered = s.lowercased()
        let tokens = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let stop: Set<String> = ["the","and","a","an","to","of","for","on","in","with","at","by","is","are","be","this","that","it","work","session","study","studying"]
        let keywords = tokens.filter { $0.count >= 3 && !stop.contains($0) }
        let expanded = keywords.flatMap { k -> [String] in
            if k.contains("-") { return [k, k.replacingOccurrences(of: "-", with: "")] }
            return [k]
        }
        return Array(Set(expanded))
    }

    private static func matchesAnyKeyword(_ kws: [String], in text: String) -> Bool {
        guard !kws.isEmpty, !text.isEmpty else { return false }
        for k in kws {
            if text.contains(k) { return true }
        }
        return false
    }

    private func containsDistractor(title: String, host: String) -> Bool {
        let words = ["trending","memes","highlights","clips","shorts","reels","discover","for you","fyp"]
        for w in words {
            if title.contains(w) || host.contains(w.replacingOccurrences(of: " ", with: "")) {
                return true
            }
        }
        return false
    }
}
