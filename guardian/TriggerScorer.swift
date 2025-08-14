import Foundation
import Combine
import AppKit

enum Verdict: String {
    case unknown
    case onTask
    case offTaskCandidate
    case offTask
}

struct ScorerConfig {
    var graceSeconds: TimeInterval = 20
    var persistenceRequired: Int = 3
    var cooldownSeconds: TimeInterval = 45
}

final class TriggerScorer: ObservableObject {
    static let shared = TriggerScorer()

    // Inputs
    private let ctx = ContextManager.shared
    private var session: SessionManager?

    // Outputs
    @Published var verdict: Verdict = .unknown
    @Published var reason: String = ""
    @Published var lastNudgeAt: Date?
    @Published var consecutiveOffTask: Int = 0

    // Config/state
    var config = ScorerConfig()
    private var cancellables: Set<AnyCancellable> = []
    private var taskKeywords: [String] = []

    // Settings
    private let settings = SettingsManager.shared

    // NEW: AI escalation bus
    let aiRequests = PassthroughSubject<AIInput, Never>()
    private var sessionAllowlist: Set<String> = [] // hosts the AI okayed for this session

    func bind(to session: SessionManager) {
        self.session = session
        setupBindings(session: session)
    }

    private func setupBindings(session: SessionManager) {
        cancellables.removeAll()

        session.$taskTitle
            .combineLatest(session.$mode)
            .sink { [weak self] (title, mode) in
                guard let self else { return }
                self.taskKeywords = Self.extractKeywords(from: title)
                if mode == .idle {
                    self.reset()
                    self.sessionAllowlist.removeAll()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(ctx.$bundleID, ctx.$windowTitleClean, ctx.$urlHost, ctx.$urlCategory)
            .combineLatest(session.$mode, session.$sessionStart)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
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

    // Exposed for AIReasoner
    func overrideOnTaskFromAI(reason: String) {
        consecutiveOffTask = 0
        verdict = .onTask
        self.reason = reason
    }

    func addSessionAllowlist(hosts: [String]) {
        sessionAllowlist.formUnion(hosts.map { $0.lowercased() })
    }

    // MARK: - Core scoring

    private func scoreOnce(sessionStart: Date) {
        let now = Date()
        let elapsed = Int(now.timeIntervalSince(sessionStart))

        // 0) Grace
        if now.timeIntervalSince(sessionStart) < config.graceSeconds {
            verdict = .onTask
            reason = "Within grace (\(Int(config.graceSeconds))s)"
            consecutiveOffTask = 0
            return
        }

        // 1) Features
        let app = ctx.appName.lowercased()
        let title = ctx.windowTitleClean.lowercased()
        let host = ctx.urlHost.lowercased()
        let display = ctx.urlDisplay.lowercased()
        let cat = ctx.urlCategory
        let isBrowser = !host.isEmpty

        // Allowlist short-circuit
        if !host.isEmpty, sessionAllowlist.contains(host) {
            verdict = .onTask
            reason = "AI-allowed host"
            consecutiveOffTask = 0
            return
        }

        let isDevApp = app.contains("xcode")
            || app.contains("code")
            || app.contains("cursor")
            || app.contains("terminal")
            || app.contains("iterm")
            || app.contains("intellij")
            || app.contains("pycharm")

        // 2) Likely on-task
        if isDevApp {
            verdict = .onTask
            reason = "Dev app: \(app)"
            consecutiveOffTask = 0
            return
        }
        if [.coding,.docs,.productivity,.ai,.cloud,.search,.storage].contains(cat) {
            if containsDistractor(title: title, host: host) == false {
                verdict = .onTask
                reason = "Work category: \(cat.rawValue)"
                consecutiveOffTask = 0
                return
            }
        }

        // 3) Task keyword hits
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

        if host.contains("youtube") && !hasKeywordHit {
            looksOffTask = true
            why = "YouTube no task match"
        }

        // NEW: Escalate to AI for ambiguous/off-task candidates (before we finalize)
        if looksOffTask || cat == .other {
            let input = AIInput(
                task: session?.taskTitle ?? "",
                appName: ctx.appName,
                bundleID: ctx.bundleID,
                windowTitle: ctx.windowTitleClean,
                urlHost: ctx.urlHost,
                urlPath: ctx.urlPathShort,
                urlDisplay: ctx.urlDisplay,
                domainCategory: cat.rawValue,
                elapsedSeconds: elapsed
            )
            aiRequests.send(input)
        }

        // 5) Persistence & cooldown → verdict
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

    // MARK: - Text helpers (unchanged)

    private static func extractKeywords(from s: String) -> [String] {
        let lowered = s.lowercased()
        let tokens = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let stop: Set<String> = ["the","and","a","an","to","of","for","on","in","with","at","by","is","are","be","this","that","it","work","session","study","studying","job","jobs","apply","applying"]
        let keywords = tokens.filter { $0.count >= 3 && !stop.contains($0) }
        let expanded = keywords.flatMap { k -> [String] in
            if k.contains("-") { return [k, k.replacingOccurrences(of: "-", with: "")] }
            return [k]
        }
        return Array(Set(expanded))
    }

    private static func matchesAnyKeyword(_ kws: [String], in text: String) -> Bool {
        guard !kws.isEmpty, !text.isEmpty else { return false }
        for k in kws { if text.contains(k) { return true } }
        return false
    }

    private func containsDistractor(title: String, host: String) -> Bool {
        let words = ["trending","memes","highlights","clips","shorts","reels","discover","for you","fyp"]
        for w in words {
            if title.contains(w) || host.contains(w.replacingOccurrences(of: " ", with: "")) { return true }
        }
        return false
    }
}
