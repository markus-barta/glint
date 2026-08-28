import AppKit
import CoreGraphics
import SwiftUI

@MainActor final class AppState: ObservableObject {
    @Published var triggerMode: TriggerMode { didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: "triggerMode") } }
    @Published var stickyModifier: StickyModifier { didSet { UserDefaults.standard.set(stickyModifier.rawValue, forKey: "stickyModifier") } }
    @Published var stickyDoublePressInterval: Double { didSet { UserDefaults.standard.set(stickyDoublePressInterval, forKey: "stickyDoublePressInterval") } }
    @Published var screenRecordingGranted: Bool
    @Published var activity = "Ready"
    private var coordinator: HoverCoordinator!
    private var settingsWindowController: SettingsWindowController?

    init() {
        let preferences = GlintPreferences.load()
        triggerMode = preferences.triggerMode
        stickyModifier = preferences.stickyModifier
        stickyDoublePressInterval = preferences.stickyDoublePressInterval
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        coordinator = HoverCoordinator(appState: self); coordinator.start()
#if DEBUG
        if CommandLine.arguments.contains("--settings-probe") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
#endif
    }
    func clearCache() { coordinator.clearCache(); activity = "Cache cleared" }
    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func openSettings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(state: self) }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor final class SettingsWindowController: NSWindowController {
    init(state: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GLINT Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
#if DEBUG
    private var probeOverlay: OverlayController?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            SelfTests.runAndExit()
        }
#if DEBUG
        if CommandLine.arguments.contains("--permission-status") { print(CGPreflightScreenCaptureAccess() ? "granted" : "missing"); Darwin.exit(0) }
        if let probeIndex = CommandLine.arguments.firstIndex(of: "--resolve-probe"),
           CommandLine.arguments.indices.contains(probeIndex + 1) {
            let raw = CommandLine.arguments[probeIndex + 1].uppercased()
            let context = ResolutionContext.load()
            guard let token = TokenParser.parse([raw]).first,
                  let spec = CandidatePlanner.candidates(for: token, context: context).first else { Darwin.exit(1) }
            Task {
                guard let line = await TicketResolver().resolve(spec) else { Darwin.exit(1) }
                print("\(line.key) | \(line.state) | \(line.title)")
                Darwin.exit(0)
            }
            return
        }
        if CommandLine.arguments.contains("--ocr-probe") {
            guard let plan = CapturePlan.around(NSEvent.mouseLocation) else { Darwin.exit(1) }
            Task { let recognized = await ScreenOCR().recognize(plan: plan); print(recognized.joined(separator: "\n")); Darwin.exit(recognized.isEmpty ? 1 : 0) }
            return
        }
#endif
        NSApp.setActivationPolicy(.accessory)
#if DEBUG
        if CommandLine.arguments.contains("--overlay-probe") {
            let overlay = OverlayController(allowsCapture: true)
            overlay.show([
                GlintLine(
                    key: "GLINT-7",
                    state: "in-progress",
                    title: "Upgrade hover cards, navigation, settings, and versioning",
                    source: "ppm",
                    metadata: "ticket · high priority",
                    detail: "Make the first lookup result immediately legible, keep every additional real result close at hand, and let the user pin the card without losing context."
                ),
                GlintLine(key: "PAI-843", state: "done", title: "Bound startup retention", source: "ppm", metadata: "task · high priority", detail: "A secondary result stays compact until it becomes the focus."),
                GlintLine(key: "#166", state: "merged", title: "Fix bounded retention", source: "gh", metadata: "inspr-at/paimos · @markus", detail: "Pull request details come from GitHub without rewriting."),
            ], near: NSEvent.mouseLocation)
            overlay.pin(shortcutLabel: "⌥ twice")
            probeOverlay = overlay
        }
#endif
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            GroupBox("Reading trigger") {
                Picker("Trigger mode", selection: $state.triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .pickerStyle(.radioGroup)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Pinned result card") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Shortcut", selection: $state.stickyModifier) {
                        ForEach(StickyModifier.allCases) { modifier in
                            Text("Double \(modifier.label)").tag(modifier)
                        }
                    }
                    HStack {
                        Text("Maximum pause")
                        Slider(value: $state.stickyDoublePressInterval, in: 0.20...0.80, step: 0.05)
                        Text(state.stickyDoublePressInterval, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Text("s")
                    }
                    Text("Press \(state.stickyModifier.symbol) twice within this interval to pin the visible card. Repeat the same sequence to close it. Pinning enables scrolling through additional hits.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.screenRecordingGranted ? "Screen Recording is allowed" : "Screen Recording permission is required", systemImage: state.screenRecordingGranted ? "checkmark.shield" : "exclamationmark.triangle")
                    Text("GLINT OCRs a small crop locally with Apple Vision. Pixels are never saved, uploaded, or sent to a model.").foregroundStyle(.secondary)
                    if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Clear title cache") { state.clearCache() }
        }
        .padding(20)
        .frame(width: 520)
    }
}

@main struct GlintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    var body: some Scene {
        MenuBarExtra("GLINT", systemImage: "sparkle.magnifyingglass") {
            Text(state.screenRecordingGranted ? state.activity : "Screen Recording required").lineLimit(1)
            Picker("Trigger", selection: $state.triggerMode) { ForEach(TriggerMode.allCases) { mode in Text(mode.label).tag(mode) } }
            Divider()
            if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
            Button("Settings…") { state.openSettings() }.keyboardShortcut(",")
            Button("Quit GLINT") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
