import AppKit
import SwiftUI

private enum OverlayMetrics {
    static let width: CGFloat = 590
    static let pinnedHeight: CGFloat = 250
    static func temporaryHeight(for lines: [GlintLine]) -> CGFloat {
        guard let first = lines.first else { return 0 }
        let primary: CGFloat = first.detail.isEmpty ? 138 : 198
        let secondaryCount = min(max(0, lines.count - 1), 2)
        let secondary = secondaryCount == 0 ? 0 : 34 + CGFloat(secondaryCount * 48)
        return primary + secondary + (lines.count > 1 ? 32 : 0) + 20
    }
}

private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct StatusPill: View {
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
        Text(state.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
}

private struct PrimaryResultCard: View {
    let line: GlintLine
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(line.key).font(.system(.headline, design: .monospaced).weight(.bold)).foregroundStyle(.tint)
                StatusPill(state: line.state)
                Spacer(minLength: 8)
                Text(line.source.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(line.title).font(.title3.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !line.detail.isEmpty {
                Text(line.detail).font(.callout).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if !line.metadata.isEmpty { Text(line.metadata).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.82)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.accentColor).frame(width: 4).padding(.vertical, 10)
        }
    }
}

private struct SecondaryResultRow: View {
    let line: GlintLine
    var body: some View {
        HStack(spacing: 9) {
            Text(line.key).font(.system(.callout, design: .monospaced).weight(.semibold)).foregroundStyle(.tint).frame(minWidth: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).font(.callout.weight(.medium)).lineLimit(1)
                if !line.metadata.isEmpty { Text(line.metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4); StatusPill(state: line.state)
        }.padding(.horizontal, 8).frame(height: 47)
    }
}

private struct OverlayContent: View {
    let lines: [GlintLine]
    let selectedIndex: Int
    let sticky: Bool
    let shortcutLabel: String
    let statusText: String?
    let inputText: String?
    let projectPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sticky { pinnedHeader }
            if let line = selectedLine {
                PrimaryResultCard(line: line)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(statusText ?? "Ready for a ticket number").font(.headline)
                    Text("Type a number, paste a ticket key, or point at one and use Inspect.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160)
            }
            if sticky {
                pinnedFooter
            } else {
                temporaryResults
            }
        }
        .padding(10)
        .frame(width: OverlayMetrics.width, height: sticky ? OverlayMetrics.pinnedHeight : OverlayMetrics.temporaryHeight(for: lines), alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }

    private var selectedLine: GlintLine? { lines.indices.contains(selectedIndex) ? lines[selectedIndex] : lines.first }
    private var secondary: [GlintLine] { Array(lines.dropFirst()) }

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

    @ViewBuilder private var temporaryResults: some View {
        if !secondary.isEmpty {
            HStack { Text("MORE MATCHES").font(.caption2.weight(.bold)).foregroundStyle(.secondary); Text("\(secondary.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary); Spacer(); if secondary.count > 2 { Text("Pin to browse").font(.caption2).foregroundStyle(.secondary) } }.padding(.horizontal, 8)
            VStack(spacing: 0) {
                ForEach(secondary.prefix(2)) { line in SecondaryResultRow(line: line); if line.id != secondary.prefix(2).last?.id { Divider().padding(.leading, 8) } }
            }.frame(maxHeight: 96)
            HStack(spacing: 6) { Image(systemName: "pin"); Text("\(shortcutLabel) opens the navigator") }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
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

@MainActor final class OverlayController: NSObject, NSWindowDelegate {
    var onCycleProject: ((Int) -> Void)?
    var onInput: ((PinnedInputEvent) -> Void)?

    private let panel: FocusablePanel
    private var displayedLines: [GlintLine] = []
    private var selectedIndex = 0
    private var anchorMouse = CGPoint.zero
    private var shortcutLabel = "⌥⇧Space"
    private var statusText: String?
    private var inputText: String?
    private var projectPreview: String?
    private var eventMonitor: Any?
    private var lastScrollAt = Date.distantPast
    private var isPositioningProgrammatically = false
    private(set) var isSticky = false

    var isVisible: Bool { panel.isVisible }
    var isActive: Bool { panel.isKeyWindow }
    var selectedLine: GlintLine? { displayedLines.indices.contains(selectedIndex) ? displayedLines[selectedIndex] : displayedLines.first }

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
    }

    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }

    func show(_ lines: [GlintLine], near mouse: CGPoint, shortcutLabel: String = "⌥⇧Space") {
        guard !lines.isEmpty else { hide(); return }
        if isSticky { replacePinnedResults(lines); return }
        displayedLines = Array(lines.prefix(HoverResultPolicy.maximumResults)); selectedIndex = 0
        anchorMouse = mouse; self.shortcutLabel = shortcutLabel; statusText = nil
        renderTemporary(); panel.orderFrontRegardless()
    }

    func openPinned(shortcutLabel: String, status: String = "Reading near pointer…") {
        isSticky = true; displayedLines = []; selectedIndex = 0; statusText = status
        inputText = nil; projectPreview = nil; self.shortcutLabel = shortcutLabel
        panel.ignoresMouseEvents = false; renderPinned(useSavedPosition: true)
        panel.makeKeyAndOrderFront(nil)
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
        guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false,
              let characters = event.charactersIgnoringModifiers else { return event }
        let digits = characters.filter(\.isNumber)
        if !digits.isEmpty { onInput?(.digits(digits)); return nil }
        let letters = characters.filter(\.isLetter)
        if !letters.isEmpty { onInput?(.letters(letters)); return nil }
        return event
    }

    private func cycleResult(_ direction: Int) {
        guard displayedLines.count > 1 else { return }
        selectedIndex = (selectedIndex + direction + displayedLines.count) % displayedLines.count
        inputText = nil; projectPreview = nil; renderPinned(useSavedPosition: false)
    }

    private func renderTemporary() {
        let size = CGSize(width: OverlayMetrics.width, height: OverlayMetrics.temporaryHeight(for: displayedLines))
        let visible = screen(containing: anchorMouse).visibleFrame
        var origin = CGPoint(x: anchorMouse.x + 18, y: anchorMouse.y - size.height - 18)
        if origin.x + size.width > visible.maxX { origin.x = anchorMouse.x - size.width - 18 }
        if origin.y < visible.minY { origin.y = anchorMouse.y + 18 }
        origin = clamp(origin: origin, size: size, to: visible)
        panel.contentView = hostingView()
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
    }

    private func renderPinned(useSavedPosition: Bool) {
        let shouldRemainFocused = panel.isKeyWindow
        let size = CGSize(width: OverlayMetrics.width, height: OverlayMetrics.pinnedHeight)
        let targetScreen = panel.screen ?? screen(containing: NSEvent.mouseLocation)
        let visible = targetScreen.visibleFrame
        let origin = useSavedPosition ? savedOrigin(for: targetScreen, size: size) : clamp(origin: panel.frame.origin, size: size, to: visible)
        panel.contentView = hostingView()
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
        if shouldRemainFocused { panel.makeKey() }
    }

    private func hostingView() -> NSView {
        NSHostingView(rootView: OverlayContent(lines: displayedLines, selectedIndex: selectedIndex, sticky: isSticky, shortcutLabel: shortcutLabel, statusText: statusText, inputText: inputText, projectPreview: projectPreview))
    }

    private func screen(containing point: CGPoint) -> NSScreen { NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0] }
    private func clamp(origin: CGPoint, size: CGSize, to visible: CGRect) -> CGPoint {
        let inset: CGFloat = 8
        return CGPoint(x: min(max(origin.x, visible.minX + inset), visible.maxX - size.width - inset), y: min(max(origin.y, visible.minY + inset), visible.maxY - size.height - inset))
    }
    private func screenID(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
    private func savedOrigin(for screen: NSScreen, size: CGSize) -> CGPoint {
        let key = "pinnedOrigin.\(screenID(screen))"
        if let value = UserDefaults.standard.string(forKey: key) {
            let parts = value.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { return clamp(origin: CGPoint(x: parts[0], y: parts[1]), size: size, to: screen.visibleFrame) }
        }
        return clamp(origin: CGPoint(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.maxY - size.height - 20), size: size, to: screen.visibleFrame)
    }
    private func savePinnedOrigin() {
        guard let screen = panel.screen else { return }
        UserDefaults.standard.set("\(panel.frame.origin.x),\(panel.frame.origin.y)", forKey: "pinnedOrigin.\(screenID(screen))")
    }
}
