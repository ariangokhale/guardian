import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var graceSeconds: Double
    @Published var persistenceRequired: Int
    @Published var cooldownSeconds: Double
    @Published var nudgeTone: String   // "buddy", "coach", "gentle", "direct"
    @Published var personaName: String // optional, like "Alex"
    @Published var nudgeEmojis: Bool

    private var bag = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    private init() {
        let savedGrace = defaults.double(forKey: "graceSeconds")
        let savedPersistence = defaults.integer(forKey: "persistenceRequired")
        let savedCooldown = defaults.double(forKey: "cooldownSeconds")

        // Initialize stored properties first
        graceSeconds = (savedGrace == 0) ? 20 : savedGrace
        persistenceRequired = (savedPersistence == 0) ? 3 : savedPersistence
        cooldownSeconds = (savedCooldown == 0) ? 45 : savedCooldown
        
        let savedTone = defaults.string(forKey: "nudgeTone") ?? "buddy"
        nudgeTone = savedTone
        personaName = defaults.string(forKey: "personaName") ?? ""
        nudgeEmojis = (defaults.object(forKey: "nudgeEmojis") as? Bool) ?? true
        
        // persist
        $nudgeTone.sink { [weak self] v in self?.defaults.set(v, forKey: "nudgeTone") }.store(in: &bag)
        $personaName.sink { [weak self] v in self?.defaults.set(v, forKey: "personaName") }.store(in: &bag)
        $nudgeEmojis.sink { [weak self] v in self?.defaults.set(v, forKey: "nudgeEmojis") }.store(in: &bag)

        // Now it's safe to use self in the rest of init
        $graceSeconds
            .sink { [weak self] v in self?.defaults.set(v, forKey: "graceSeconds") }
            .store(in: &bag)

        $persistenceRequired
            .sink { [weak self] v in self?.defaults.set(v, forKey: "persistenceRequired") }
            .store(in: &bag)

        $cooldownSeconds
            .sink { [weak self] v in self?.defaults.set(v, forKey: "cooldownSeconds") }
            .store(in: &bag)
    }
}
