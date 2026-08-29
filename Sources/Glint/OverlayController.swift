import AppKit
import SwiftUI

enum OverlayMetrics {
    static let pinnedReservedChromeHeight: CGFloat = 76
    static let outerPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 8

    static func pinnedBodyHeight(totalHeight: CGFloat) -> CGFloat {
        max(0, totalHeight - pinnedReservedChromeHeight)
    }

    static func preferredHeight(
        lines: [GlintLine],
        sticky: Bool,
        preferences: PresentationPreferences,
        selectedIndex: Int = 0,
        width: CGFloat? = nil
    ) -> CGFloat {
        let resolvedWidth = max(360, width ?? preferences.width.points)
        guard !lines.isEmpty else { return sticky ? 236 : 180 }
        let normalizedIndex = ((selectedIndex % lines.count) + lines.count) % lines.count
        let primary = primaryHeight(line: lines[normalizedIndex], preferences: preferences, width: resolvedWidth)
        let alternatives = min(preferences.alternativePreviews, max(0, lines.count - 1))
        let rail = alternativeBlockHeight(count: alternatives, sticky: sticky, preferences: preferences)
        let body = primary + (rail > 0 ? sectionSpacing + rail : 0)
        return ceil(body + (sticky ? pinnedReservedChromeHeight : outerPadding * 2))
    }

    static func size(lines: [GlintLine], sticky: Bool, preferences: PresentationPreferences, selectedIndex: Int = 0, visibleFrame: CGRect) -> CGSize {
        let width = min(preferences.width.points, max(360, visibleFrame.width - 24))
        let preferred = preferredHeight(lines: lines, sticky: sticky, preferences: preferences, selectedIndex: selectedIndex, width: width)
        return CGSize(width: width, height: min(preferred, max(190, visibleFrame.height - 24)))
    }

    static func primaryHeight(line: GlintLine, preferences: PresentationPreferences, width: CGFloat) -> CGFloat {
        let cardPadding = preferences.density.verticalPadding
        let textWidth = max(160, width - outerPadding * 2 - cardPadding * 2)
        let scale = preferences.textSize.scale
        let keyFont = NSFont.monospacedSystemFont(ofSize: 15 * scale, weight: .bold)
        let titleFont = NSFont.systemFont(ofSize: 17 * scale, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 13 * scale)
        let metadataFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let header = max(22, lineHeight(for: keyFont))
        let titleLines = preferences.density == .detailed ? 3 : 2
        let title = boundedTextHeight(line.title, font: titleFont, width: textWidth, lineLimit: titleLines)

        var childHeights = [header, title]
        if preferences.density.showsDetail, !line.detail.isEmpty {
            childHeights.append(boundedTextHeight(line.detail, font: detailFont, width: textWidth, lineLimit: preferences.density.detailLines))
        }
        if preferences.density.showsMetadata, !line.metadata.isEmpty {
            childHeights.append(boundedTextHeight(line.metadata, font: metadataFont, width: textWidth, lineLimit: 1))
        }
        let spacing = preferences.density == .compact ? CGFloat(6) : CGFloat(10)
        return ceil(childHeights.reduce(0, +) + CGFloat(max(0, childHeights.count - 1)) * spacing + cardPadding * 2)
    }

    static func alternativeBlockHeight(count: Int, sticky: Bool, preferences: PresentationPreferences) -> CGFloat {
        guard count > 0 else { return 0 }
        let header = lineHeight(for: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold))
        let rows = CGFloat(count) * (43 * preferences.textSize.scale) + CGFloat(max(0, count - 1))
        let hint = sticky ? 0 : 4 + lineHeight(for: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize))
        return ceil(header + 4 + rows + hint)
    }

    static func boundedTextHeight(_ text: String, font: NSFont, width: CGFloat, lineLimit: Int) -> CGFloat {
        guard !text.isEmpty, width > 0, lineLimit > 0 else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(ceil(bounds.height), lineHeight(for: font) * CGFloat(lineLimit))
    }

    static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func previewScale(
        contentWidth: CGFloat,
        availableWidth: CGFloat,
        contentHeight: CGFloat,
        maximumHeight: CGFloat = 300
    ) -> CGFloat {
        guard contentWidth > 0, contentHeight > 0, availableWidth > 0, maximumHeight > 0 else { return 0 }
        return min(1, availableWidth / contentWidth, maximumHeight / contentHeight)
    }
}

private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct StatusPill: View {
    let state: String
    private var color: Color {
        switch state.lowercased() {
        case "done", "accepted", "merged", "closed": return .green
        case "in-progress", "in_progress", "open": return .blue
        case "blocked", "cancelled": return .red
        default: return .secondary
        }
    }
    var body: some View {
        Text((state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : state).replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
}

struct PrimaryResultCard: View {
    let line: GlintLine
    let preferences: PresentationPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: preferences.density == .compact ? 6 : 10) {
            HStack(spacing: 8) {
                Text(line.key).font(.system(size: 15 * preferences.textSize.scale, weight: .bold, design: .monospaced)).foregroundStyle(.tint)
                StatusPill(state: line.state)
                Spacer(minLength: 8)
                Text(line.source.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(line.title).font(.system(size: 17 * preferences.textSize.scale, weight: .semibold)).lineLimit(preferences.density == .detailed ? 3 : 2).fixedSize(horizontal: false, vertical: true)
            if preferences.density.showsDetail, !line.detail.isEmpty {
                Text(line.detail).font(.system(size: 13 * preferences.textSize.scale)).foregroundStyle(.secondary).lineLimit(preferences.density.detailLines).fixedSize(horizontal: false, vertical: true)
            }
            if preferences.density.showsMetadata, !line.metadata.isEmpty { Text(line.metadata).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .padding(preferences.density.verticalPadding).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.82)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.accentColor).frame(width: 4).padding(.vertical, 10)
        }
    }
}

struct AlternativeResultRow: View {
    let position: Int
    let line: GlintLine
    let preferences: PresentationPreferences
    var body: some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.caption2.monospacedDigit().weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).background(Color.primary.opacity(0.07), in: Circle())
            Text(line.key).font(.system(size: 12.5 * preferences.textSize.scale, weight: .semibold, design: .monospaced)).foregroundStyle(.tint).frame(minWidth: 78, alignment: .leading)
            Text(line.title).font(.system(size: 12.5 * preferences.textSize.scale, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Text(line.source.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            StatusPill(state: line.state)
        }.padding(.horizontal, 8).frame(height: 43 * preferences.textSize.scale)
    }
}

struct OverlayContent: View {
    let lines: [GlintLine]
    let selectedIndex: Int
    let sticky: Bool
    let shortcutLabel: String
    let statusText: String?
    let inputText: String?
    let projectPreview: String?
    let preferences: PresentationPreferences
    let constrainedSize: CGSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sticky {
                pinnedHeader
                ScrollView(.vertical, showsIndicators: false) {
                    resultBody
                }
                .frame(height: OverlayMetrics.pinnedBodyHeight(totalHeight: constrainedSize.height))
                pinnedFooter.fixedSize(horizontal: false, vertical: true)
            } else {
                resultBody
            }
        }
        .padding(10)
        .frame(width: constrainedSize.width, height: constrainedSize.height, alignment: .top)
        .background { surface }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }

    private var selectedLine: GlintLine? { lines.indices.contains(selectedIndex) ? lines[selectedIndex] : lines.first }
    private var alternativeIndices: [Int] { preferences.circularAlternativeIndices(count: lines.count, selectedIndex: selectedIndex) }

    @ViewBuilder private var resultBody: some View {
        VStack(alignment: .leading, spacing: OverlayMetrics.sectionSpacing) {
            if let line = selectedLine {
                PrimaryResultCard(line: line, preferences: preferences)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(statusText ?? "Ready for a ticket number").font(.headline)
                    Text("Type a number, paste a ticket key, or point at one and use Inspect.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160)
            }
            alternativeResults
        }
    }

    private var pinnedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Text("PINNED").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            if !lines.isEmpty { Text("\(min(selectedIndex + 1, lines.count)) of \(lines.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if let inputText, !inputText.isEmpty {
                Text(inputText).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.tint)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if let projectPreview { Text("→ \(projectPreview)").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
            Spacer()
            Image(systemName: "pin.fill").foregroundStyle(.tint)
        }.contentShape(Rectangle()).padding(.horizontal, 8).frame(height: 24)
    }

    @ViewBuilder private var alternativeResults: some View {
        if !alternativeIndices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("NEXT WITH SCROLL").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    let remaining = max(0, lines.count - 1 - alternativeIndices.count)
                    if remaining > 0 { Text("+\(remaining) more").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                }.padding(.horizontal, 8)
                VStack(spacing: 0) {
                    ForEach(Array(alternativeIndices.enumerated()), id: \.element) { offset, index in
                        AlternativeResultRow(position: offset + 1, line: lines[index], preferences: preferences)
                        if offset < alternativeIndices.count - 1 { Divider().padding(.leading, 38) }
                    }
                }
                if !sticky {
                    HStack(spacing: 6) { Image(systemName: "pin"); Text("\(shortcutLabel) opens the navigator") }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                }
            }
        }
    }

    @ViewBuilder private var surface: some View {
        if preferences.surface == .system && !reduceTransparency {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var pinnedFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "computermouse")
            Text("scroll: result")
            Text("·")
            Text("⇧ scroll: project")
            Text("·")
            Text("type: ticket/project")
            Spacer()
            Text("\(shortcutLabel) closes").lineLimit(1)
        }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8)
    }
}

struct AppearanceCardPreview: View {
    let preferences: PresentationPreferences
    private let sampleLines = [
        GlintLine(key: "GLINT-22", state: "in-progress", title: "A card that feels unmistakably yours", source: "ppm", metadata: "ticket · high priority", detail: "See the right amount of context, then scroll through alternatives with confidence."),
        GlintLine(key: "GLINT-21", state: "open", title: "Make activation effortless", source: "ppm"),
        GlintLine(key: "#184", state: "review", title: "Refine source-aware matching", source: "gh"),
        GlintLine(key: "PAI-608", state: "done", title: "Launch the ticket navigator", source: "ppm"),
        GlintLine(key: "GLINT-19", state: "open", title: "Add scan feedback", source: "ppm")
    ]

    var body: some View {
        GeometryReader { proxy in
            let actualWidth = preferences.width.points
            let height = OverlayMetrics.preferredHeight(lines: sampleLines, sticky: true, preferences: preferences)
            let scale = OverlayMetrics.previewScale(
                contentWidth: actualWidth,
                availableWidth: max(1, proxy.size.width - 4),
                contentHeight: height
            )
            OverlayContent(lines: sampleLines, selectedIndex: 0, sticky: true, shortcutLabel: "⌥⇧Space", statusText: nil, inputText: nil, projectPreview: nil, preferences: preferences, constrainedSize: CGSize(width: actualWidth, height: height))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: actualWidth * scale, height: height * scale, alignment: .topLeading)
                .accessibilityLabel("Live ticket card preview")
        }
        .frame(height: min(300, OverlayMetrics.preferredHeight(lines: sampleLines, sticky: true, preferences: preferences)))
        .clipped()
    }
}

@MainActor final class OverlayController: NSObject, NSWindowDelegate {
    var onCycleProject: ((Int) -> Void)?
    var onInput: ((PinnedInputEvent) -> Void)?
    var onSelectionChange: ((GlintLine) -> Void)?

    private let panel: FocusablePanel
    private var displayedLines: [GlintLine] = []
    private var selectedIndex = 0
    private var anchorMouse = CGPoint.zero
    private var shortcutLabel = "⌥⇧Space"
    private var statusText: String?
    private var inputText: String?
    private var projectPreview: String?
    private var eventMonitor: Any?
    private var preferenceObserver: NSObjectProtocol?
    private var lastScrollAt = Date.distantPast
    private var isPositioningProgrammatically = false
    private var presentationPreferences = PresentationPreferences.load()
    private(set) var isSticky = false

    var isVisible: Bool { panel.isVisible }
    var isActive: Bool { panel.isKeyWindow }
    var selectedLine: GlintLine? { displayedLines.indices.contains(selectedIndex) ? displayedLines[selectedIndex] : displayedLines.first }

#if DEBUG
    func captureProbe(to url: URL) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }
#endif

    init(allowsCapture: Bool = false) {
        panel = FocusablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.sharingType = allowsCapture ? .readOnly : .none
        panel.isMovableByWindowBackground = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
        preferenceObserver = NotificationCenter.default.addObserver(forName: .glintPresentationPreferencesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.presentationPreferences = PresentationPreferences.load()
                guard self.panel.isVisible else { return }
                if self.isSticky { self.renderPinned(useSavedPosition: false) } else { self.renderTemporary() }
            }
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }

    func show(_ lines: [GlintLine], near mouse: CGPoint, shortcutLabel: String = "⌥⇧Space") {
        guard !lines.isEmpty else { hide(); return }
        if isSticky { replacePinnedResults(lines); return }
        displayedLines = Array(lines.prefix(HoverResultPolicy.maximumResults)); selectedIndex = 0
        anchorMouse = mouse; self.shortcutLabel = shortcutLabel; statusText = nil
        renderTemporary(); panel.orderFrontRegardless()
    }

    func openPinned(shortcutLabel: String, status: String = "Reading near pointer…") {
        isSticky = true; displayedLines = []; selectedIndex = 0; statusText = status
        anchorMouse = NSEvent.mouseLocation
        inputText = nil; projectPreview = nil; self.shortcutLabel = shortcutLabel
        panel.ignoresMouseEvents = false; renderPinned(useSavedPosition: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSticky else { return }
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    func pin(shortcutLabel: String) {
        guard panel.isVisible else { openPinned(shortcutLabel: shortcutLabel); return }
        isSticky = true; selectedIndex = 0; self.shortcutLabel = shortcutLabel
        panel.ignoresMouseEvents = false; renderPinned(useSavedPosition: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func focusPinned() { guard isSticky else { return }; panel.makeKeyAndOrderFront(nil) }

    func replacePinnedResults(_ lines: [GlintLine], selecting key: String? = nil, status: String? = nil) {
        guard isSticky else { return }
        displayedLines = Array(lines.prefix(HoverResultPolicy.maximumResults))
        if let key, let index = displayedLines.firstIndex(where: { $0.key == key }) { selectedIndex = index }
        else { selectedIndex = min(selectedIndex, max(0, displayedLines.count - 1)) }
        statusText = status; renderPinned(useSavedPosition: false)
    }

    func setInput(_ value: String?, projectPreview: String? = nil) {
        inputText = value; self.projectPreview = projectPreview
        if isSticky {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isSticky else { return }
                self.renderPinned(useSavedPosition: false)
            }
        }
    }

    func showPinnedStatus(_ status: String) {
        guard isSticky else { return }
        displayedLines = []; selectedIndex = 0; statusText = status; renderPinned(useSavedPosition: false)
    }

    func closePinned() { guard isSticky else { return }; hide() }
    func hide() { panel.orderOut(nil); isSticky = false; panel.ignoresMouseEvents = true; inputText = nil; projectPreview = nil }

    func windowDidMove(_ notification: Notification) {
        guard isSticky, !isPositioningProgrammatically else { return }
        savePinnedOrigin()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isSticky, event.window === panel else { return event }
        if event.type == .scrollWheel {
            let shiftingProject = event.modifierFlags.contains(.shift)
            let delta = shiftingProject && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1, Date().timeIntervalSince(lastScrollAt) > 0.10 else { return nil }
            lastScrollAt = Date(); let direction = delta > 0 ? -1 : 1
            if shiftingProject { onCycleProject?(direction) }
            else { cycleResult(direction) }
            return nil
        }
        guard panel.isKeyWindow else { return event }
        guard event.type == .keyDown else { return event }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            onInput?(.paste(NSPasteboard.general.string(forType: .string) ?? "")); return nil
        }
        switch event.keyCode {
        case 36, 76: onInput?(.submit); return nil
        case 51, 117: onInput?(.backspace); return nil
        case 53: onInput?(.escape); return nil
        default: break
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers else { return event }
        let digits = characters.filter(\.isNumber)
        if !digits.isEmpty { onInput?(.digits(digits)); return nil }
        let letters = characters.filter(\.isLetter)
        if !letters.isEmpty { onInput?(.letters(letters)); return nil }
        return event
    }

    private func cycleResult(_ direction: Int) {
        guard displayedLines.count > 1 else { return }
        selectedIndex = CircularNavigation.advancedIndex(current: selectedIndex, direction: direction, count: displayedLines.count)
        inputText = nil; projectPreview = nil; renderPinned(useSavedPosition: false)
        if let selectedLine { onSelectionChange?(selectedLine) }
    }

    private func renderTemporary() {
        guard let targetScreen = screen(containing: anchorMouse) else { hide(); return }
        let visible = targetScreen.visibleFrame
        let size = OverlayMetrics.size(lines: displayedLines, sticky: false, preferences: presentationPreferences, selectedIndex: selectedIndex, visibleFrame: visible)
        var origin = CGPoint(x: anchorMouse.x + 18, y: anchorMouse.y - size.height - 18)
        if origin.x + size.width > visible.maxX { origin.x = anchorMouse.x - size.width - 18 }
        if origin.y < visible.minY { origin.y = anchorMouse.y + 18 }
        origin = PanelPlacement.clamped(origin: origin, size: size, visibleFrame: visible)
        panel.contentView = hostingView(size: size)
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
    }

    private func renderPinned(useSavedPosition: Bool) {
        let shouldRemainFocused = panel.isKeyWindow
        guard let targetScreen = useSavedPosition ? screen(containing: anchorMouse) : (panel.screen ?? screen(containing: NSEvent.mouseLocation)) else {
            hide(); return
        }
        let visible = targetScreen.visibleFrame
        let size = OverlayMetrics.size(lines: displayedLines, sticky: true, preferences: presentationPreferences, selectedIndex: selectedIndex, visibleFrame: visible)
        let origin = useSavedPosition ? savedOrigin(for: targetScreen, size: size) : PanelPlacement.clamped(origin: panel.frame.origin, size: size, visibleFrame: visible)
        panel.contentView = hostingView(size: size)
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
        if shouldRemainFocused { panel.makeKey() }
    }

    private func hostingView(size: CGSize) -> NSView {
        NSHostingView(rootView: OverlayContent(lines: displayedLines, selectedIndex: selectedIndex, sticky: isSticky, shortcutLabel: shortcutLabel, statusText: statusText, inputText: inputText, projectPreview: projectPreview, preferences: presentationPreferences, constrainedSize: size))
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func screenID(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
    private func savedOrigin(for screen: NSScreen, size: CGSize) -> CGPoint {
        let key = "pinnedOrigin.\(screenID(screen))"
        if let value = UserDefaults.standard.string(forKey: key) {
            let parts = value.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { return PanelPlacement.clamped(origin: CGPoint(x: parts[0], y: parts[1]), size: size, visibleFrame: screen.visibleFrame) }
        }
        return PanelPlacement.clamped(origin: CGPoint(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.maxY - size.height - 20), size: size, visibleFrame: screen.visibleFrame)
    }
    private func savePinnedOrigin() {
        guard let screen = panel.screen else { return }
        UserDefaults.standard.set("\(panel.frame.origin.x),\(panel.frame.origin.y)", forKey: "pinnedOrigin.\(screenID(screen))")
    }
}
