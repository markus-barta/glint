import AppKit
import CoreGraphics
import SwiftUI

private enum GlintBrand {
    private static var resourceBundles: [Bundle] {
        var bundles = [Bundle.main]
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appendingPathComponent("Glint_Glint.bundle")
            if let bundle = Bundle(url: sibling) { bundles.append(bundle) }
        }
        return bundles
    }
    private static func image(named name: String) -> NSImage? {
        for bundle in resourceBundles {
            let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Brand")
                ?? bundle.url(forResource: name, withExtension: "png")
            if let url, let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
    static var appIcon: NSImage {
        image(named: "glint-app-icon-1024") ?? NSApp.applicationIconImage
    }
    static var menuBarIcon: NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let combined = NSImage(size: targetSize)
        for name in ["glint-menubar-18", "glint-menubar-36"] {
            guard let source = image(named: name) else { continue }
            for representation in source.representations {
                representation.size = targetSize
                combined.addRepresentation(representation)
            }
        }
        let result = combined.representations.isEmpty
            ? NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "GLINT")!
            : combined
        result.isTemplate = true
        return result
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var triggerMode: TriggerMode { didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: "triggerMode") } }
    @Published var inspectHotKey: HotKey? { didSet { GlintPreferences.save(inspectHotKey, key: "inspectHotKey"); configureHotKeys() } }
    @Published var pinHotKey: HotKey? { didSet { GlintPreferences.save(pinHotKey, key: "pinHotKey"); configureHotKeys() } }
    @Published var hotKeyError: String?
    @Published var screenRecordingGranted: Bool
    @Published var activity = "Ready"

    private let hotKeyMonitor: GlobalHotKeyMonitor
    private var coordinator: HoverCoordinator!
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?

    init() {
        let preferences = GlintPreferences.load()
        triggerMode = preferences.triggerMode
        inspectHotKey = preferences.inspectHotKey
        pinHotKey = preferences.pinHotKey
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        hotKeyMonitor = GlobalHotKeyMonitor()
        coordinator = HoverCoordinator(appState: self)
        hotKeyMonitor.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .inspect: self.coordinator.performInspectCommand()
            case .pin: self.coordinator.performPinCommand()
            }
        }
        configureHotKeys()
        coordinator.start()
#if DEBUG
        if CommandLine.arguments.contains("--settings-probe") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        if CommandLine.arguments.contains("--about-probe") {
            DispatchQueue.main.async { [weak self] in self?.openAbout() }
        }
#endif
    }

    func clearCache() { coordinator.clearCache(); activity = "Cache cleared" }
    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func openSettings() {
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(state: self) }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func openAbout() {
        if aboutWindowController == nil { aboutWindowController = AboutWindowController() }
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func resetHotKeys() { inspectHotKey = .inspect; pinHotKey = .pin }

    private func configureHotKeys() {
        guard coordinator != nil else { return }
        if let inspectHotKey, inspectHotKey == pinHotKey {
            hotKeyMonitor.configure(inspect: inspectHotKey, pin: nil)
            hotKeyError = ["Inspect and Pin must use different shortcuts.", hotKeyMonitor.errors[.inspect]]
                .compactMap { $0 }.joined(separator: " ")
            return
        }
        hotKeyMonitor.configure(inspect: inspectHotKey, pin: pinHotKey)
        hotKeyError = hotKeyMonitor.errors.values.first
    }
}

@MainActor final class SettingsWindowController: NSWindowController {
    init(state: AppState) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "GLINT Settings"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView(state: state))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About GLINT"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: AboutView())
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
#if DEBUG
    private var probeOverlay: OverlayController?
#endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") { SelfTests.runAndExit() }
#if DEBUG
        if CommandLine.arguments.contains("--permission-status") { print(CGPreflightScreenCaptureAccess() ? "granted" : "missing"); Darwin.exit(0) }
        if let probeIndex = CommandLine.arguments.firstIndex(of: "--resolve-probe"), CommandLine.arguments.indices.contains(probeIndex + 1) {
            let raw = CommandLine.arguments[probeIndex + 1].uppercased()
            let context = ResolutionContext.load()
            guard let token = TokenParser.parse([raw]).first, let spec = CandidatePlanner.candidates(for: token, context: context).first else { Darwin.exit(1) }
            Task {
                guard let line = await TicketResolver().resolve(spec) else { Darwin.exit(1) }
                print("\(line.key) | \(line.state) | \(line.title)"); Darwin.exit(0)
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
                GlintLine(key: "GLINT-12", state: "in-progress", title: "Add configurable global inspect and pin commands", source: "ppm", metadata: "ticket · high priority", detail: "Record any safe system-wide shortcut and open the ticket navigator immediately, without requiring an accessibility permission."),
                GlintLine(key: "GLINT-13", state: "new", title: "Build the docked wheel-driven pinned navigator", source: "ppm", metadata: "ticket · high priority", detail: "A secondary result becomes a full card when selected."),
                GlintLine(key: "GLINT-14", state: "new", title: "Add focused ticket entry and fuzzy project switching", source: "ppm", metadata: "ticket · high priority", detail: "Type a number or a forgiving project abbreviation while the card has focus."),
            ], near: NSEvent.mouseLocation, shortcutLabel: "⌥⇧Space")
            overlay.pin(shortcutLabel: "⌥⇧Space")
            probeOverlay = overlay
        }
#endif
    }
}

private final class ShortcutRecorderButton: NSButton {
    var hotKey: HotKey?
    var forbiddenHotKey: HotKey?
    var onChange: ((HotKey?) -> Void)?
    var onValidation: ((String?) -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true; title = "Type shortcut…"; window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { finish(hotKey); return }
        if event.keyCode == 51 || event.keyCode == 117 { finish(nil); return }
        let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(from: event.modifierFlags), keyLabel: Self.label(for: event))
        guard candidate.isSafeGlobalShortcut else {
            onValidation?("Use ⌘, ⌥, or ⌃ with regular keys. Function keys may be used alone."); NSSound.beep(); return
        }
        guard candidate != forbiddenHotKey else {
            onValidation?("Inspect and Pin must use different shortcuts."); NSSound.beep(); return
        }
        finish(candidate)
    }
    private func finish(_ value: HotKey?) {
        recording = false; hotKey = value; title = value?.label ?? "Not set"; onValidation?(nil); onChange?(value); window?.makeFirstResponder(nil)
    }
    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
    private static func label(for event: NSEvent) -> String {
        let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let name = names[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey?
    let forbiddenHotKey: HotKey?
    @Binding var validationMessage: String?
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(title: hotKey?.label ?? "Not set", target: nil, action: nil)
        button.bezelStyle = .rounded; button.setButtonType(.momentaryPushIn)
        button.onChange = { hotKey = $0 }; button.onValidation = { validationMessage = $0 }
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.hotKey = hotKey; button.forbiddenHotKey = forbiddenHotKey; button.title = hotKey?.label ?? "Not set"
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var recorderMessage: String?
    var body: some View {
        Form {
            HStack(spacing: 12) {
                Image(nsImage: GlintBrand.appIcon).resizable().interpolation(.high).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GLINT").font(.title2.weight(.bold))
                    Text("Ticket context, right where you point.").foregroundStyle(.secondary)
                }
            }
            GroupBox("Automatic reading") {
                Picker("Trigger mode", selection: $state.triggerMode) { ForEach(TriggerMode.allCases) { mode in Text(mode.label).tag(mode) } }
                    .pickerStyle(.radioGroup).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Global shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    shortcutRow("Inspect at pointer", hotKey: $state.inspectHotKey, forbidden: state.pinHotKey)
                    shortcutRow("Open / focus / close pinned", hotKey: $state.pinHotKey, forbidden: state.inspectHotKey)
                    Text("Click a shortcut, then type the new combination. Delete clears it; Esc keeps the old value.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let message = recorderMessage ?? state.hotKeyError {
                        Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    }
                    HStack { Button("Restore defaults") { state.resetHotKeys() }; Spacer(); Text("Defaults: ⌥Space · ⌥⇧Space").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Pinned navigator") {
                Text("Mouse wheel selects another found ticket. Shift-wheel keeps the number and tries another project. While the card is focused, type digits for a ticket number or letters to fuzzy-match a project; Return resolves and Esc reverts or closes.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.screenRecordingGranted ? "Screen Recording is allowed" : "Screen Recording permission is required", systemImage: state.screenRecordingGranted ? "checkmark.shield" : "exclamationmark.triangle")
                    Text("GLINT OCRs a small crop locally with Apple Vision. Pixels are never saved, uploaded, or sent to a model.").foregroundStyle(.secondary)
                    if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Clear title cache") { state.clearCache() }
        }.padding(20).frame(width: 560, height: 600)
    }
    private func shortcutRow(_ title: String, hotKey: Binding<HotKey?>, forbidden: HotKey?) -> some View {
        HStack { Text(title); Spacer(); ShortcutRecorder(hotKey: hotKey, forbiddenHotKey: forbidden, validationMessage: $recorderMessage).frame(width: 150) }
    }
}

private struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? (try? String(contentsOfFile: "VERSION", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "Development"
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: GlintBrand.appIcon).resizable().interpolation(.high).frame(width: 112, height: 112)
            Text("GLINT").font(.largeTitle.weight(.bold))
            Text("Ticket context, right where you point.").font(.headline).foregroundStyle(.secondary)
            Text("Version \(version)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text("Reads a tiny on-screen region locally and resolves real PPM, PMA, and GitHub records—never invented placeholders.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
        }.padding(28).frame(width: 420, height: 360)
    }
}

@main struct GlintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    var body: some Scene {
        MenuBarExtra {
            Text(state.screenRecordingGranted ? state.activity : "Screen Recording required").lineLimit(1)
            if let hotKeyError = state.hotKeyError {
                Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
            } else {
                if let inspect = state.inspectHotKey { Text("Inspect: \(inspect.label)") }
                if let pin = state.pinHotKey { Text("Pin: \(pin.label)") }
            }
            Divider()
            Picker("Trigger", selection: $state.triggerMode) { ForEach(TriggerMode.allCases) { mode in Text(mode.label).tag(mode) } }
            Divider()
            if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
            Button("Settings…") { state.openSettings() }.keyboardShortcut(",")
            Button("About GLINT") { state.openAbout() }
            Button("Quit GLINT") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: GlintBrand.menuBarIcon).renderingMode(.template)
        }
    }
}
