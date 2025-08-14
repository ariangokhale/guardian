import SwiftUI
import AppKit

// MARK: - Window shell

final class HUDWindow: NSPanel, NSWindowDelegate {
    private let defaultsKey = "HUDWindowOrigin"

    init<Content: View>(@ViewBuilder content: () -> Content) {
        let style: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        super.init(contentRect: .zero, styleMask: style, backing: .buffered, defer: true)

        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isExcludedFromWindowsMenu = true
        ignoresMouseEvents = false
        delegate = self

        let host = NSHostingView(rootView: content().ignoresSafeArea())
        host.wantsLayer = true
        contentView = host

        let startFrame = loadStartFrame() ?? defaultFrame()
        setFrame(startFrame, display: false)
        orderFrontRegardless()
    }

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: GuardianTheme.hudWidth, height: GuardianTheme.hudHeightCompact)
        return NSRect(
            x: screen.maxX - size.width - 16,
            y: screen.maxY - size.height - 16,
            width: size.width, height: size.height
        )
    }

    func setSize(_ size: CGSize, animate: Bool = true) {
        var f = frame
        f.origin.x += (f.width - size.width)
        f.origin.y += (f.height - size.height)
        f.size = size
        setFrame(f, display: true, animate: animate)
        saveOrigin(f.origin)
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: defaultsKey)
    }
    private func loadStartFrame() -> NSRect? {
        guard let arr = UserDefaults.standard.array(forKey: defaultsKey) as? [CGFloat], arr.count == 2 else { return nil }
        let size = NSSize(width: GuardianTheme.hudWidth, height: GuardianTheme.hudHeightCompact)
        return NSRect(x: arr[0], y: arr[1], width: size.width, height: size.height)
    }

    func windowDidMove(_ notification: Notification) { saveOrigin(frame.origin) }
}

// MARK: - Manager

struct Nudge: Identifiable, Equatable { let id = UUID(); let text: String }

final class HUDManager: ObservableObject {
    static let shared = HUDManager()
    private var window: HUDWindow?

    private var compactSize: CGSize { .init(width: GuardianTheme.hudWidth, height: GuardianTheme.hudHeightCompact) }
    private var expandedSize: CGSize { .init(width: GuardianTheme.hudWidth, height: GuardianTheme.hudHeightExpanded) }

    @Published var taskTitle: String = ""
    @Published var sessionStart: Date?
    @Published var currentNudge: Nudge?

    var onStopRequested: (() -> Void)?

    // NEW: simple de-dupe + timer management
    private var lastNudges: [String] = []
    private var clearWorkItem: DispatchWorkItem?

    func show(task: String, start: Date) {
        taskTitle = task
        sessionStart = start
        if window == nil {
            window = HUDWindow { HUDView().environmentObject(self) }
        } else {
            window?.orderFrontRegardless()
        }
        window?.setSize(compactSize, animate: false)
    }

    func hide() { window?.orderOut(nil); window = nil }

    func showAnimated(from sourceFrame: NSRect, fadeMainWindow: Bool = false) {
        let start = sessionStart ?? Date()
        if window == nil {
            window = HUDWindow { HUDView().environmentObject(self) }
            window?.setFrame(sourceFrame, display: false)
        }
        window?.setSize(compactSize, animate: false)
        guard let hud = window else { return }

        let screen = hud.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let final = NSRect(x: screen.maxX - compactSize.width - 16, y: screen.maxY - compactSize.height - 16,
                           width: compactSize.width, height: compactSize.height)

        let main = NSApp.keyWindow
        if fadeMainWindow { main?.animator().alphaValue = 0.85 }

        hud.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.allowsImplicitAnimation = true
            ctx.duration = 0.28
            hud.setFrame(final, display: true, animate: true)
        } completionHandler: {
            if fadeMainWindow {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    main?.animator().alphaValue = 1.0
                }
            }
        }

        taskTitle = taskTitle.isEmpty ? taskTitle : taskTitle
        sessionStart = start
    }

    /// Show a temporary nudge.
    /// You can pass `alternatives` (e.g., from AI) and we'll pick a fresh one if possible.
    func flashNudge(_ text: String, alternatives: [String] = [], duration: TimeInterval = 2.5) {
        DispatchQueue.main.async {
            // Pick a message that isn't in the recent history, if possible
            let options = [text] + alternatives
            let chosen = self.pickFresh(from: options)

            // Cancel any pending clear while we replace the message
            self.clearWorkItem?.cancel()

            self.resize(expanded: true)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                self.currentNudge = Nudge(text: chosen)
            }

            // Remember it (keep only recent few)
            self.lastNudges.append(chosen)
            if self.lastNudges.count > 5 { self.lastNudges.removeFirst(self.lastNudges.count - 5) }

            // Schedule clear + collapse
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    // Only clear if unchanged (avoid racing a newer nudge)
                    if self.currentNudge?.text == chosen { self.currentNudge = nil }
                }
                // Collapse slightly after fade to avoid clipping
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    self.resize(expanded: false)
                }
            }
            self.clearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    private func pickFresh(from options: [String]) -> String {
        // Prefer the first option not in recent history; fallback to first
        if let fresh = options.first(where: { !lastNudges.contains($0) && !$0.isEmpty }) {
            return fresh
        }
        return options.first ?? ""
    }

    private func resize(expanded: Bool) {
        window?.setSize(expanded ? expandedSize : compactSize, animate: true)
    }
}

// MARK: - SwiftUI HUD view

struct HUDView: View {
    @EnvironmentObject var hud: HUDManager

    var body: some View {
        VStack(spacing: 8) {
            // Main row
            HStack(spacing: 10) {
                ProgressRing(progress: 0.75, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.taskTitle.isEmpty ? "Working…" : hud.taskTitle)
                        .font(.headline)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        Text(elapsedString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                HUDButton(symbol: "stop.fill") {
                    HUDManager.shared.onStopRequested?()
                    HUDManager.shared.hide()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Divider that appears only when expanded
            if hud.currentNudge != nil {
                Divider().opacity(0.5).padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Message row
            if let nudge = hud.currentNudge {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .imageScale(.small)
                        .opacity(0.85)
                    Text(nudge.text)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.09))
        )
        .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 12)
        .frame(width: GuardianTheme.hudWidth)
        .onAppear { (NSApp.keyWindow as? HUDWindow)?.setSize(CGSize(width: GuardianTheme.hudWidth, height: GuardianTheme.hudHeightCompact)) }
    }

    private var elapsedString: String {
        guard let start = hud.sessionStart else { return "00:00 elapsed" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let m = s / 60, sec = s % 60
        return String(format: "%02d:%02d elapsed", m, sec)
    }
}

// MARK: - Little controls

struct HUDButton: View {
    let symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).imageScale(.small)
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
    }
}

struct ProgressRing: View {
    let progress: CGFloat
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(AngularGradient(gradient: Gradient(colors: [GuardianTheme.accent.opacity(0.95), .blue.opacity(0.9)]), center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
