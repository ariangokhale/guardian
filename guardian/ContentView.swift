import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var session: SessionManager

    // Shared singletons observed for live debug + updates
    @ObservedObject var ctx = ContextManager.shared
    @ObservedObject var scorer = TriggerScorer.shared
    @ObservedObject var settings = SettingsManager.shared

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
        .frame(minWidth: 720, minHeight: 460)
        .padding(24)
        .onAppear {
            // Sync the input field
            localTask = session.taskTitle

            // Hook HUD stop → session.stopSession
            HUDManager.shared.onStopRequested = { [weak session] in
                session?.stopSession()
            }

            // Start context capture and bind the scorer here (moved from App)
            ContextManager.shared.start()
            TriggerScorer.shared.bind(to: session)
        }
        .onDisappear {
            ContextManager.shared.stop()
        }
        .onChange(of: session.mode) { _, newMode in
            switch newMode {
            case .active:
                if let start = session.sessionStart {
                    if let mainWin = NSApp.keyWindow {
                        HUDManager.shared.taskTitle = session.taskTitle
                        HUDManager.shared.sessionStart = start
                        HUDManager.shared.showAnimated(from: mainWin.frame, fadeMainWindow: false)
                    } else {
                        HUDManager.shared.show(task: session.taskTitle, start: start)
                    }
                }
            case .idle:
                HUDManager.shared.hide()
            }
        }
        // Show a nudge when the scorer declares an off-task verdict
        .onReceive(TriggerScorer.shared.$verdict) { verdict in
            guard session.mode == .active else { return }
            if verdict == .offTask {
                let msg = makeNudgeMessage(
                    task: session.taskTitle,
                    ctx: ContextManager.shared,
                    reason: TriggerScorer.shared.reason
                )
                HUDManager.shared.flashNudge(msg)
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
                Text("Window Title (clean): \(ctx.windowTitleClean)")
                Text("URL Host: \(ctx.urlHost)")
                Text("URL Short: \(ctx.urlPathShort)")
                Text("Browser URL: \(ctx.browserURL)")
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("Domain Category: \(ctx.urlCategory.rawValue)")
            }
            .font(.callout)
            .monospaced()

            Divider().padding(.vertical, 6)

            Group {
                Text("Verdict: \(scorer.verdict.rawValue)")
                Text("Reason: \(scorer.reason)")
                Text("Off-task streak: \(scorer.consecutiveOffTask)")
                Text("Last nudge: \(HUDManager.shared.currentNudge?.text ?? "—")")
            }
            .font(.callout)
            .monospaced()

            // Scoring settings (live-tunable)
            Divider().padding(.vertical, 6)
            Text("Scoring Settings").font(.headline)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grace (seconds)")
                    Slider(value: $settings.graceSeconds, in: 0...120, step: 5)
                    Text("\(Int(settings.graceSeconds))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Persistence (polls)")
                    Stepper(value: $settings.persistenceRequired, in: 1...10) {
                        Text("\(settings.persistenceRequired)x")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cooldown (seconds)")
                    Slider(value: $settings.cooldownSeconds, in: 0...300, step: 5)
                    Text("\(Int(settings.cooldownSeconds))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .font(.callout)
        }
    }
}

// MARK: - Nudge message helper (file-scope)

private func makeNudgeMessage(task: String, ctx: ContextManager, reason: String) -> String {
    if !ctx.urlDisplay.isEmpty {
        return "Still on \(task)? (\(ctx.urlDisplay))"
    }
    if !ctx.windowTitleClean.isEmpty {
        return "Back to \(task)? — \(ctx.windowTitleClean)"
    }
    return "Still working on \(task)?"
}
