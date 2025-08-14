import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var session: SessionManager
    @ObservedObject var ctx = ContextManager.shared
    @ObservedObject var scorer = TriggerScorer.shared
    @ObservedObject var settings = SettingsManager.shared

    @State private var localTask: String = ""

    var body: some View {
        VStack(spacing: 18) {
            header

            Group {
                switch session.mode {
                case .idle: idleCard
                case .active: activeCard
                }
            }

            debugPanel
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            localTask = session.taskTitle
            HUDManager.shared.onStopRequested = { [weak session] in session?.stopSession() }
            ContextManager.shared.start()
            TriggerScorer.shared.bind(to: session)
            AIReasoner.shared.bind(to: TriggerScorer.shared, session: session)
        }
        .onDisappear { ContextManager.shared.stop() }
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.accentColor.opacity(0.9), .blue.opacity(0.8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "shield.lefthalf.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.8))
            }
            .frame(width: 32, height: 32)
            Text("Guardian")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Idle Card

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you working on?")
                .font(.title2).bold()

            HStack(spacing: 10) {
                TextField("e.g., Practice LeetCode problems", text: $localTask)
                    .textFieldStyle(PillTextFieldStyle()) // ← custom style from UIStyles.swift

                Button {
                    session.startSession(with: localTask)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Clear") {
                    localTask = ""
                    session.taskTitle = ""
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(18)
        .glassCard()
    }

    // MARK: - Active Card

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session active").font(.title3).bold()
                    Text(session.taskTitle).font(.headline)
                    if let start = session.sessionStart {
                        Text("Started at \(start.formatted(date: .omitted, time: .shortened))")
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Show HUD") {
                        if let start = session.sessionStart {
                            HUDManager.shared.show(task: session.taskTitle, start: start)
                        }
                    }.buttonStyle(SecondaryButtonStyle())

                    Button("Hide HUD") {
                        HUDManager.shared.hide()
                    }.buttonStyle(SecondaryButtonStyle())

                    Button(role: .destructive) {
                        session.stopSession()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }

            Divider().padding(.vertical, 4)

            liveContextBlock
        }
        .padding(18)
        .glassCard()
    }

    // MARK: - Live Context & Scoring

    private var liveContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Context").font(.headline)
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
        }
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Scoring & Diagnostics").font(.headline)
            
            Divider().padding(.vertical, 6)
            Text("Nudge Style").font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Picker("Tone", selection: $settings.nudgeTone) {
                    Text("Buddy").tag("buddy")
                    Text("Coach").tag("coach")
                    Text("Gentle").tag("gentle")
                    Text("Direct").tag("direct")
                }
                .pickerStyle(.segmented)
                Toggle("Emojis", isOn: $settings.nudgeEmojis).toggleStyle(.switch)

                TextField("Persona name (optional)", text: $settings.personaName)
                    .textFieldStyle(PillTextFieldStyle())
                    .frame(maxWidth: 220)
            }
            .font(.callout)


            Group {
                Text("Verdict: \(scorer.verdict.rawValue)")
                Text("Reason: \(scorer.reason)")
                Text("Off-task streak: \(scorer.consecutiveOffTask)")
                Text("Last nudge: \(HUDManager.shared.currentNudge?.text ?? "—")")
            }
            .font(.callout)
            .monospaced()

            Divider().padding(.vertical, 6)
            Text("Scoring Settings").font(.subheadline).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grace (seconds)")
                    Slider(value: $settings.graceSeconds, in: 0...120, step: 5)
                    Text("\(Int(settings.graceSeconds))s").font(.caption).foregroundColor(.secondary)
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
                    Text("\(Int(settings.cooldownSeconds))s").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .font(.callout)
        }
    }
}

// MARK: - Nudge message helper

private func makeNudgeMessage(task: String, ctx: ContextManager, reason: String) -> String {
    if !ctx.urlDisplay.isEmpty { return "Still on \(task)? (\(ctx.urlDisplay))" }
    if !ctx.windowTitleClean.isEmpty { return "Back to \(task)? — \(ctx.windowTitleClean)" }
    return "Still working on \(task)?"
}
