import AppKit
import CoreGraphics
import SwiftUI

@MainActor final class AppState: ObservableObject {
    @Published var triggerMode: TriggerMode { didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: "triggerMode") } }
    @Published var screenRecordingGranted: Bool
    @Published var activity = "Ready"
    private var coordinator: HoverCoordinator!
    init() {
        triggerMode = TriggerMode(rawValue: UserDefaults.standard.string(forKey: "triggerMode") ?? "dwell") ?? .dwell
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        coordinator = HoverCoordinator(appState: self); coordinator.start()
    }
    func clearCache() { coordinator.clearCache(); activity = "Cache cleared" }
    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func openSettings() { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil); NSApp.activate(ignoringOtherApps: true) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Picker("Trigger mode", selection: $state.triggerMode) {
                ForEach(TriggerMode.allCases) { mode in Text(mode.label).tag(mode) }
            }.pickerStyle(.radioGroup)
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.screenRecordingGranted ? "Screen Recording is allowed" : "Screen Recording permission is required", systemImage: state.screenRecordingGranted ? "checkmark.shield" : "exclamationmark.triangle")
                    Text("GLINT OCRs a small crop locally with Apple Vision. Pixels are never saved, uploaded, or sent to a model.").foregroundStyle(.secondary)
                    if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Clear title cache") { state.clearCache() }
        }.padding(20).frame(width: 480)
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
        Settings { SettingsView(state: state) }
    }
}
