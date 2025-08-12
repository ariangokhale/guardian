import Foundation
import Combine

final class SessionManager: ObservableObject {
    enum Mode { case idle, active }

    @Published var mode: Mode = .idle
    @Published var taskTitle: String = ""
    @Published var sessionStart: Date?

    // You can add cooldowns, DND, etc. later

    func startSession(with title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskTitle = trimmed
        sessionStart = Date()
        mode = .active
    }

    func stopSession() {
        mode = .idle
        sessionStart = nil
        // keep last task in field, or clear if you prefer:
        // taskTitle = ""
    }
}
