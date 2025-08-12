import Foundation
import AppKit
import Combine
import ApplicationServices
import Vision
import CryptoKit

final class ContextManager: ObservableObject {
    static let shared = ContextManager()

    @Published var appName: String = ""
    @Published var bundleID: String = ""
    @Published var windowTitle: String = ""
    @Published var browserURL: String = ""
    @Published var urlHost: String = ""
    @Published var urlPathShort: String = ""
    @Published var urlDisplay: String = ""
    @Published var urlCategory: DomainCategory = .other
    @Published var windowTitleClean: String = ""


    // OCR
    @Published var ocrText: String = ""
    private var lastOCRAt: Date = .distantPast
    private let ocrInterval: TimeInterval = 6.0         // run OCR at most every 6s
    private let ocrMaxChars: Int = 12000                 // cap to keep it lightweight
    private var lastOCRHash: String = ""                 // avoid re-updating unchanged text

    private var timer: Timer?
    private let myBundleID = Bundle.main.bundleIdentifier

    // Remember the last non-Guardian app so button presses (bringing Guardian frontmost)
    // don’t “lose” what we were monitoring. (Keeping for future use; not needed for OCR path now.)
    private var lastNonGuardianBundleID: String?

    // Chromium family bundle IDs we can talk to similarly via AppleScript
    private let chromiumIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.Edge"
    ]

    // MARK: - Public

    func start() {
        // Poll every 1s (you can tune later or switch to event-driven)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.probeOnce()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func captureNow() {
        probeOnce()
    }

    // MARK: - Probe

    private func probeOnce() {
        // 1) Who's frontmost?
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let name = app.localizedName ?? "Unknown"
        let bid  = app.bundleIdentifier ?? ""

        // Track last non-Guardian app (kept for future logic if needed)
        if bid != myBundleID {
            lastNonGuardianBundleID = bid
        }

        // 2) Read the focused window title via AX
        let title = frontWindowTitle(of: app.processIdentifier) ?? ""

        // 3) Update immediate fields
        DispatchQueue.main.async {
            self.appName = name
            self.bundleID = bid
            self.windowTitle = title
            self.windowTitleClean = TitleNormalizer.clean(appName: name, bundleID: bid, rawTitle: title)
        }


        // 4) Only fetch a URL if a *browser* is actually frontmost right now
        if isBrowser(bundleID: bid) {
            fetchActiveTabURL(for: bid) { [weak self] url in
                DispatchQueue.main.async {
                    self?.browserURL = url ?? ""   // keep raw for debugging
                    if let parsed = URLUtils.normalize(url) {
                        self?.urlHost = parsed.host
                        self?.urlPathShort = parsed.pathShort
                        self?.urlDisplay = parsed.display
                        self?.urlCategory = DomainCatalog.shared.category(forHost: parsed.host, path: parsed.path)
                    } else {
                        self?.urlHost = ""
                        self?.urlPathShort = ""
                        self?.urlDisplay = ""
                        self?.urlCategory = .other
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.browserURL = ""
                self.urlHost = ""
                self.urlPathShort = ""
                self.urlDisplay = ""
                self.urlCategory = .other
            }
        }

        // 5) OCR policy (MVP):
        //    - Only when NON-browser is frontmost
        //    - Throttled (every ocrInterval seconds)
        if !isBrowser(bundleID: bid) {
            maybeRunOCR()
        }
    }

    // MARK: - AX Window Title

    private func frontWindowTitle(of pid: pid_t) -> String? {
        let appElem = AXUIElementCreateApplication(pid)

        var windowCF: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &windowCF)
        guard res == .success, let win = windowCF else { return nil }

        var titleCF: CFTypeRef?
        let tRes = AXUIElementCopyAttributeValue((win as! AXUIElement),
                                                 kAXTitleAttribute as CFString,
                                                 &titleCF)
        return (tRes == .success) ? (titleCF as? String) : nil
    }

    // MARK: - Browser URL

    private func isBrowser(bundleID: String) -> Bool {
        chromiumIDs.contains(bundleID) || bundleID == "com.apple.Safari"
    }

    private func isAppRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func runningBrowserBundleIDs() -> [String] {
        var ids: [String] = []
        for id in chromiumIDs.union(["com.apple.Safari"]) {
            if isAppRunning(bundleID: id) { ids.append(id) }
        }
        return ids
    }

    /// Fetch URL off the main thread and return in completion.
    private func fetchActiveTabURL(for bundleID: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.isAppRunning(bundleID: bundleID) else { completion(nil); return }

            func runAppleScript(_ source: String) -> String? {
                var errorDict: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    NSLog("AppleScript: failed to create script")
                    return nil
                }
                let result = script.executeAndReturnError(&errorDict)
                if let errorDict { NSLog("AppleScript error: \(errorDict)") }
                return result.stringValue?.isEmpty == false ? result.stringValue : nil
            }

            var url: String?

            if self.chromiumIDs.contains(bundleID) {
                // Prefer bundle id targeting
                url = runAppleScript(#"""
                tell application id "\#(bundleID)"
                  if (count of windows) = 0 then return ""
                  set theWindow to front window
                  if (count of tabs of theWindow) = 0 then return ""
                  return URL of active tab of theWindow
                end tell
                """#)

                // For regular Chrome, also try "by name" to trigger first-time consent if needed
                if (url ?? "").isEmpty, bundleID == "com.google.Chrome" {
                    url = runAppleScript(#"""
                    tell application "Google Chrome"
                      if (count of windows) = 0 then return ""
                      set theWindow to front window
                      if (count of tabs of theWindow) = 0 then return ""
                      return URL of active tab of theWindow
                    end tell
                    """#)
                }
            } else if bundleID == "com.apple.Safari" {
                url = runAppleScript(#"""
                tell application id "com.apple.Safari"
                  if (count of windows) = 0 then return ""
                  set theTab to current tab of front window
                  return URL of theTab
                end tell
                """#)
            }

            completion((url ?? "").isEmpty ? nil : url)
        }
    }

    // MARK: - OCR

    private func maybeRunOCR() {
        let now = Date()
        guard now.timeIntervalSince(lastOCRAt) >= ocrInterval else { return }
        lastOCRAt = now

        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImg = self.captureMainDisplayImage() else {
                // Likely missing Screen Recording permission
                DispatchQueue.main.async { self.ocrText = "" }
                return
            }
            self.recognizeText(from: cgImg) { raw in
                let cleaned = self.normalizeOCR(raw, max: self.ocrMaxChars)
                let hash = self.sha256String(cleaned)
                guard hash != self.lastOCRHash else { return } // unchanged; skip UI churn
                self.lastOCRHash = hash
                DispatchQueue.main.async { self.ocrText = cleaned }
            }
        }
    }

    /// Full-screen screenshot of visible content (requires Screen Recording permission).
    private func captureMainDisplayImage() -> CGImage? {
        // Swap for ScreenCaptureKit later to capture just the frontmost window/region for better perf.
        let rect = CGRect.infinite
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    /// Run Vision OCR and join results into a single string.
    private func recognizeText(from cgImage: CGImage, completion: @escaping (String) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            let strings: [String] = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            completion(strings.joined(separator: " "))
        }
        request.recognitionLanguages = ["en-US"]  // add more if needed
        request.recognitionLevel = .fast          // use .accurate if you can afford it
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            completion("")
        }
    }

    /// Whitespace cleanup + length cap for OCR text.
    private func normalizeOCR(_ s: String, max: Int) -> String {
        if s.isEmpty { return "" }
        let squished = s
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(squished.prefix(max))
    }

    private func sha256String(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Diagnostics & Consent

    /// Logs which browsers are running and their bundle IDs (helps find the right target).
    func diagnoseRunningBrowsers() {
        let all = chromiumIDs.union(["com.apple.Safari"])
        for id in all.sorted() {
            let running = isAppRunning(bundleID: id)
            NSLog("Browser check: \(id) running=\(running)")
        }
    }

    /// Try each supported browser (if running) *without guards* to force the Automation consent prompt.
    func requestAutomationConsentAllBrowsers() {
        DispatchQueue.global(qos: .userInitiated).async {
            let targets = [
                "com.google.Chrome",
                "com.google.Chrome.canary",
                "com.brave.Browser",
                "company.thebrowser.Browser", // Arc
                "com.microsoft.Edge",
                "com.apple.Safari"
            ]
            for bid in targets where self.isAppRunning(bundleID: bid) {
                var err: NSDictionary?
                let src: String
                if bid == "com.apple.Safari" {
                    src = #"""
                    tell application id "com.apple.Safari"
                      return URL of current tab of front window
                    end tell
                    """#
                } else {
                    src = #"""
                    tell application id "\#(bid)"
                      set theWindow to front window
                      return URL of active tab of theWindow
                    end tell
                    """#
                }
                guard let script = NSAppleScript(source: src) else { continue }
                let result = script.executeAndReturnError(&err)
                if let err { NSLog("FORCE consent error (\(bid)): \(err)") }
                if let s = result.stringValue { NSLog("FORCE consent (\(bid)) returned: \(s)") }
            }
        }
    }

    /// Uses NSWorkspace to launch Chrome if needed, then directly "tells" it to force the prompt.
    func forceAutomationPromptForChrome() {
        let chromeID = "com.google.Chrome"
        ensureAppRunning(bundleID: chromeID) { running in
            guard running else { NSLog("Could not launch Chrome"); return }
            // small delay so a normal tab window is up
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) {
                let src = #"""
                tell application id "com.google.Chrome"
                  try
                    set theWindow to front window
                    return URL of active tab of theWindow
                  on error errMsg number errNum
                    return "ERR:" & errNum & ":" & errMsg
                  end try
                end tell
                """#
                var err: NSDictionary?
                if let script = NSAppleScript(source: src) {
                    let result = script.executeAndReturnError(&err)
                    if let err { NSLog("FORCE Chrome error: \(err)") }
                    if let s = result.stringValue { NSLog("FORCE Chrome returned: \(s)") }
                }
            }
        }
    }

    /// Ensure an app is running by bundle ID; launches it if needed.
    func ensureAppRunning(bundleID: String, completion: @escaping (Bool) -> Void) {
        if isAppRunning(bundleID: bundleID) {
            completion(true); return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion(false); return
        }
        NSWorkspace.shared.openApplication(at: appURL,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: { app, error in
            completion(error == nil && app != nil)
        })
    }
}
