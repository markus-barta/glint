import AppKit
import Combine

enum MenuBarScanOutcome: Equatable {
    case started
    case permissionRequired
}

enum MenuBarPointerClick: Equatable {
    case left(controlKey: Bool)
    case right
}

enum MenuBarClickAction: Equatable {
    case scanOnce
    case openMenu
}

enum MenuBarClickRoutingPolicy {
    static func action(for click: MenuBarPointerClick) -> MenuBarClickAction {
        switch click {
        case let .left(controlKey): return controlKey ? .openMenu : .scanOnce
        case .right: return .openMenu
        }
    }
}

enum MenuBarAccessibilityPolicy {
    static let openMenuActionName = "Open Nuncid menu"
}

enum MenuBarClickRouter {
    static func route(
        _ click: MenuBarPointerClick,
        scanOnce: () -> Void,
        openMenu: () -> Void
    ) {
        switch MenuBarClickRoutingPolicy.action(for: click) {
        case .scanOnce: scanOnce()
        case .openMenu: openMenu()
        }
    }
}

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        var values: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  (component.count == 1 || component.first != "0"),
                  let value = Int(component) else { return nil }
            values.append(value)
        }
        major = values[0]
        minor = values[1]
        patch = values[2]
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
    }
}

enum AppUpdateState: Equatable {
    case checking
    case current
    case available(version: String, url: URL)
    case unavailable

    var menuTitle: String {
        switch self {
        case .checking: return "Checking for updates…"
        case .current: return "Nuncid is up to date"
        case let .available(version, _): return "Update to Version \(version) available"
        case .unavailable: return "Update status unavailable"
        }
    }
}

enum MenuUpdateHeaderPolicy {
    static func titles(installedVersion: String, updateState: AppUpdateState) -> [String] {
        ["Nuncid version \(installedVersion)", updateState.menuTitle]
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

enum CanonicalReleasePolicy {
    static let endpoint = URL(string: "https://api.github.com/repos/markus-barta/nuncid/releases/latest")!

    static func evaluate(
        currentVersion: String,
        data: Data,
        responseURL: URL?,
        statusCode: Int
    ) -> AppUpdateState {
        guard statusCode == 200,
              isExactEndpoint(responseURL),
              let current = SemanticVersion(currentVersion),
              let payload = try? JSONDecoder().decode(GitHubReleasePayload.self, from: data),
              !payload.draft,
              !payload.prerelease,
              let release = releaseVersion(from: payload.tagName),
              let releaseURL = URL(string: payload.htmlURL),
              isCanonicalReleaseURL(releaseURL, tag: payload.tagName) else {
            return .unavailable
        }
        guard release > current else { return .current }
        return .available(version: payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName, url: releaseURL)
    }

    private static func releaseVersion(from tag: String) -> SemanticVersion? {
        let rawVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !rawVersion.isEmpty, tag == rawVersion || tag == "v\(rawVersion)" else { return nil }
        return SemanticVersion(rawVersion)
    }

    static func isExactEndpoint(_ url: URL?) -> Bool {
        guard let components = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return false }
        return components.scheme == "https"
            && components.host?.lowercased() == "api.github.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && components.percentEncodedPath == "/repos/markus-barta/nuncid/releases/latest"
    }

    private static func isCanonicalReleaseURL(_ url: URL, tag: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let expectedPath = "/markus-barta/nuncid/releases/tag/\(tag)"
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && components.percentEncodedPath == expectedPath
    }
}

private final class CanonicalReleaseSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(CanonicalReleasePolicy.isExactEndpoint(request.url) ? request : nil)
    }
}

struct BoundedResponseAccumulator {
    static let releaseMaximumBytes = 128 * 1_024

    let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int = Self.releaseMaximumBytes) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    static func accepts(expectedContentLength: Int64, maximumBytes: Int = releaseMaximumBytes) -> Bool {
        expectedContentLength == NSURLSessionTransferSizeUnknown
            || (expectedContentLength >= 0 && expectedContentLength <= Int64(maximumBytes))
    }

    mutating func append(_ byte: UInt8) -> Bool {
        guard data.count < maximumBytes else { return false }
        data.append(byte)
        return true
    }
}

enum CanonicalReleaseChecker {
    static func check(currentVersion: String) async -> AppUpdateState {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        let session = URLSession(
            configuration: configuration,
            delegate: CanonicalReleaseSessionDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: CanonicalReleasePolicy.endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nuncid/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  CanonicalReleasePolicy.isExactEndpoint(response.url) else { return .unavailable }
            var body = BoundedResponseAccumulator()
            guard BoundedResponseAccumulator.accepts(
                expectedContentLength: response.expectedContentLength,
                maximumBytes: body.maximumBytes
            ) else { return .unavailable }
            for try await byte in bytes {
                guard body.append(byte) else { return .unavailable }
            }
            return CanonicalReleasePolicy.evaluate(
                currentVersion: currentVersion,
                data: body.data,
                responseURL: response.url,
                statusCode: response.statusCode
            )
        } catch {
            return .unavailable
        }
    }
}

@MainActor private final class MenuBarActionTarget: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func perform(_ sender: Any?) { action() }
}

@MainActor final class NuncidStatusItemController: NSObject {
    private let state: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let scanFeedback = MenuBarScanFeedbackController()
    private var cancellables = Set<AnyCancellable>()
    private var menuActionTargets: [MenuBarActionTarget] = []
    private var updateState: AppUpdateState = .checking
    private var updateTask: Task<Void, Never>?
    private var lastUpdateCheckAt = Date.distantPast

    init(state: AppState) {
        self.state = state
        super.init()
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: MenuBarAccessibilityPolicy.openMenuActionName) { [weak self, weak button] in
                guard let self, let button else { return false }
                self.openMenu(from: button)
                return true
            },
        ])
        state.$activationPreferences
            .combineLatest(state.$hoverScanningEnabled, state.$hoverMatchFound)
            .sink { [weak self] preferences, hoverEnabled, matchFound in
                self?.refreshIcon(
                    mode: preferences.mode,
                    hoverEnabled: hoverEnabled,
                    matchFound: matchFound
                )
            }
            .store(in: &cancellables)
        refreshIcon(
            mode: state.activationPreferences.mode,
            hoverEnabled: state.hoverScanningEnabled,
            matchFound: state.hoverMatchFound
        )
        beginUpdateCheck()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let click: MenuBarPointerClick
        switch event.type {
        case .leftMouseUp: click = .left(controlKey: event.modifierFlags.contains(.control))
        case .rightMouseUp: click = .right
        default: return
        }
        MenuBarClickRouter.route(
            click,
            scanOnce: { [weak self] in self?.scanOnce(from: sender) },
            openMenu: { [weak self] in self?.openMenu(from: sender) }
        )
    }

    private func scanOnce(from button: NSStatusBarButton) {
        let outcome = state.performMenuBarScan()
        switch outcome {
        case .started:
            scanFeedback.show(message: "Scanning near pointer…", anchoredTo: button)
        case .permissionRequired:
            scanFeedback.show(message: "Screen Recording required", anchoredTo: button)
        }
    }

    private func openMenu(from button: NSStatusBarButton) {
        if Date().timeIntervalSince(lastUpdateCheckAt) >= 15 * 60 {
            beginUpdateCheck(showCheckingState: false)
        }
        let menu = makeMenu()
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        menuActionTargets.removeAll()
        let menu = NSMenu()

        let headerTitles = MenuUpdateHeaderPolicy.titles(
            installedVersion: NuncidBrand.version,
            updateState: updateState
        )
        addDisabledItem(headerTitles[0], to: menu)
        switch updateState {
        case let .available(_, url):
            addActionItem(headerTitles[1], to: menu) { NSWorkspace.shared.open(url) }
        case .checking, .current, .unavailable:
            addDisabledItem(headerTitles[1], to: menu)
        }
        menu.addItem(.separator())

        addDisabledItem(state.screenRecordingGranted ? state.activity : "Screen Recording required", to: menu)
        if state.activationPreferences.mode == .toggleHover {
            let title = state.hoverScanningEnabled
                ? (state.hoverMatchFound ? "Hover On · Ticket Found" : "Hover On")
                : "Hover Off"
            addDisabledItem(title, image: state.hoverMatchFound
                ? "checkmark.circle.fill"
                : (state.hoverScanningEnabled ? "circle.inset.filled" : "circle"), to: menu)
            addActionItem(state.hoverScanningEnabled ? "Turn Hover Off" : "Turn Hover On", to: menu) { [weak state] in
                state?.performActivationCommand()
            }
        }
        if let hotKeyError = state.hotKeyError {
            addDisabledItem(hotKeyError, image: "exclamationmark.triangle.fill", to: menu)
        } else {
            if let inspect = state.inspectHotKey { addDisabledItem("Activation: \(inspect.label)", to: menu) }
            if let pin = state.pinHotKey { addDisabledItem("Pin: \(pin.label)", to: menu) }
        }
        menu.addItem(.separator())

        let shortcutMenu = NSMenu()
        for mode in HoverActivationMode.allCases {
            let item = addActionItem(mode.title, to: shortcutMenu) { [weak state] in
                state?.activationPreferences.mode = mode
            }
            item.state = state.activationPreferences.mode == mode ? .on : .off
        }
        let shortcutItem = NSMenuItem(title: "Shortcut behavior", action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)
        menu.addItem(.separator())

        if !state.screenRecordingGranted {
            addActionItem("Grant Screen Recording…", to: menu) { [weak state] in state?.requestScreenRecording() }
        }
        addActionItem("Settings…", keyEquivalent: ",", to: menu) { [weak state] in state?.openSettings() }
        addActionItem("Version History…", to: menu) { [weak state] in state?.openVersionHistory() }
        addActionItem("About Nuncid", to: menu) { [weak state] in state?.openAbout() }
        addActionItem("Quit Nuncid", keyEquivalent: "q", to: menu) { NSApp.terminate(nil) }
        return menu
    }

    private func beginUpdateCheck(showCheckingState: Bool = true) {
        updateTask?.cancel()
        if showCheckingState { updateState = .checking }
        lastUpdateCheckAt = Date()
        let currentVersion = NuncidBrand.version
        updateTask = Task { [weak self] in
            let result = await CanonicalReleaseChecker.check(currentVersion: currentVersion)
            guard !Task.isCancelled else { return }
            self?.updateState = result
        }
    }

    private func addDisabledItem(_ title: String, image: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
        menu.addItem(item)
    }

    @discardableResult
    private func addActionItem(
        _ title: String,
        keyEquivalent: String = "",
        to menu: NSMenu,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let target = MenuBarActionTarget(action)
        menuActionTargets.append(target)
        let item = NSMenuItem(title: title, action: #selector(MenuBarActionTarget.perform(_:)), keyEquivalent: keyEquivalent)
        item.target = target
        menu.addItem(item)
        return item
    }

    private func refreshIcon(
        mode: HoverActivationMode,
        hoverEnabled: Bool,
        matchFound: Bool
    ) {
        guard let button = statusItem.button else { return }
        let resolved = HoverMenuBarState.resolve(
            mode: mode,
            hoverEnabled: hoverEnabled,
            matchFound: matchFound
        )
        switch resolved {
        case .matchFound:
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            button.contentTintColor = .systemGreen
            button.setAccessibilityLabel("Nuncid, hover on, ticket found")
        case .active:
            button.image = NSImage(systemSymbolName: "viewfinder.circle.fill", accessibilityDescription: nil)
            button.contentTintColor = .controlAccentColor
            button.setAccessibilityLabel("Nuncid, hover on")
        case .inactive:
            button.image = NuncidBrand.menuBarIcon
            button.contentTintColor = mode == .pressToScan ? .labelColor : .secondaryLabelColor
            let label = mode == .off
                ? "Nuncid, scanning off. Left-click to scan once; right-click for Settings."
                : (mode == .pressToScan
                    ? "Nuncid, press to scan. Left-click to scan once; right-click for Settings."
                    : "Nuncid, hover off. Left-click to scan once; right-click for Settings.")
            button.setAccessibilityLabel(label)
        }
        button.image?.isTemplate = true
        button.toolTip = "Left-click to scan once · Right-click for Settings"
        button.setAccessibilityHelp(
            "Left-click to scan once; right-click, Control-click, or use Open Nuncid menu for Settings and controls."
        )
    }

#if DEBUG
    func captureScanFeedbackProbe(to url: URL) {
        guard let button = statusItem.button else { Darwin.exit(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [scanFeedback] in
            scanFeedback.captureProbe(message: "Scanning near pointer…", anchoredTo: button, to: url)
        }
    }
#endif
}

@MainActor private final class MenuBarScanFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class MenuBarScanFeedbackController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String, anchoredTo button: NSStatusBarButton) {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let panel = makePanel(message: message, reduceMotion: reduceMotion)
        position(panel, below: button)
        self.panel = panel
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            if reduceMotion {
                panel.orderOut(nil)
                self.panel = nil
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 0
                })
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak panel] in
                    panel?.orderOut(nil)
                    if self?.panel === panel { self?.panel = nil }
                }
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    private func makePanel(message: String, reduceMotion: Bool) -> NSPanel {
        let size = NSSize(width: 238, height: 58)
        let panel = MenuBarScanFeedbackPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.sharingType = .none

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: reduceMotion ? "viewfinder" : "sparkle.magnifyingglass", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: message)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let hint = NSTextField(labelWithString: "Right-click for Settings")
        hint.font = .systemFont(ofSize: 10.5, weight: .regular)
        hint.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, hint])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(icon)
        effect.addSubview(labels)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        panel.contentView = effect
        return panel
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: min(max(anchor.midX - panel.frame.width / 2, visibleFrame.minX + 8), visibleFrame.maxX - panel.frame.width - 8),
            y: max(visibleFrame.minY + 8, anchor.minY - panel.frame.height - 8)
        )
        panel.setFrameOrigin(origin)
    }

#if DEBUG
    func captureProbe(message: String, anchoredTo button: NSStatusBarButton, to url: URL) {
        show(message: message, anchoredTo: button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let view = self?.panel?.contentView else { Darwin.exit(1) }
            view.layoutSubtreeIfNeeded()
            guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Darwin.exit(1) }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else { Darwin.exit(1) }
            do {
                try data.write(to: url, options: .atomic)
                print("Captured menu scan feedback probe at \(url.path)")
                Darwin.exit(0)
            } catch {
                fputs("menu scan feedback capture failed: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
    }
#endif
}

#if DEBUG
enum MenuBarClickRoutingProbe {
    static func runAndExit() -> Never {
        var scans = 0
        var menus = 0
        MenuBarClickRouter.route(.left(controlKey: false), scanOnce: { scans += 1 }, openMenu: { menus += 1 })
        guard scans == 1, menus == 0 else { Darwin.exit(1) }
        MenuBarClickRouter.route(.right, scanOnce: { scans += 1 }, openMenu: { menus += 1 })
        guard scans == 1, menus == 1 else { Darwin.exit(1) }
        print("menu click routing probe passed: left=1 scan, right=0 scans")
        Darwin.exit(0)
    }
}
#endif
