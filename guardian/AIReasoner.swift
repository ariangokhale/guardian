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
    private var recent: [String: Date] = [:]       // hashKey -> last time asked
    private let minGap: TimeInterval = 20          // don't re-ask within 20s
    private let minConfidence: Double = 0.55       // tweak later or expose in settings
    
    func bind(to scorer: TriggerScorer, session: SessionManager) {
        scorer.aiRequests
            .removeDuplicates()
            .filter { [weak self] input in
                guard let self else { return true }
                // rate-limit by hash + time window
                if let last = recent[input.hashKey], Date().timeIntervalSince(last) < minGap { return false }
                if inFlight.contains(input.hashKey) { return false }
                return true
            }
            .sink { [weak self] input in
                self?.recent[input.hashKey] = Date()
                self?.inFlight.insert(input.hashKey)
                self?.callAI(input: input, scorer: scorer, session: session)
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
