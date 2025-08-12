import SwiftUI
import ApplicationServices

func ensureAXPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}


@main
struct GuardianApp: App {
    @StateObject private var session = SessionManager()

    init() {
        ensureAXPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
