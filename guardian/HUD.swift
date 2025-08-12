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
        isMovableByWindowBackground = true   // drag anywhere to move
        isExcludedFromWindowsMenu = true
        ignoresMouseEvents = false
        delegate = self

        let host = NSHostingView(rootView: content().ignoresSafeArea())
        host.wantsLayer = true
        contentView = host

        // Place at saved position or default corner
        let startFrame = loadStartFrame() ?? defaultFrame()
        setFrame(startFrame, display: false)
        orderFrontRegardless()
    }

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 800, height: 600)
        let size = NSSize(width: 320, height: 72)
        return NSRect(
            x: screen.maxX - size.width - 16,
            y: screen.maxY - size.height - 16,
            width: size.width, height: size.height
        )
    }

    func setSize(_ size: CGSize, animate: Bool = true) {
        var f = frame
        // anchor bottom-right while resizing
        f.origin.x += (f.width - size.width)
        f.origin.y += (f.height - size.height)
        f.size = size
        setFrame(f, display: true, animate: animate)
        saveOrigin(f.origin)
    }

    // Persist & restore origin
    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: defaultsKey)
    }
    private func loadStartFrame() -> NSRect? {
        guard
            let arr = UserDefaults.standard.array(forKey: defaultsKey) as? [CGFloat],
            arr.count == 2
        else { return nil }
        let size = NSSize(width: 320, height: 72)
        return NSRect(x: arr[0], y: arr[1], width: size.width, height: size.height)
    }

    // Save when user drags the window
    func windowDidMove(_ notification: Notification) {
        saveOrigin(frame.origin)
    }
}

// MARK: - Manager

final class HUDManager: ObservableObject {
    static let shared = HUDManager()
    private var window: HUDWindow?

    @Published var taskTitle: String = ""
    @Published var sessionStart: Date?

    /// Set by the main UI to handle "Stop session" coming from the HUD.
    var onStopRequested: (() -> Void)?

    func show(task: String, start: Date) {
        taskTitle = task
        sessionStart = start
        if window == nil {
            window = HUDWindow {
                HUDView()
                    .environmentObject(self)
            }
        } else {
            window?.orderFrontRegardless()
        }
        // Ensure correct size every time we show
        window?.setSize(CGSize(width: 320, height: 72), animate: false)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
    
    // Add this new method next to `show(...)`
    func showAnimated(from sourceFrame: NSRect, fadeMainWindow: Bool = false) {
        let start = sessionStart ?? Date()
        if window == nil {
            // Create HUD window starting at the main window’s frame
            window = HUDWindow {
                HUDView().environmentObject(self)
            }
            window?.setFrame(sourceFrame, display: false) // start exactly where the main window is
        }

        // target size/pos (top-right). reuse helper by setting final size first
        window?.setSize(CGSize(width: 320, height: 72), animate: false)
        guard let hud = window else { return }

        // compute final rect anchored to screen’s top-right (same as defaultFrame)
        let screen = hud.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let final = NSRect(x: screen.maxX - 320 - 16, y: screen.maxY - 72 - 16, width: 320, height: 72)

        // optionally fade main window (purely cosmetic)
        let main = NSApp.keyWindow
        if fadeMainWindow { main?.animator().alphaValue = 0.85 }

        // ensure HUD is on top and visible, then animate to final rect
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

        // keep model in sync
        taskTitle = taskTitle.isEmpty ? (taskTitle) : taskTitle
        sessionStart = start
    }
}

// MARK: - SwiftUI HUD view

struct HUDView: View {
    @EnvironmentObject var hud: HUDManager

    var body: some View {
        HStack(spacing: 10) {
            ProgressRing(progress: 0.75, size: 24) // decorative placeholder
            VStack(alignment: .leading, spacing: 2) {
                Text(hud.taskTitle.isEmpty ? "Working…" : hud.taskTitle)
                    .font(.headline)
                    .lineLimit(1)
                // Live timer that ticks every second
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
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .onAppear { (NSApp.keyWindow as? HUDWindow)?.setSize(CGSize(width: 320, height: 72)) }
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
                .stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
    
    
}
