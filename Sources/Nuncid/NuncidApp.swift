import AppKit
import CoreGraphics
import SwiftUI

enum NuncidBrand {
    private static var resourceBundles: [Bundle] {
        var bundles = [Bundle.main]
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appendingPathComponent("Nuncid_Nuncid.bundle")
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
        image(named: "nuncid-app-icon-1024") ?? NSApp.applicationIconImage
    }
    static var menuBarIcon: NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        let combined = NSImage(size: targetSize)
        for name in ["nuncid-menubar-18", "nuncid-menubar-36"] {
            guard let source = image(named: name) else { continue }
            for representation in source.representations {
                representation.size = targetSize
                combined.addRepresentation(representation)
            }
        }
        let result = combined.representations.isEmpty
            ? NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Nuncid")!
            : combined
        result.isTemplate = true
        return result
    }
    static var version: String {
#if DEBUG
        if let sourceVersion = try? String(contentsOfFile: "VERSION", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceVersion.isEmpty {
            return sourceVersion
        }
#endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? (try? String(contentsOfFile: "VERSION", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
            ?? "Development"
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var activationPreferences: ActivationPreferences {
        didSet {
            activationPreferences.persist()
            if oldValue.mode != activationPreferences.mode {
                hoverScanningEnabled = false
                hoverMatchFound = false
                coordinator?.resetHoverActivation()
            }
        }
    }
    @Published var presentationPreferences: PresentationPreferences { didSet { presentationPreferences.persist() } }
    @Published var popupInteractionPreferences: PopupInteractionPreferences { didSet { popupInteractionPreferences.persist() } }
    @Published var inspectHotKey: HotKey? { didSet { NuncidPreferences.save(inspectHotKey, key: "inspectHotKey"); configureHotKeys() } }
    @Published var pinHotKey: HotKey? { didSet { NuncidPreferences.save(pinHotKey, key: "pinHotKey"); configureHotKeys() } }
    @Published var hotKeyError: String?
    @Published var screenRecordingGranted: Bool
    @Published var activity = "Ready"
    @Published private(set) var hoverScanningEnabled = false
    @Published private(set) var hoverMatchFound = false

    private let hotKeyMonitor: GlobalHotKeyMonitor
    private var coordinator: HoverCoordinator!
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var versionHistoryWindowController: VersionHistoryWindowController?

    init() {
        let preferences = NuncidPreferences.load()
        var activation = ActivationPreferences.load()
        var presentation = PresentationPreferences.load()
        let popupInteraction = PopupInteractionPreferences.load()
#if DEBUG
        if CommandLine.arguments.contains("--settings-toggle-hover-probe") ||
            CommandLine.arguments.contains("--menu-hover-inactive-probe") ||
            CommandLine.arguments.contains("--menu-hover-active-probe") ||
            CommandLine.arguments.contains("--menu-match-probe") {
            activation.mode = .toggleHover
        }
        if CommandLine.arguments.contains("--settings-appearance-stress-probe") {
            presentation = PresentationPreferences(
                alternativePreviews: 5,
                textSize: .extraLarge,
                width: .wide,
                density: .detailed,
                surface: .solid
            )
        }
#endif
        activationPreferences = activation
        presentationPreferences = presentation
        popupInteractionPreferences = popupInteraction
        inspectHotKey = preferences.inspectHotKey
        pinHotKey = preferences.pinHotKey
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        hotKeyMonitor = GlobalHotKeyMonitor()
        coordinator = HoverCoordinator(appState: self)
        hotKeyMonitor.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .inspect: self.performActivationCommand()
            case .pin: self.coordinator.performPinCommand()
            }
        }
        configureHotKeys()
        coordinator.start()
#if DEBUG
        if CommandLine.arguments.contains("--settings-toggle-hover-probe") ||
            CommandLine.arguments.contains("--menu-hover-active-probe") ||
            CommandLine.arguments.contains("--menu-match-probe") {
            performActivationCommand()
            if CommandLine.arguments.contains("--menu-match-probe") {
                setHoverMatchFound(true)
            }
        }
        if CommandLine.arguments.contains("--settings-probe") || CommandLine.arguments.contains("--settings-capture-probe") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        if CommandLine.arguments.contains("--about-probe") || CommandLine.arguments.contains("--about-capture-probe") {
            DispatchQueue.main.async { [weak self] in self?.openAbout() }
        }
        if CommandLine.arguments.contains("--version-history-probe") ||
            CommandLine.arguments.contains("--version-history-capture-probe") {
            DispatchQueue.main.async { [weak self] in self?.openVersionHistory() }
        }
#endif
    }

    func clearCache() {
        coordinator.clearCache()
        LearnedContextStore.clear()
        activity = "Titles and learned context cleared"
    }
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
#if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--settings-capture-probe"),
           CommandLine.arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsWindowController?.captureProbe(to: url)
            }
        }
#endif
    }
    func openAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController { [weak self] in self?.openVersionHistory() }
        }
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
#if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--about-capture-probe"),
           CommandLine.arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.aboutWindowController?.captureProbe(to: url)
            }
        }
#endif
    }
    func openVersionHistory() {
        if versionHistoryWindowController == nil { versionHistoryWindowController = VersionHistoryWindowController() }
        versionHistoryWindowController?.showWindow(nil)
        versionHistoryWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
#if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--version-history-capture-probe"),
           CommandLine.arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.versionHistoryWindowController?.captureProbe(to: url)
            }
        }
#endif
    }
    func resetActivation() {
        inspectHotKey = .inspect
        activationPreferences = .defaults
    }
    func resetPinHotKey() { pinHotKey = .pin }
    func resetAppearance() { presentationPreferences = .defaults }

    func performActivationCommand() {
        switch ActivationShortcutPolicy.action(for: activationPreferences.mode) {
        case .none:
            activity = "Scanning off"
        case .toggleHover:
            if !hoverScanningEnabled && !screenRecordingGranted {
                requestScreenRecording()
                guard screenRecordingGranted else {
                    activity = "Screen Recording required"
                    return
                }
            }
            hoverScanningEnabled.toggle()
            hoverMatchFound = false
            coordinator.setHoverScanningEnabled(hoverScanningEnabled)
        case .scanOnce:
            coordinator.performInspectCommand()
        }
    }

    func setHoverMatchFound(_ found: Bool) {
        hoverMatchFound = activationPreferences.mode == .toggleHover && hoverScanningEnabled && found
    }

    private func configureHotKeys() {
        guard coordinator != nil else { return }
        if NuncidPreferences.shortcutsConflict(inspect: inspectHotKey, pin: pinHotKey), let inspectHotKey {
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
        #if DEBUG
        let captureHeight: CGFloat = CommandLine.arguments.contains("--settings-tall-capture-probe") ? 780 : 720
        #else
        let captureHeight: CGFloat = 720
        #endif
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: captureHeight), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Nuncid Settings"
        window.titlebarSeparatorStyle = .line
        window.minSize = NSSize(width: 760, height: 650)
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView(state: state))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
#if DEBUG
    func captureProbe(to url: URL) {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }
#endif
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class AboutWindowController: NSWindowController {
    init(onVersionHistory: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About Nuncid"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: AboutView(onVersionHistory: onVersionHistory))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
#if DEBUG
    func captureProbe(to url: URL) {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }
#endif
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class VersionHistoryWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Nuncid Version History"
        window.titlebarSeparatorStyle = .line
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        let view = VersionHistoryView(currentVersion: NuncidBrand.version)
#if DEBUG
        let rootView = CommandLine.arguments.contains("--version-history-dark-probe")
            ? AnyView(view.preferredColorScheme(.dark))
            : AnyView(view)
#else
        let rootView = AnyView(view)
#endif
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        super.init(window: window)
    }
#if DEBUG
    func captureProbe(to url: URL) {
        guard let view = window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }
#endif
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
#if DEBUG
    private var probeOverlay: OverlayController?
    private var probeScanFeedback: [ScanFeedbackController] = []
    private var probeScanBackdrop: NSWindow?
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
        if CommandLine.arguments.contains("--scan-feedback-probe") {
            Task { @MainActor [weak self] in self?.showScanFeedbackProbe() }
        }
        if CommandLine.arguments.contains("--overlay-probe") || CommandLine.arguments.contains("--overlay-stress-probe") {
            let overlay = OverlayController(allowsCapture: true)
            let stress = CommandLine.arguments.contains("--overlay-stress-probe")
            let single = CommandLine.arguments.contains("--overlay-single-probe")
            let minimumStress = CommandLine.arguments.contains("--overlay-minimum-stress-probe")
            let lines: [TicketLine] = minimumStress ? [
                TicketLine(key: "NUNCID-34", state: "in-progress", title: "Make a very small custom card adapt safely to unusually long real-world ticket content", source: "ppm", metadata: "ticket · high priority · release 0.5", detail: "This deliberately long detail verifies that extra-large detailed content remains inside the rounded popup surface even at the minimum remembered dimensions."),
                TicketLine(key: "NUNCID-36", state: "done", title: "Navigate spatially", source: "ppm"),
                TicketLine(key: "NUNCID-35", state: "done", title: "Open the source", source: "ppm")
            ] : single ? [
                TicketLine(key: "NUNCID-36", state: "in-progress", title: "Navigate results spatially", source: "ppm")
            ] : stress ? [
                TicketLine(key: "NUNCID-36", state: "in-progress", title: "Navigate results spatially from anywhere while the current ticket remains fixed and readable", source: "ppm", metadata: "ticket · high priority · release 0.5", detail: "Hold your chosen modifier and scroll from any app, or simply scroll inside the popup. Previous and next destinations move around a stable primary card so every step stays understandable."),
                TicketLine(key: "NUNCID-35", state: "done", title: "Open the source and read every neighboring ID", source: "ppm"),
                TicketLine(key: "#184", state: "review", title: "Keep GitHub pull requests visible", source: "gh"),
                TicketLine(key: "NUNCID-34", state: "done", title: "Remember a custom card size", source: "ppm"),
                TicketLine(key: "NUNCID-33", state: "done", title: "Pin directly without racing the popup", source: "ppm"),
                TicketLine(key: "NUNCID-37", state: "done", title: "Use F19 and other function keys as shortcuts", source: "ppm")
            ] : [
                TicketLine(key: "NUNCID-36", state: "in-progress", title: "Navigate results spatially from anywhere", source: "ppm", metadata: "ticket · high priority", detail: "The current ticket stays fixed while previous and next destinations move around it."),
                TicketLine(key: "NUNCID-35", state: "done", title: "Open the ticket source directly", source: "ppm", metadata: "ticket · medium priority", detail: "The source label is now a clear, quiet link."),
                TicketLine(key: "NUNCID-33", state: "done", title: "Pin without racing the popup", source: "ppm", metadata: "ticket · high priority", detail: "Move into the card and pin it directly.")
            ]
            overlay.show(lines, near: NSEvent.mouseLocation, shortcutLabel: "⌥⇧Space")
            if !CommandLine.arguments.contains("--overlay-temporary-probe") {
                overlay.pin(shortcutLabel: "⌥⇧Space")
            }
            probeOverlay = overlay
            if let index = CommandLine.arguments.firstIndex(of: "--overlay-capture-probe"),
               CommandLine.arguments.indices.contains(index + 1) {
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { overlay.captureProbe(to: url) }
            }
        }
#endif
    }

#if DEBUG
    @MainActor
    private func showScanFeedbackProbe() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = CGSize(width: min(860, screen.visibleFrame.width - 40), height: 260)
        let frame = CGRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let backdrop = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backdrop.level = .floating
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.isOpaque = true
        backdrop.backgroundColor = .windowBackgroundColor
        backdrop.hasShadow = true
        backdrop.sharingType = .readOnly
        backdrop.contentView = NSHostingView(rootView: ScanFeedbackProbeBackdrop())
        backdrop.orderFrontRegardless()
        probeScanBackdrop = backdrop

        // The debug anchors deliberately sit on the visible ticket glyphs so the
        // probe exercises the same spatial relationship as live OCR feedback.
        let centerY = frame.minY + 68
        let invoked = ScanFeedbackController(allowsCapture: true)
        invoked.showDebugInvoked(at: CGPoint(x: frame.minX + frame.width / 6, y: centerY))

        let recognized = ScanFeedbackController(allowsCapture: true)
        let recognizedPrimary = ScanFeedbackAnchor(
            literal: "NUNCID-29",
            bounds: CGRect(x: frame.midX - 94, y: centerY - 10, width: 94, height: 22)
        )
        let recognizedAlternate = ScanFeedbackAnchor(
            literal: "#184",
            bounds: CGRect(x: frame.midX + 24, y: centerY - 10, width: 52, height: 22)
        )
        recognized.showDebugRecognized(
            anchors: [recognizedPrimary, recognizedAlternate],
            selected: recognizedPrimary
        )

        let resolved = ScanFeedbackController(allowsCapture: true)
        resolved.showDebugResolved(anchor: ScanFeedbackAnchor(
            literal: "NUNCID-29",
            bounds: CGRect(x: frame.maxX - frame.width / 6 - 42, y: centerY - 10, width: 84, height: 22)
        ))
        probeScanFeedback = [invoked, recognized, resolved]
    }
#endif
}

#if DEBUG
private struct ScanFeedbackProbeBackdrop: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                phase("1", "INVOKED", "Immediate acknowledgement", ticket: "PAI-843")
                Divider().padding(.vertical, 22)
                phase("2", "RECOGNIZED", "Candidate anchors", ticket: "NUNCID-29     #184")
                Divider().padding(.vertical, 22)
                phase("3", "RESOLVED", "Confirmed ticket", ticket: "NUNCID-29")
            }
            Text("DEBUG VISUAL PROBE · release scan feedback remains capture-excluded")
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18)))
        .padding(8)
    }

    private func phase(_ number: String, _ title: String, _ subtitle: String, ticket: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Text(number)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                Text(title).font(.caption.weight(.bold)).tracking(0.6)
            }
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(ticket)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.bottom, 29)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .padding(.top, 20)
    }
}
#endif

private final class ShortcutRecorderButton: NSButton {
    var hotKey: HotKey?
    var forbiddenHotKey: HotKey?
    var onChange: ((HotKey?) -> Void)?
    var onFeedback: ((PreferenceFeedback?) -> Void)?
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
        let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(from: event.modifierFlags), keyLabel: Self.label(for: event))
        switch ShortcutCapturePolicy.decision(for: candidate, forbiddenHotKey: forbiddenHotKey) {
        case .cancel:
            cancelRecording()
            window?.makeFirstResponder(nil)
        case .clear:
            finish(nil, feedback: .success("Shortcut cleared."))
        case .rejectUnsafe:
            onFeedback?(.problem("Use ⌘, ⌥, or ⌃ with regular keys. Function keys may be used alone.")); NSSound.beep(); return
        case .rejectDuplicate:
            onFeedback?(.problem("Inspect and Pin must use different shortcuts.")); NSSound.beep(); return
        case .accept(let hotKey):
            finish(hotKey, feedback: .success("Shortcut updated."))
        }
    }
    private func finish(_ value: HotKey?, feedback: PreferenceFeedback) {
        recording = false
        hotKey = value
        title = value?.label ?? "Not set"
        bezelColor = nil
        contentTintColor = nil
        onFeedback?(feedback)
        onChange?(value)
        window?.makeFirstResponder(nil)
    }
    private func cancelRecording() {
        recording = false
        title = hotKey?.label ?? "Not set"
        bezelColor = nil
        contentTintColor = nil
        onFeedback?(nil)
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
        if let functionKey = HotKey.functionKeyLabel(for: UInt32(event.keyCode)) { return functionKey }
        let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let name = names[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey?
    let forbiddenHotKey: HotKey?
    @Binding var feedback: PreferenceFeedback?
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(title: hotKey?.label ?? "Not set", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.setButtonType(.momentaryPushIn)
        button.onChange = { hotKey = $0 }; button.onFeedback = { feedback = $0 }
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
    case scanning, pinned, appearance, privacy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .scanning: return "Scanning"
        case .pinned: return "Pinned Card"
        case .appearance: return "Appearance"
        case .privacy: return "Privacy"
        }
    }
    var icon: String {
        switch self {
        case .scanning: return "viewfinder"
        case .pinned: return "pin"
        case .appearance: return "paintbrush"
        case .privacy: return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var selection: SettingsPane = .scanning
    @State private var recorderFeedback: PreferenceFeedback?
    @State private var cacheCleared = false
    @State private var appearanceBeforeReset: PresentationPreferences?

    init(state: AppState) {
        self.state = state
#if DEBUG
        if CommandLine.arguments.contains("--settings-appearance-probe") { _selection = State(initialValue: .appearance) }
        else if CommandLine.arguments.contains("--settings-pinned-probe") { _selection = State(initialValue: .pinned) }
#endif
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, idealWidth: 840, minHeight: 650, idealHeight: 720)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NuncidBrand.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nuncid").font(.headline.weight(.bold))
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
            Button { state.openVersionHistory() } label: {
                Label("Version \(NuncidBrand.version)", systemImage: "clock.arrow.circlepath")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open version history")
            .padding(18)
        }
        .frame(width: 180)
        .background(SidebarMaterial())
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .scanning: scanningPage
        case .pinned: pinnedPage
        case .appearance: appearancePage
        case .privacy: privacyPage
        }
    }

    private var scanningPage: some View {
        SettingsPage(title: "How Nuncid Activates", subtitle: "Choose what the activation shortcut does.") {
            SettingsCard(padding: 0) {
                shortcutRow(icon: "cursorarrow.rays", title: "Activation shortcut", subtitle: "Controls the selected behavior below.", hotKey: $state.inspectHotKey, forbidden: state.pinHotKey)
            }

            SettingsCard {
                SettingsCardHeader(icon: "cursorarrow.motionlines", title: "Shortcut behavior", subtitle: "Choose one clear action for the activation shortcut.")
                Picker("Shortcut behavior", selection: $state.activationPreferences.mode) {
                    ForEach(HoverActivationMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(state.activationPreferences.mode.subtitle)
                    .font(.callout).foregroundStyle(.secondary)

                if state.activationPreferences.mode == .toggleHover {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hover is \(state.hoverScanningEnabled ? "on" : "off")").fontWeight(.medium)
                            Text(state.hoverMatchFound ? "The menu bar icon confirms a ticket was found." : "The menu bar icon shows when hover is active.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(state.hoverScanningEnabled ? "Turn Off" : "Turn On") { state.performActivationCommand() }
                    }
                }

                Divider()
                Toggle(isOn: $state.activationPreferences.scanFeedbackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show scan feedback").fontWeight(.medium)
                        Text("Briefly marks where Nuncid is looking when a scan starts.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(.tint).font(.title3)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your setup").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    setupRow("Behavior", state.activationPreferences.mode.title)
                    setupRow("Shortcut", state.inspectHotKey?.label ?? "Not set")
                    if state.activationPreferences.mode == .toggleHover {
                        setupRow("Hover", state.hoverScanningEnabled ? (state.hoverMatchFound ? "On · ticket found" : "On") : "Off")
                    }
                    setupRow("Scan feedback", state.activationPreferences.scanFeedbackEnabled ? "On" : "Off")
                }
                Spacer()
            }
            .padding(15)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityElement(children: .combine)

            settingsFeedback
            HStack {
                Text("Changes apply immediately—there is no Save button.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Activation Defaults") { state.resetActivation(); recorderFeedback = .success("Activation defaults restored.") }
            }
        }
    }

    private var pinnedPage: some View {
        SettingsPage(title: "Pinned Card", subtitle: "Keep a result on screen and navigate without leaving your work.") {
            SettingsCard(padding: 0) {
                shortcutRow(icon: "pin.fill", title: "Open pinned card", subtitle: "Open, focus, or close the pinned ticket card.", hotKey: $state.pinHotKey, forbidden: state.inspectHotKey)
            }
            settingsFeedback
            SettingsCard {
                SettingsCardHeader(icon: "computermouse", title: "Navigate in place", subtitle: "The pinned card stays focused while you browse or jump directly.")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    interactionHint("Scroll", "Browse found tickets")
                    interactionHint("⇧ Scroll", "Try another project")
                    interactionHint("0–9", "Enter a ticket number")
                    interactionHint("A–Z", "Fuzzy-match a project")
                    interactionHint("Return", "Resolve your entry")
                    interactionHint("Esc", "Revert or close")
                }
                Divider()
                appearanceRow("Scroll from anywhere", detail: "Hold this modifier while a Nuncid popup is visible. Inside the popup, scroll normally.") {
                    Picker("Global scroll modifier", selection: $state.popupInteractionPreferences.scrollModifier) {
                        ForEach(PopupScrollModifier.allCases) { modifier in
                            Text("\(modifier.symbol) \(modifier.title)").tag(modifier)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 150)
                }
            }
            HStack {
                Text("Drag or resize from any edge. Nuncid remembers the card’s position, size, and pin state.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Shortcut Default") { state.resetPinHotKey(); recorderFeedback = .success("Pinned-card shortcut restored.") }
            }
        }
    }

    private var appearancePage: some View {
        SettingsPage(title: "Card Appearance", subtitle: "Tune the ticket card without changing what Nuncid finds.") {
            AppearanceCardPreview(preferences: state.presentationPreferences)
                .frame(maxWidth: .infinity)

            SettingsCard {
                appearanceRow("Visible neighbors", detail: "Shows prior and next wheel destinations around the fixed primary card.") {
                    HStack(spacing: 8) {
                        Text("\(state.presentationPreferences.alternativePreviews)").font(.body.monospacedDigit()).frame(width: 20)
                        Stepper("Visible neighbors", value: $state.presentationPreferences.alternativePreviews, in: 0...6).labelsHidden()
                    }
                }
                Divider()
                presetPicker("Text size", selection: $state.presentationPreferences.textSize, values: CardTextSize.allCases)
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    presetPicker("Card size", selection: $state.presentationPreferences.width, values: CardWidth.allCases)
                    if state.presentationPreferences.width == .custom {
                        Text("Custom · \(Int(state.presentationPreferences.customWidth.rounded())) × \(Int(state.presentationPreferences.customHeight.rounded())) pt")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("Resize any popup from an edge or corner to create a remembered Custom size.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                presetPicker("Content", selection: $state.presentationPreferences.density, values: CardDensity.allCases)
                Divider()
                presetPicker("Surface", selection: $state.presentationPreferences.surface, values: CardSurface.allCases)
            }
            HStack {
                if let previous = appearanceBeforeReset {
                    Label("Appearance defaults restored.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    Button("Undo") { state.presentationPreferences = previous; appearanceBeforeReset = nil }
                } else {
                    Text("The preview uses sample data and never contacts a tracker.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore Appearance Defaults") {
                    appearanceBeforeReset = state.presentationPreferences
                    state.resetAppearance()
                }
                .disabled(state.presentationPreferences == .defaults)
            }
        }
        .onChange(of: state.presentationPreferences) { value in
            if !AppearanceResetPolicy.shouldKeepUndo(previous: appearanceBeforeReset, current: value) {
                appearanceBeforeReset = nil
            }
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
                        Text(state.screenRecordingGranted ? "Nuncid is ready to inspect the small region beneath your pointer." : "Allow access so Nuncid can read ticket identifiers from the screen.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !state.screenRecordingGranted {
                            Button("Open Privacy Settings…") { state.requestScreenRecording() }.padding(.top, 6)
                        }
                    }
                }
            }

            SettingsCard {
                SettingsCardHeader(icon: "lock.laptopcomputer", title: "On-device by design", subtitle: "Nuncid uses Apple Vision locally. Screen pixels never leave your Mac.")
                VStack(spacing: 10) {
                    privacyRow("viewfinder", "Small crop only", "Captures only the area needed to find a ticket ID.")
                    privacyRow("text.viewfinder", "Local OCR", "Recognition runs entirely through Apple Vision.")
                    privacyRow("app.badge", "Foreground app context", "Reads the active app’s bundle identifier and visible window title locally to disambiguate matches.")
                    privacyRow("externaldrive.badge.xmark", "No pixel storage", "Images are never saved, uploaded, or sent to a model.")
                }
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resolved titles & learned context").fontWeight(.medium)
                        Text("Nuncid caches ticket titles and remembers confirmed project or repository choices by the foreground app’s bundle identifier.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(cacheCleared ? "Forgotten" : "Forget Titles & Context") {
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

    @ViewBuilder private var settingsFeedback: some View {
        if let feedback = PreferenceFeedback.resolved(local: recorderFeedback, globalError: state.hotKeyError) {
            Label(feedback.message, systemImage: feedback.severity == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(feedback.severity == .success ? Color.green : Color.orange)
        } else {
            Text("Click the shortcut, press a new combination, or press Delete to clear it. Esc keeps the current value.")
                .font(.caption).foregroundStyle(.secondary)
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
            ShortcutRecorder(hotKey: hotKey, forbiddenHotKey: forbidden, feedback: $recorderFeedback)
                .frame(width: 148, height: 32)
        }
        .padding(16)
    }

    private func setupRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
        .font(.callout)
    }

    private func appearanceRow<Content: View>(_ title: String, detail: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            control()
        }
    }

    private func presetPicker<Value>(_ title: String, selection: Binding<Value>, values: [Value]) -> some View where Value: Hashable & Identifiable, Value.ID == String {
        HStack {
            Text(title).fontWeight(.medium)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values) { value in Text(presetTitle(value)).tag(value) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 330)
        }
    }

    private func presetTitle<Value>(_ value: Value) -> String {
        if let value = value as? CardTextSize { return value.title }
        if let value = value as? CardWidth { return value.title }
        if let value = value as? CardDensity { return value.title }
        if let value = value as? CardSurface { return value.title }
        return String(describing: value)
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

}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
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
    let onVersionHistory: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NuncidBrand.appIcon).resizable().interpolation(.high).frame(width: 112, height: 112)
            Text("Nuncid").font(.largeTitle.weight(.bold))
            Text("Pronounced NUN-sid").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
            Text("Ticket context, right where you point.").font(.headline).foregroundStyle(.secondary)
            Text("Version \(NuncidBrand.version)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button("Version History…", action: onVersionHistory)
            Text("Reads a tiny on-screen region locally and resolves real PPM, PMA, and GitHub records—never invented placeholders.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
            Divider().frame(width: 250)
            HStack(spacing: 4) {
                Text("Open source under")
                Link("GNU AGPL v3.0", destination: URL(string: "https://github.com/markus-barta/nuncid/blob/main/LICENSE")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@main struct NuncidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    var body: some Scene {
        MenuBarExtra {
            Text(state.screenRecordingGranted ? state.activity : "Screen Recording required").lineLimit(1)
            if state.activationPreferences.mode == .toggleHover {
                Label(
                    state.hoverScanningEnabled
                        ? (state.hoverMatchFound ? "Hover On · Ticket Found" : "Hover On")
                        : "Hover Off",
                    systemImage: state.hoverMatchFound ? "checkmark.circle.fill" : (state.hoverScanningEnabled ? "circle.inset.filled" : "circle")
                )
                Button(state.hoverScanningEnabled ? "Turn Hover Off" : "Turn Hover On") { state.performActivationCommand() }
            }
            if let hotKeyError = state.hotKeyError {
                Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
            } else {
                if let inspect = state.inspectHotKey { Text("Activation: \(inspect.label)") }
                if let pin = state.pinHotKey { Text("Pin: \(pin.label)") }
            }
            Divider()
            Picker("Shortcut behavior", selection: $state.activationPreferences.mode) {
                ForEach(HoverActivationMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Divider()
            if !state.screenRecordingGranted { Button("Grant Screen Recording…") { state.requestScreenRecording() } }
            Button("Settings…") { state.openSettings() }.keyboardShortcut(",")
            Button("Version History…") { state.openVersionHistory() }
            Button("About Nuncid") { state.openAbout() }
            Button("Quit Nuncid") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            NuncidMenuBarIcon(
                mode: state.activationPreferences.mode,
                hoverEnabled: state.hoverScanningEnabled,
                matchFound: state.hoverMatchFound
            )
        }
    }
}

private struct NuncidMenuBarIcon: View {
    let mode: HoverActivationMode
    let hoverEnabled: Bool
    let matchFound: Bool
    private var state: HoverMenuBarState {
        .resolve(mode: mode, hoverEnabled: hoverEnabled, matchFound: matchFound)
    }

    var body: some View {
        HStack(spacing: 2) {
            if state == .matchFound {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else if state == .active {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(nsImage: NuncidBrand.menuBarIcon)
                    .renderingMode(.template)
                    .opacity(mode == .pressToScan ? 1 : 0.55)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .active: return "Nuncid, hover on"
        case .matchFound: return "Nuncid, hover on, ticket found"
        case .inactive:
            if mode == .off { return "Nuncid, scanning off" }
            return mode == .pressToScan ? "Nuncid, press to scan" : "Nuncid, hover off"
        }
    }
}
