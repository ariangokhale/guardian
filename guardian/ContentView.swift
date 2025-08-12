import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionManager
    @ObservedObject var ctx = ContextManager.shared

    @State private var localTask: String = ""

    var body: some View {
        Group {
            switch session.mode {
            case .idle:
                idleView
            case .active:
                activeView
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .padding(24)
        .onAppear {
            localTask = session.taskTitle
            // Hook HUD stop → session.stopSession
            HUDManager.shared.onStopRequested = { [weak session] in
                session?.stopSession()
            }
        }
        .onChange(of: session.mode) { _, newMode in
            switch newMode {
            case .active:
                if let start = session.sessionStart {
                    // grab the current main window frame
                    if let mainWin = NSApp.keyWindow {
                        HUDManager.shared.taskTitle = session.taskTitle
                        HUDManager.shared.sessionStart = start
                        HUDManager.shared.showAnimated(from: mainWin.frame, fadeMainWindow: false)
                    } else {
                        // fallback if we can't find the window (rare)
                        HUDManager.shared.show(task: session.taskTitle, start: start)
                    }
                }
            case .idle:
                HUDManager.shared.hide()
            }
        }

    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you working on?")
                .font(.title)
                .bold()

            TextField("e.g., Studying LeetCode", text: $localTask)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button {
                    session.startSession(with: localTask)
                } label: {
                    Text("Start work session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Clear") {
                    localTask = ""
                    session.taskTitle = ""
                }
            }

            Divider().padding(.vertical, 8)

            debugContextBlock

            Spacer()
        }
    }

    // MARK: - Active (main window stays open to show debug)

    private var activeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session active").font(.title2).bold()
            Text("Task: \(session.taskTitle)").font(.headline)
            if let start = session.sessionStart {
                Text("Started at \(start.formatted(date: .omitted, time: .shortened))")
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Stop session") {
                    session.stopSession()
                }
                .buttonStyle(.bordered)
                Button("Show HUD") {
                    if let start = session.sessionStart {
                        HUDManager.shared.show(task: session.taskTitle, start: start)
                    }
                }
                Button("Hide HUD") {
                    HUDManager.shared.hide()
                }
            }
            .padding(.bottom, 8)

            Divider()

            debugContextBlock

            Spacer()
        }
    }

    // MARK: - Shared debug block

    private var debugContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Context (debug)").font(.headline)
            Group {
                Text("Frontmost App: \(ctx.appName)")
                Text("Bundle ID: \(ctx.bundleID)")
                Text("Window Title: \(ctx.windowTitle)")
                Text("Browser URL: \(ctx.browserURL)")
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .monospaced()
        }
    }
}
