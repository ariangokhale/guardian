import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Keep the personality only (simplified)
    @Published var nudgeTone: String   // "buddy", "coach", "mean"

    // (Optional: keep for future but don’t surface in UI)
    @Published var personaName: String
    @Published var nudgeEmojis: Bool

    private var bag = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    private init() {
        let savedTone = defaults.string(forKey: "nudgeTone") ?? "buddy"
        nudgeTone = savedTone

        // keep but default quietly
        personaName = defaults.string(forKey: "personaName") ?? ""
        nudgeEmojis = (defaults.object(forKey: "nudgeEmojis") as? Bool) ?? true

        // persist personality + quiet extras
        $nudgeTone.sink { [weak self] v in self?.defaults.set(v, forKey: "nudgeTone") }.store(in: &bag)
        $personaName.sink { [weak self] v in self?.defaults.set(v, forKey: "personaName") }.store(in: &bag)
        $nudgeEmojis.sink { [weak self] v in self?.defaults.set(v, forKey: "nudgeEmojis") }.store(in: &bag)
    }
}
