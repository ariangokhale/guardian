import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var session: SessionManager
    @ObservedObject var ctx = ContextManager.shared
    @ObservedObject var scorer = TriggerScorer.shared
    @ObservedObject var settings = SettingsManager.shared

    @State private var localTask: String = ""

    // Feature flag
    private let showDiagnostics = false // Toggle to true for dev/debug

    var body: some View {
        VStack(spacing: 18) {
            header

            Group {
                switch session.mode {
                case .idle: idleCard
                case .active: activeCard
                }
            }

            // Always-visible sections
            messagePersonalization
            timingControls

            // Only show scoring & diagnostics if flag is on
            if showDiagnostics {
                debugPanel
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
        .cleanWindow()
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
                Circle().fill(LinearGradient(colors: [GuardianTheme.primaryOrange, GuardianTheme.primaryOrange.opacity(0.8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "shield.lefthalf.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.8))
            }
            .frame(width: 32, height: 32)
            Text("Guardian")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(GuardianTheme.textPrimary)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Idle Card

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you working on?")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(GuardianTheme.textPrimary)

            HStack(spacing: 10) {
                PlaceholderTextField(placeholder: "e.g., Practice LeetCode problems", text: $localTask)

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
        .cleanCard()
    }

    // MARK: - Active Card

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session active").font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(GuardianTheme.textPrimary)
                    Text(session.taskTitle).font(.headline)
                        .foregroundColor(GuardianTheme.textPrimary)
                    if let start = session.sessionStart {
                        Text("Started at \(start.formatted(date: .omitted, time: .shortened))")
                            .foregroundColor(GuardianTheme.textSecondary).font(.caption)
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
        .cleanCard()
    }

    // MARK: - Live Context

    private var liveContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Context").font(.headline)
                .foregroundColor(GuardianTheme.textPrimary)
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
            .foregroundColor(GuardianTheme.textPrimary)
        }
    }

    // MARK: - Always-visible Message Style & Tone

    private var messagePersonalization: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Message Personalization").font(.headline)
                .foregroundColor(GuardianTheme.textPrimary)

            HStack(spacing: 16) {
                SleekSegmentedPickerStyle(
                    options: [
                        ("Buddy", "buddy"),
                        ("Coach", "coach"),
                        ("Gentle", "gentle"),
                        ("Direct", "direct")
                    ],
                    selection: $settings.nudgeTone
                )

                PlaceholderTextField(placeholder: "Persona name (optional)", text: $settings.personaName)
                    .frame(maxWidth: 220)
            }
            .font(.callout)
        }
    }

    // MARK: - Always-visible Focus Timing

    private var timingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Focus Timing").font(.headline)
                .foregroundColor(GuardianTheme.textPrimary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .center, spacing: 10) {
                    Text("Warm-Up Time")
                        .foregroundColor(GuardianTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                    Slider(value: $settings.graceSeconds, in: 0...120, step: 5)
                        .tint(GuardianTheme.primaryOrange)
                    Text("\(Int(settings.graceSeconds)) seconds before monitoring distractions")
                        .font(.caption).foregroundColor(GuardianTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .timingCard()
                .frame(maxWidth: .infinity)
                VStack(alignment: .center, spacing: 10) {
                    Text("Patience Level")
                        .foregroundColor(GuardianTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 8) {
                        Button(action: { if settings.persistenceRequired > 1 { settings.persistenceRequired -= 1 } }) {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(MiniCapsuleButtonStyle())
                        Text("\(settings.persistenceRequired)")
                            .monospacedDigit()
                            .foregroundColor(GuardianTheme.textPrimary)
                        Button(action: { if settings.persistenceRequired < 10 { settings.persistenceRequired += 1 } }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(MiniCapsuleButtonStyle())
                    }
                    Text("Needs \(settings.persistenceRequired) consecutive off-task checks")
                        .font(.caption)
                        .foregroundColor(GuardianTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .timingCard()
                .frame(maxWidth: .infinity)
                VStack(alignment: .center, spacing: 10) {
                    Text("Quiet Time Between Messages")
                        .foregroundColor(GuardianTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                    Slider(value: $settings.cooldownSeconds, in: 0...300, step: 5)
                        .tint(GuardianTheme.primaryOrange)
                    Text("At least \(Int(settings.cooldownSeconds)) seconds between nudges")
                        .font(.caption)
                        .foregroundColor(GuardianTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .timingCard()
                .frame(maxWidth: .infinity)
            }
            .font(.callout)
        }
    }

    // MARK: - Diagnostics (Optional)

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Scoring & Diagnostics").font(.headline)
                .foregroundColor(GuardianTheme.textPrimary)

            Group {
                Text("Verdict: \(scorer.verdict.rawValue)")
                Text("Reason: \(scorer.reason)")
                Text("Off-task streak: \(scorer.consecutiveOffTask)")
                Text("Last nudge: \(HUDManager.shared.currentNudge?.text ?? "—")")
            }
            .font(.callout)
            .monospaced()
            .foregroundColor(GuardianTheme.textPrimary)
        }
    }
}

// MARK: - Nudge message helper

private func makeNudgeMessage(task: String, ctx: ContextManager, reason: String) -> String {
    if !ctx.urlDisplay.isEmpty { return "Still on \(task)? (\(ctx.urlDisplay))" }
    if !ctx.windowTitleClean.isEmpty { return "Back to \(task)? — \(ctx.windowTitleClean)" }
    return "Still working on \(task)?"
}
