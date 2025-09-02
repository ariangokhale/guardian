import Foundation
import Combine
import CryptoKit

struct AIInput: Equatable, Hashable {
    let task: String
    let appName: String
    let bundleID: String
    let windowTitle: String
    let urlHost: String
    let urlPath: String
    let urlDisplay: String
    let domainCategory: String
    let elapsedSeconds: Int

    var hashKey: String {
        let base = [task, appName, bundleID, windowTitle, urlHost, urlPath, domainCategory].joined(separator: "|")
        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

final class AIReasoner {
    static let shared = AIReasoner()
    private var bag = Set<AnyCancellable>()
    private var inFlight: Set<String> = []
    private var recent: [String: Date] = [:]
    private let minGap: TimeInterval = 20
    private let minConfidence: Double = 0.55

    private var isBound = false   // ⬅️ add

    func bind(to scorer: TriggerScorer, session: SessionManager) {
        guard !isBound else { return } // ⬅️ prevent duplicate subscriptions
        isBound = true
        scorer.aiRequests
            // coalesce identical contexts
            .removeDuplicates(by: { $0.hashKey == $1.hashKey })       // ⬅️ new
            .throttle(for: .seconds(1.0), scheduler: RunLoop.main, latest: true) // ⬅️ new
            .filter { [weak self] input in
                guard let self else { return true }
                if let last = recent[input.hashKey], Date().timeIntervalSince(last) < minGap { return false }
                if inFlight.contains(input.hashKey) { return false }
                return true
            }
            .sink { [weak self] input in
                guard let self else { return }
                recent[input.hashKey] = Date()
                inFlight.insert(input.hashKey)
                self.callAI(input: input, scorer: scorer, session: session)
            }
            .store(in: &bag)
    }
    
    private func callAI(input: AIInput, scorer: TriggerScorer, session: SessionManager) {
        let s = SettingsManager.shared
        let req = AIRequest(
            task: input.task,
            appName: input.appName,
            bundleID: input.bundleID,
            windowTitle: input.windowTitle,
            urlHost: input.urlHost,
            urlPath: input.urlPath,
            urlDisplay: input.urlDisplay,
            domainCategory: input.domainCategory,
            elapsedSeconds: input.elapsedSeconds,
            tone: s.nudgeTone,
            personaName: s.personaName,
            useEmojis: s.nudgeEmojis
        )
        
        AIClient.shared.review(req) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(input.hashKey)
                
                switch result {
                case .failure:
                    break
                case .success(let res):
                    switch res.verdict {
                    case .on_task where res.confidence >= self.minConfidence:
                        scorer.overrideOnTaskFromAI(reason: "AI override: \(res.rationale)")
                        if let hosts = res.allowlistHosts { scorer.addSessionAllowlist(hosts: hosts) }
                        
                    case .off_task where res.confidence >= self.minConfidence:
                        // Prefer AI copy; fallback to local if blank
                        let text = res.nudge.isEmpty ? Self.localBuddyLine(for: req) : res.nudge
                        HUDManager.shared.flashNudge(text)
                        SpeechManager.shared.maybeSpeakNudge(text)
                        
                    case .unsure, .on_task, .off_task:
                        break
                    }
                }
            }
        }
    }
    
    // Local fallback generator to keep variety if server doesn’t return copy
    private static func localBuddyLine(for req: AIRequest) -> String {
        let task = req.task.isEmpty ? "your task" : req.task
        let host = req.urlDisplay.isEmpty ? req.urlHost : req.urlDisplay
        let name = req.personaName.trimmingCharacters(in: .whitespaces)
        let prefix: String = {
            switch req.tone {
            case "coach":  return name.isEmpty ? "Quick check" : "\(name) here—quick check"
            case "gentle": return name.isEmpty ? "Hey" : "Hey \(name)"
            case "direct": return name.isEmpty ? "Focus" : "\(name), focus"
            default:       return name.isEmpty ? "Buddy check" : "\(name)"
            }
        }()
        let emoji = req.useEmojis ? " 🔎" : ""
        if !host.isEmpty {
            return "\(prefix): still on \(task)? (\(host))\(emoji)"
        } else if !req.windowTitle.isEmpty {
            return "\(prefix): back to \(task)? — \(req.windowTitle)\(emoji)"
        } else {
            return "\(prefix): stay with \(task)\(emoji)"
        }
    }
}
