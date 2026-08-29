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
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? (try? String(contentsOfFile: "VERSION", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
            ?? "Development"
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
        if GlintPreferences.shortcutsConflict(inspect: inspectHotKey, pin: pinHotKey), let inspectHotKey {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "GLINT Settings"
        window.titlebarSeparatorStyle = .line
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

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, recording { cancelRecording() }
        return didResign
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        title = "Press shortcut…"
        bezelColor = .controlAccentColor
        contentTintColor = .white
        window?.makeFirstResponder(self)
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
        recording = false
        hotKey = value
        title = value?.label ?? "Not set"
        bezelColor = nil
        contentTintColor = nil
        onValidation?(nil)
        onChange?(value)
        window?.makeFirstResponder(nil)
    }
    private func cancelRecording() {
        recording = false
        title = hotKey?.label ?? "Not set"
        bezelColor = nil
        contentTintColor = nil
        onValidation?(nil)
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
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.setButtonType(.momentaryPushIn)
        button.onChange = { hotKey = $0 }; button.onValidation = { validationMessage = $0 }
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.hotKey = hotKey
        button.forbiddenHotKey = forbiddenHotKey
        if button.window?.firstResponder !== button {
            button.title = hotKey?.label ?? "Not set"
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, privacy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var selection: SettingsPane = .general
    @State private var recorderMessage: String?
    @State private var cacheCleared = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 540)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: GlintBrand.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 0) {
                    Text("GLINT").font(.headline.weight(.bold))
                    Text("Settings").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button { selection = pane } label: {
                        Label(pane.title, systemImage: pane.icon)
                            .font(.body.weight(selection == pane ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == pane ? Color.white : Color.primary)
                    .background(selection == pane ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityAddTraits(selection == pane ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("Version \(GlintBrand.version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(18)
        }
        .frame(width: 180)
        .background(SidebarMaterial())
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: generalPage
        case .shortcuts: shortcutsPage
        case .privacy: privacyPage
        }
    }

    private var generalPage: some View {
        SettingsPage(title: "General", subtitle: "Choose when GLINT reads and learn the pinned controls.") {
            SettingsCard {
                SettingsCardHeader(icon: "eye", title: "Automatic reading", subtitle: "When should GLINT inspect the ticket beneath your pointer?")
                VStack(spacing: 4) {
                    ForEach(TriggerMode.allCases) { mode in
                        Button { state.triggerMode = mode } label: {
                            HStack(spacing: 11) {
                                Image(systemName: state.triggerMode == mode ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(state.triggerMode == mode ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.label).fontWeight(.medium)
                                    Text(triggerDescription(mode)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(state.triggerMode == mode ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }

            SettingsCard {
                SettingsCardHeader(icon: "pin", title: "Pinned navigator", subtitle: "Once pinned, the card becomes a fast ticket navigator.")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    interactionHint("Scroll", "Browse found tickets")
                    interactionHint("⇧ Scroll", "Try another project")
                    interactionHint("0–9", "Enter a ticket number")
                    interactionHint("A–Z", "Fuzzy-match a project")
                    interactionHint("Return", "Resolve your entry")
                    interactionHint("Esc", "Revert or close")
                }
            }
        }
    }

    private var shortcutsPage: some View {
        SettingsPage(title: "Keyboard Shortcuts", subtitle: "Control GLINT without breaking your flow.") {
            SettingsCard(padding: 0) {
                shortcutRow(icon: "cursorarrow.rays", title: "Inspect at pointer", subtitle: "Read the ticket beneath your cursor.", hotKey: $state.inspectHotKey, forbidden: state.pinHotKey)
                Divider().padding(.leading, 66)
                shortcutRow(icon: "pin.fill", title: "Open pinned card", subtitle: "Open, focus, or close the pinned ticket card.", hotKey: $state.pinHotKey, forbidden: state.inspectHotKey)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Click a shortcut, then press a new key combination. Delete clears it; Esc keeps the current value.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = recorderMessage ?? state.hotKeyError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Restore Defaults") { state.resetHotKeys() }
                    Spacer()
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var privacyPage: some View {
        SettingsPage(title: "Privacy", subtitle: "Screen understanding stays on your Mac.") {
            SettingsCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: state.screenRecordingGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.screenRecordingGranted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.screenRecordingGranted ? "Screen Recording is allowed" : "Screen Recording permission is required")
                            .font(.headline)
                        Text(state.screenRecordingGranted ? "GLINT is ready to inspect the small region beneath your pointer." : "Allow access so GLINT can read ticket identifiers from the screen.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !state.screenRecordingGranted {
                            Button("Open Privacy Settings…") { state.requestScreenRecording() }.padding(.top, 6)
                        }
                    }
                }
            }

            SettingsCard {
                SettingsCardHeader(icon: "lock.laptopcomputer", title: "On-device by design", subtitle: "GLINT uses Apple Vision locally. Screen pixels never leave your Mac.")
                VStack(spacing: 10) {
                    privacyRow("viewfinder", "Small crop only", "Captures only the area needed to find a ticket ID.")
                    privacyRow("text.viewfinder", "Local OCR", "Recognition runs entirely through Apple Vision.")
                    privacyRow("externaldrive.badge.xmark", "No pixel storage", "Images are never saved, uploaded, or sent to a model.")
                }
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resolved title cache").fontWeight(.medium)
                        Text("Clear locally cached ticket titles if they look stale.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(cacheCleared ? "Cleared" : "Clear Cache") {
                        state.clearCache()
                        cacheCleared = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            cacheCleared = false
                        }
                    }
                    .disabled(cacheCleared)
                }
            }
        }
    }

    private func shortcutRow(icon: String, title: String, subtitle: String, hotKey: Binding<HotKey?>, forbidden: HotKey?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            ShortcutRecorder(hotKey: hotKey, forbiddenHotKey: forbidden, validationMessage: $recorderMessage)
                .frame(width: 148, height: 32)
        }
        .padding(16)
    }

    private func interactionHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 9) {
            Text(key)
                .font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.1)))
            Text(action).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func privacyRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func triggerDescription(_ mode: TriggerMode) -> String {
        switch mode {
        case .dwell: return "Read after your pointer rests briefly on a ticket."
        case .option: return "Read only while you hold the Option key."
        case .always: return "Continuously follow the ticket beneath your pointer."
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }
}

private struct SettingsCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.10)))
            .shadow(color: Color.black.opacity(0.035), radius: 2, y: 1)
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct SettingsCardHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: GlintBrand.appIcon).resizable().interpolation(.high).frame(width: 112, height: 112)
            Text("GLINT").font(.largeTitle.weight(.bold))
            Text("Ticket context, right where you point.").font(.headline).foregroundStyle(.secondary)
            Text("Version \(GlintBrand.version)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
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
