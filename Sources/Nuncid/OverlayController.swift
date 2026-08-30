import AppKit
import SwiftUI

enum OverlayMetrics {
    static let pinnedReservedChromeHeight: CGFloat = 76
    static let outerPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 8

    static func pinnedBodyHeight(totalHeight: CGFloat) -> CGFloat {
        max(0, totalHeight - pinnedReservedChromeHeight)
    }

    static func temporaryBodyHeight(totalHeight: CGFloat) -> CGFloat {
        max(0, totalHeight - outerPadding * 2)
    }

    static func preferredHeight(
        lines: [TicketLine],
        sticky: Bool,
        preferences: PresentationPreferences,
        width: CGFloat? = nil
    ) -> CGFloat {
        let resolvedWidth = max(360, width ?? (preferences.width == .custom ? preferences.customWidth : preferences.width.points))
        guard !lines.isEmpty else { return sticky ? 236 : 180 }
        let primary = stablePrimaryHeight(lines: lines, preferences: preferences, width: resolvedWidth)
        let alternatives = min(preferences.alternativePreviews, max(0, lines.count - 1))
        let rail = alternativeBlockHeight(count: alternatives, sticky: sticky, preferences: preferences)
        let body = primary + (rail > 0 ? sectionSpacing + rail : 0)
        return ceil(body + (sticky ? pinnedReservedChromeHeight : outerPadding * 2))
    }

    static func size(lines: [TicketLine], sticky: Bool, preferences: PresentationPreferences, visibleFrame: CGRect) -> CGSize {
        if preferences.width == .custom {
            return OverlaySizePolicy.clamped(
                CGSize(width: preferences.customWidth, height: preferences.customHeight),
                visibleFrame: visibleFrame
            )
        }
        let width = min(preferences.width.points, max(OverlaySizePolicy.minimum.width, visibleFrame.width - 24))
        let preferred = preferredHeight(lines: lines, sticky: sticky, preferences: preferences, width: width)
        return OverlaySizePolicy.clampedToVisibleMaximum(
            CGSize(width: width, height: preferred),
            visibleFrame: visibleFrame
        )
    }

    static func visibleAlternativeCount(
        lines: [TicketLine],
        preferences: PresentationPreferences,
        width: CGFloat,
        totalHeight: CGFloat,
        sticky: Bool
    ) -> Int {
        guard !lines.isEmpty else { return 0 }
        let requested = min(preferences.alternativePreviews, max(0, lines.count - 1))
        guard requested > 0 else { return 0 }
        let primary = stablePrimaryHeight(lines: lines, preferences: preferences, width: width)
        let available = sticky
            ? pinnedBodyHeight(totalHeight: totalHeight)
            : temporaryBodyHeight(totalHeight: totalHeight)
        return stride(from: requested, through: 1, by: -1).first { count in
            primary + sectionSpacing + alternativeBlockHeight(
                count: count,
                sticky: sticky,
                preferences: preferences
            ) <= available
        } ?? 0
    }

    static func primaryHeight(line: TicketLine, preferences: PresentationPreferences, width: CGFloat) -> CGFloat {
        let cardPadding = preferences.density.verticalPadding
        let textWidth = max(160, width - outerPadding * 2 - cardPadding * 2)
        let scale = preferences.textSize.scale
        let keyFont = NSFont.monospacedSystemFont(ofSize: 15 * scale, weight: .bold)
        let detailFont = NSFont.systemFont(ofSize: 13 * scale)
        let metadataFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let header = max(22, lineHeight(for: keyFont))
        let title = primaryTitleHeight(line: line, preferences: preferences, width: width)

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

    static func stablePrimaryHeight(lines: [TicketLine], preferences: PresentationPreferences, width: CGFloat) -> CGFloat {
        let stableTitle = stablePrimaryTitleHeight(lines: lines, preferences: preferences, width: width)
        return lines.map {
            primaryHeight(line: $0, preferences: preferences, width: width)
                - primaryTitleHeight(line: $0, preferences: preferences, width: width)
                + stableTitle
        }.max() ?? 0
    }

    static func primaryTitleHeight(line: TicketLine, preferences: PresentationPreferences, width: CGFloat) -> CGFloat {
        let textWidth = max(160, width - outerPadding * 2 - preferences.density.verticalPadding * 2)
        let titleFont = NSFont.systemFont(ofSize: 17 * preferences.textSize.scale, weight: .semibold)
        let titleLines = preferences.density == .detailed ? 3 : 2
        return boundedTextHeight(line.title, font: titleFont, width: textWidth, lineLimit: titleLines)
    }

    static func stablePrimaryTitleHeight(lines: [TicketLine], preferences: PresentationPreferences, width: CGFloat) -> CGFloat {
        lines.map { primaryTitleHeight(line: $0, preferences: preferences, width: width) }.max() ?? 0
    }

    static func alternativeBlockHeight(count: Int, sticky: Bool, preferences: PresentationPreferences) -> CGFloat {
        guard count > 0 else { return 0 }
        let headerCount = min(2, count)
        let header = lineHeight(for: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)) * CGFloat(headerCount)
        let headerSpacing = CGFloat(headerCount) * 4
        let rows = CGFloat(count) * (43 * preferences.textSize.scale) + CGFloat(max(0, count - 1))
        let secondRailSpacing = CGFloat(max(0, headerCount - 1)) * sectionSpacing
        let hint = sticky ? 0 : sectionSpacing + lineHeight(for: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize))
        return ceil(header + headerSpacing + rows + secondRailSpacing + hint)
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

enum OverlaySizePolicy {
    static let minimum = CGSize(width: 420, height: 260)
    static let fallbackMaximum = CGSize(width: 1_100, height: 900)

    static func clamped(_ size: CGSize, visibleFrame: CGRect?) -> CGSize {
        let maximum = visibleFrame.map {
            CGSize(width: max(minimum.width, $0.width - 16), height: max(minimum.height, $0.height - 16))
        } ?? fallbackMaximum
        return CGSize(
            width: min(max(size.width, minimum.width), maximum.width),
            height: min(max(size.height, minimum.height), maximum.height)
        )
    }

    static func clampedToVisibleMaximum(_ size: CGSize, visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(size.width, max(1, visibleFrame.width - 16)),
            height: min(size.height, max(1, visibleFrame.height - 16))
        )
    }
}

enum NeighborRailPolicy {
    static func indices(count: Int, selectedIndex: Int, visibleCount: Int) -> (previous: [Int], next: [Int]) {
        guard count > 1, visibleCount > 0 else { return ([], []) }
        let selected = ((selectedIndex % count) + count) % count
        let limit = min(visibleCount, count - 1)
        var previous: [Int] = []
        var next: [Int] = []
        var used = Set([selected])
        for distance in 1..<count where previous.count + next.count < limit {
            let nextIndex = (selected + distance) % count
            if used.insert(nextIndex).inserted, previous.count + next.count < limit {
                next.append(nextIndex)
            }
            let previousIndex = (selected - distance + count) % count
            if used.insert(previousIndex).inserted, previous.count + next.count < limit {
                previous.insert(previousIndex, at: 0)
            }
        }
        return (previous, next)
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

enum TicketKeyMotionStyle: Equatable {
    case matchedFlight
    case opacityOnly
}

enum TicketKeyMotionPolicy {
    static let titleSettleDelay: TimeInterval = 0.38

    static func style(reduceMotion: Bool) -> TicketKeyMotionStyle {
        reduceMotion ? .opacityOnly : .matchedFlight
    }
}

enum TicketTitleSettlePolicy {
    static func nextGeneration(after current: Int) -> Int {
        current + 1
    }

    static func isSettled(
        navigationGeneration: Int,
        settledGeneration: Int,
        reduceMotion: Bool
    ) -> Bool {
        reduceMotion || settledGeneration >= navigationGeneration
    }

    static func completedGeneration(current: Int, callbackGeneration: Int) -> Int {
        max(current, callbackGeneration)
    }
}

private enum TicketKeyRole: Equatable {
    case primary
    case neighbor
}

private struct TicketKeyLabel: View {
    let line: TicketLine
    let role: TicketKeyRole
    let preferences: PresentationPreferences
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        if TicketKeyMotionPolicy.style(reduceMotion: reduceMotion) == .matchedFlight {
            styledLabel
                .matchedGeometryEffect(
                    id: "ticket-key-\(line.id)",
                    in: namespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: role == .primary
                )
                .zIndex(20)
        } else {
            styledLabel
                .contentTransition(.opacity)
        }
    }

    @ViewBuilder private var styledLabel: some View {
        switch role {
        case .primary:
            Text(line.key)
                .font(.system(size: 15 * preferences.textSize.scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.tint)
                .lineLimit(1)
                .fixedSize()
        case .neighbor:
            Text(line.key)
                .font(.system(size: 12.5 * preferences.textSize.scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(minWidth: 88, alignment: .leading)
        }
    }
}

private struct TicketTitleLabel: View {
    let line: TicketLine
    let role: TicketKeyRole
    let preferences: PresentationPreferences
    let namespace: Namespace.ID
    let primaryTitleSettled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        if TicketKeyMotionPolicy.style(reduceMotion: reduceMotion) == .matchedFlight {
            styledLabel
                .matchedGeometryEffect(
                    id: "ticket-title-\(line.id)",
                    in: namespace,
                    properties: .frame,
                    anchor: .leading,
                    isSource: role == .primary
                )
                .zIndex(19)
        } else {
            styledLabel
                .contentTransition(.opacity)
        }
    }

    @ViewBuilder private var styledLabel: some View {
        switch role {
        case .primary:
            Text(line.title)
                .font(.system(size: 17 * preferences.textSize.scale, weight: .semibold))
                .lineLimit(primaryTitleSettled ? (preferences.density == .detailed ? 3 : 2) : 1)
                .fixedSize(horizontal: false, vertical: true)
        case .neighbor:
            Text(line.title)
                .font(.system(size: 12.5 * preferences.textSize.scale, weight: .medium))
                .lineLimit(1)
        }
    }
}

struct PrimaryResultCard: View {
    let line: TicketLine
    let preferences: PresentationPreferences
    let keyNamespace: Namespace.ID
    let fixedHeight: CGFloat
    let titleSlotHeight: CGFloat
    let primaryTitleSettled: Bool
    let showsPin: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: preferences.density == .compact ? 6 : 10) {
            HStack(spacing: 8) {
                TicketKeyLabel(line: line, role: .primary, preferences: preferences, namespace: keyNamespace)
                StatusPill(state: line.state)
                Spacer(minLength: 8)
                SourceDestinationLink(line: line)
                if showsPin { PinToggleButton(isPinned: isPinned, action: onTogglePin) }
            }
            TicketTitleLabel(
                line: line,
                role: .primary,
                preferences: preferences,
                namespace: keyNamespace,
                primaryTitleSettled: primaryTitleSettled
            )
            .frame(height: titleSlotHeight, alignment: .topLeading)
            .clipped()
            if preferences.density.showsDetail, !line.detail.isEmpty {
                Text(line.detail).font(.system(size: 13 * preferences.textSize.scale)).foregroundStyle(.secondary).lineLimit(preferences.density.detailLines).fixedSize(horizontal: false, vertical: true)
            }
            if preferences.density.showsMetadata, !line.metadata.isEmpty { Text(line.metadata).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
        .padding(preferences.density.verticalPadding).frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: fixedHeight, alignment: .top)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.82)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.accentColor).frame(width: 4).padding(.vertical, 10)
        }
    }
}

private struct SourceDestinationLink: View {
    let line: TicketLine
    @State private var hovering = false

    var body: some View {
        if let destination = line.destinationURL {
            Link(destination: destination) { linkedLabel }
                .buttonStyle(.plain)
                .help("Open \(line.source.uppercased()) record")
                .accessibilityLabel("Open \(line.key) in \(line.source.uppercased())")
                .onHover { hovering = $0 }
        } else {
            Text(line.source.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
        }
    }

    private var linkedLabel: some View {
        HStack(spacing: 3) {
            Text(line.source.uppercased())
            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(hovering ? 0.12 : 0.001), in: Capsule())
        .contentShape(Capsule())
    }
}

private struct PinToggleButton: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin card" : "Pin card")
        .accessibilityLabel(isPinned ? "Unpin card" : "Pin card")
    }
}

struct AlternativeResultRow: View {
    let position: Int
    let line: TicketLine
    let preferences: PresentationPreferences
    let keyNamespace: Namespace.ID
    var body: some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.caption2.monospacedDigit().weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).background(Color.primary.opacity(0.07), in: Circle())
            TicketKeyLabel(line: line, role: .neighbor, preferences: preferences, namespace: keyNamespace)
            TicketTitleLabel(
                line: line,
                role: .neighbor,
                preferences: preferences,
                namespace: keyNamespace,
                primaryTitleSettled: true
            )
            Spacer(minLength: 4)
            Text(line.source.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            StatusPill(state: line.state)
        }.padding(.horizontal, 8).frame(height: 43 * preferences.textSize.scale)
    }
}

struct OverlayContent: View {
    let lines: [TicketLine]
    let selectedIndex: Int
    let navigationGeneration: Int
    let sticky: Bool
    let shortcutLabel: String
    let statusText: String?
    let inputText: String?
    let projectPreview: String?
    let preferences: PresentationPreferences
    let constrainedSize: CGSize
    let scrollModifier: PopupScrollModifier
    let onTogglePin: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ticketKeyNamespace
    @State private var settledTitleGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sticky {
                pinnedHeader
                resultBody
                .frame(
                    height: OverlayMetrics.pinnedBodyHeight(totalHeight: constrainedSize.height),
                    alignment: .top
                )
                .clipped()
                pinnedFooter.fixedSize(horizontal: false, vertical: true)
            } else {
                resultBody
                    .frame(
                        height: OverlayMetrics.temporaryBodyHeight(totalHeight: constrainedSize.height),
                        alignment: .top
                    )
                    .clipped()
            }
        }
        .padding(10)
        .frame(width: constrainedSize.width, height: constrainedSize.height, alignment: .top)
        .background { surface }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
        .onChange(of: navigationGeneration) { generation in
            if reduceMotion {
                settledTitleGeneration = TicketTitleSettlePolicy.completedGeneration(
                    current: settledTitleGeneration,
                    callbackGeneration: generation
                )
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + TicketKeyMotionPolicy.titleSettleDelay) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        settledTitleGeneration = TicketTitleSettlePolicy.completedGeneration(
                            current: settledTitleGeneration,
                            callbackGeneration: generation
                        )
                    }
                }
            }
        }
        .onChange(of: reduceMotion) { enabled in
            if enabled {
                settledTitleGeneration = TicketTitleSettlePolicy.completedGeneration(
                    current: settledTitleGeneration,
                    callbackGeneration: navigationGeneration
                )
            }
        }
    }

    private var selectedLine: TicketLine? { lines.indices.contains(selectedIndex) ? lines[selectedIndex] : lines.first }
    private var primarySlotHeight: CGFloat {
        OverlayMetrics.stablePrimaryHeight(
            lines: lines,
            preferences: preferences,
            width: constrainedSize.width
        )
    }
    private var primaryTitleSlotHeight: CGFloat {
        OverlayMetrics.stablePrimaryTitleHeight(
            lines: lines,
            preferences: preferences,
            width: constrainedSize.width
        )
    }
    private var neighborIndices: (previous: [Int], next: [Int]) {
        let visibleCount = OverlayMetrics.visibleAlternativeCount(
            lines: lines,
            preferences: preferences,
            width: constrainedSize.width,
            totalHeight: constrainedSize.height,
            sticky: sticky
        )
        return NeighborRailPolicy.indices(
            count: lines.count,
            selectedIndex: selectedIndex,
            visibleCount: visibleCount
        )
    }

    @ViewBuilder private var resultBody: some View {
        VStack(alignment: .leading, spacing: OverlayMetrics.sectionSpacing) {
            neighborResults(indices: neighborIndices.previous, title: "PREVIOUS")
            if let line = selectedLine {
                PrimaryResultCard(
                    line: line,
                    preferences: preferences,
                    keyNamespace: ticketKeyNamespace,
                    fixedHeight: primarySlotHeight,
                    titleSlotHeight: primaryTitleSlotHeight,
                    primaryTitleSettled: TicketTitleSettlePolicy.isSettled(
                        navigationGeneration: navigationGeneration,
                        settledGeneration: settledTitleGeneration,
                        reduceMotion: reduceMotion
                    ),
                    showsPin: !sticky,
                    isPinned: sticky,
                    onTogglePin: onTogglePin
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(statusText ?? "Ready for a ticket number").font(.headline)
                    Text("Type a number, paste a ticket key, or point at one and use Inspect.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160)
            }
            neighborResults(indices: neighborIndices.next, title: "NEXT")
            if !sticky, !neighborIndices.previous.isEmpty || !neighborIndices.next.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pin")
                    Text("\(shortcutLabel) opens the navigator")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88),
            value: selectedIndex
        )
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
            PinToggleButton(isPinned: true, action: onTogglePin)
        }.contentShape(Rectangle()).padding(.horizontal, 8).frame(height: 24)
    }

    @ViewBuilder private func neighborResults(indices: [Int], title: String) -> some View {
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 8)
                VStack(spacing: 0) {
                    ForEach(Array(indices.enumerated()), id: \.element) { offset, index in
                        AlternativeResultRow(
                            position: index + 1,
                            line: lines[index],
                            preferences: preferences,
                            keyNamespace: ticketKeyNamespace
                        )
                            .transition(neighborTransition(title: title))
                        if offset < indices.count - 1 { Divider().padding(.leading, 38) }
                    }
                }
            }
        }
    }

    private func neighborTransition(title: String) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: title == "NEXT" ? .bottom : .top).combined(with: .opacity),
            removal: .move(edge: title == "NEXT" ? .top : .bottom).combined(with: .opacity)
        )
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
            Text("\(scrollModifier.symbol) scroll anywhere")
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
        TicketLine(key: "NUNCID-36", state: "in-progress", title: "Navigate results spatially from anywhere", source: "ppm", metadata: "ticket · high priority", detail: "The current ticket stays fixed while clear previous and next destinations move around it."),
        TicketLine(key: "NUNCID-35", state: "done", title: "Open the source and read every neighboring ID", source: "ppm"),
        TicketLine(key: "#184", state: "review", title: "Refine source-aware matching", source: "gh"),
        TicketLine(key: "NUNCID-34", state: "done", title: "Remember a custom card size", source: "ppm"),
        TicketLine(key: "NUNCID-33", state: "done", title: "Pin directly without racing the popup", source: "ppm"),
        TicketLine(key: "NUNCID-37", state: "done", title: "Use F19 and other function keys as shortcuts", source: "ppm")
    ]

    var body: some View {
        GeometryReader { proxy in
            let actualWidth = preferences.width == .custom ? preferences.customWidth : preferences.width.points
            let height = preferences.width == .custom ? preferences.customHeight : OverlayMetrics.preferredHeight(lines: sampleLines, sticky: true, preferences: preferences)
            let scale = OverlayMetrics.previewScale(
                contentWidth: actualWidth,
                availableWidth: max(1, proxy.size.width - 4),
                contentHeight: height
            )
            OverlayContent(lines: sampleLines, selectedIndex: 0, navigationGeneration: 0, sticky: true, shortcutLabel: "⌥⇧Space", statusText: nil, inputText: nil, projectPreview: nil, preferences: preferences, constrainedSize: CGSize(width: actualWidth, height: height), scrollModifier: .option, onTogglePin: {})
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: actualWidth * scale, height: height * scale, alignment: .topLeading)
                .accessibilityLabel("Live ticket card preview")
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: min(300, OverlayMetrics.preferredHeight(lines: sampleLines, sticky: true, preferences: preferences)))
        .clipped()
    }
}

@MainActor private final class OverlayViewState: ObservableObject {
    @Published var lines: [TicketLine] = []
    @Published var selectedIndex = 0
    @Published var navigationGeneration = 0
    @Published var sticky = false
    @Published var shortcutLabel = "⌥⇧Space"
    @Published var statusText: String?
    @Published var inputText: String?
    @Published var projectPreview: String?
    @Published var preferences = PresentationPreferences.load()
    @Published var scrollModifier = PopupInteractionPreferences.load().scrollModifier
}

private struct OverlayRootView: View {
    @ObservedObject var state: OverlayViewState
    let onTogglePin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            OverlayContent(
                lines: state.lines,
                selectedIndex: state.selectedIndex,
                navigationGeneration: state.navigationGeneration,
                sticky: state.sticky,
                shortcutLabel: state.shortcutLabel,
                statusText: state.statusText,
                inputText: state.inputText,
                projectPreview: state.projectPreview,
                preferences: state.preferences,
                constrainedSize: proxy.size,
                scrollModifier: state.scrollModifier,
                onTogglePin: onTogglePin
            )
        }
    }
}

@MainActor final class OverlayController: NSObject, NSWindowDelegate {
    var onCycleProject: ((Int) -> Void)?
    var onInput: ((PinnedInputEvent) -> Void)?
    var onSelectionChange: ((TicketLine) -> Void)?
    var onTogglePin: (() -> Void)?
    var onPinStateChange: ((Bool) -> Void)?
    var onPresentationPreferencesChange: ((PresentationPreferences) -> Void)?

    private let panel: FocusablePanel
    private let viewState = OverlayViewState()
    private var displayedLines: [TicketLine] = []
    private var selectedIndex = 0
    private var navigationGeneration = 0
    private var anchorMouse = CGPoint.zero
    private var shortcutLabel = "⌥⇧Space"
    private var statusText: String?
    private var inputText: String?
    private var projectPreview: String?
    private var eventMonitor: Any?
    private var globalScrollMonitor: Any?
    private var preferenceObserver: NSObjectProtocol?
    private var interactionPreferenceObserver: NSObjectProtocol?
    private var lastScrollAt = Date.distantPast
    private var isPositioningProgrammatically = false
    private var presentationPreferences = PresentationPreferences.load()
    private var interactionPreferences = PopupInteractionPreferences.load()
    private(set) var isSticky = false

    var isVisible: Bool { panel.isVisible }
    var isActive: Bool { panel.isKeyWindow }
    var selectedLine: TicketLine? { displayedLines.indices.contains(selectedIndex) ? displayedLines[selectedIndex] : displayedLines.first }
    var containsPointer: Bool { panel.isVisible && panel.frame.contains(NSEvent.mouseLocation) }

#if DEBUG
    func captureProbe(to url: URL) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func advanceCaptureProbe() {
        cycleResult(1)
    }

    func retreatCaptureProbe() {
        cycleResult(-1)
    }
#endif

    init(allowsCapture: Bool = false) {
        panel = FocusablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        super.init()
#if DEBUG
        if CommandLine.arguments.contains("--overlay-stress-probe") {
            presentationPreferences.alternativePreviews = 6
        }
        if CommandLine.arguments.contains("--overlay-minimum-stress-probe") {
            presentationPreferences = PresentationPreferences(
                alternativePreviews: 6,
                textSize: .extraLarge,
                width: .custom,
                density: .detailed,
                surface: .solid,
                customWidth: OverlaySizePolicy.minimum.width,
                customHeight: OverlaySizePolicy.minimum.height
            )
        }
#endif
        panel.delegate = self
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = false; panel.hidesOnDeactivate = false
        panel.sharingType = allowsCapture ? .readOnly : .none
        panel.isMovableByWindowBackground = true
        panel.contentMinSize = OverlaySizePolicy.minimum
        panel.contentMaxSize = OverlaySizePolicy.fallbackMaximum
        panel.contentView = NSHostingView(rootView: OverlayRootView(state: viewState) { [weak self] in self?.onTogglePin?() })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleGlobalScroll(event)
        }
        preferenceObserver = NotificationCenter.default.addObserver(forName: .nuncidPresentationPreferencesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let loaded = PresentationPreferences.load()
                self.presentationPreferences = loaded
                guard self.panel.isVisible else { return }
                if loaded.width == .custom,
                   abs(self.panel.frame.width - loaded.customWidth) < 1,
                   abs(self.panel.frame.height - loaded.customHeight) < 1 {
                    self.syncViewState()
                    return
                }
                if self.isSticky { self.renderPinned(useSavedPosition: false) } else { self.renderTemporary() }
            }
        }
        interactionPreferenceObserver = NotificationCenter.default.addObserver(forName: .nuncidPopupInteractionPreferencesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.interactionPreferences = PopupInteractionPreferences.load()
                self.syncViewState()
            }
        }
        syncViewState()
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        if let interactionPreferenceObserver { NotificationCenter.default.removeObserver(interactionPreferenceObserver) }
    }

    func show(_ lines: [TicketLine], near mouse: CGPoint, shortcutLabel: String = "⌥⇧Space") {
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
        renderPinned(useSavedPosition: true)
        onPinStateChange?(true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSticky else { return }
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    func pin(shortcutLabel: String) {
        guard panel.isVisible else { openPinned(shortcutLabel: shortcutLabel); return }
        isSticky = true; self.shortcutLabel = shortcutLabel
        renderPinned(useSavedPosition: false)
        onPinStateChange?(true)
        panel.makeKeyAndOrderFront(nil)
    }

    func unpin() {
        guard panel.isVisible, isSticky else { return }
        isSticky = false
        inputText = nil; projectPreview = nil
        syncViewState()
        onPinStateChange?(false)
        panel.orderFrontRegardless()
    }

    func restorePinnedIfNeeded(shortcutLabel: String) {
        guard interactionPreferences.restorePinned, !panel.isVisible else { return }
        isSticky = true; displayedLines = []; selectedIndex = 0
        statusText = "Ready for a ticket number"
        anchorMouse = NSEvent.mouseLocation
        self.shortcutLabel = shortcutLabel
        renderPinned(useSavedPosition: true)
        panel.orderFrontRegardless()
    }

    func focusPinned() { guard isSticky else { return }; panel.makeKeyAndOrderFront(nil) }

    func replacePinnedResults(_ lines: [TicketLine], selecting key: String? = nil, status: String? = nil) {
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

    func closePinned() {
        guard isSticky else { return }
        onPinStateChange?(false)
        hide()
    }
    func hide() {
        panel.orderOut(nil); isSticky = false; inputText = nil; projectPreview = nil
        syncViewState()
    }

    func windowDidMove(_ notification: Notification) {
        guard isSticky, !isPositioningProgrammatically else { return }
        savePinnedOrigin()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        OverlaySizePolicy.clamped(frameSize, visibleFrame: sender.screen?.visibleFrame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !isPositioningProgrammatically else { return }
        let clamped = OverlaySizePolicy.clamped(panel.frame.size, visibleFrame: panel.screen?.visibleFrame)
        presentationPreferences.width = .custom
        presentationPreferences.customWidth = clamped.width
        presentationPreferences.customHeight = clamped.height
        presentationPreferences.persist()
        onPresentationPreferencesChange?(presentationPreferences)
        if isSticky { savePinnedOrigin() }
        syncViewState()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }
        if event.type == .scrollWheel {
            let pointerInside = event.window === panel || panel.frame.contains(NSEvent.mouseLocation)
            let globalChord = interactionPreferences.scrollModifier.matches(event.modifierFlags)
            guard pointerInside || globalChord else { return event }
            let shiftingProject = pointerInside && isSticky && event.modifierFlags.contains(.shift)
            let delta = shiftingProject && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            navigateScroll(delta: delta, shiftingProject: shiftingProject)
            return pointerInside ? nil : event
        }
        guard isSticky, event.window === panel else { return event }
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

    private func handleGlobalScroll(_ event: NSEvent) {
        guard panel.isVisible,
              !panel.frame.contains(NSEvent.mouseLocation),
              interactionPreferences.scrollModifier.matches(event.modifierFlags) else { return }
        navigateScroll(delta: event.scrollingDeltaY, shiftingProject: false)
    }

    private func navigateScroll(delta: CGFloat, shiftingProject: Bool) {
        guard abs(delta) > 0.1, Date().timeIntervalSince(lastScrollAt) > 0.10 else { return }
        lastScrollAt = Date()
        let direction = delta > 0 ? -1 : 1
        if shiftingProject { onCycleProject?(direction) }
        else { cycleResult(direction) }
    }

    private func cycleResult(_ direction: Int) {
        guard displayedLines.count > 1 else { return }
        navigationGeneration = TicketTitleSettlePolicy.nextGeneration(after: navigationGeneration)
        selectedIndex = CircularNavigation.advancedIndex(current: selectedIndex, direction: direction, count: displayedLines.count)
        inputText = nil; projectPreview = nil; syncViewState()
        if let selectedLine { onSelectionChange?(selectedLine) }
    }

    private func renderTemporary() {
        guard let targetScreen = screen(containing: anchorMouse) else { hide(); return }
        let visible = targetScreen.visibleFrame
        let size = OverlayMetrics.size(lines: displayedLines, sticky: false, preferences: presentationPreferences, visibleFrame: visible)
        var origin = CGPoint(x: anchorMouse.x + 18, y: anchorMouse.y - size.height - 18)
        if origin.x + size.width > visible.maxX { origin.x = anchorMouse.x - size.width - 18 }
        if origin.y < visible.minY { origin.y = anchorMouse.y + 18 }
        origin = PanelPlacement.clamped(origin: origin, size: size, visibleFrame: visible)
        updatePanelSizeLimits(for: targetScreen)
        syncViewState()
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
    }

    private func renderPinned(useSavedPosition: Bool) {
        let shouldRemainFocused = panel.isKeyWindow
        guard let targetScreen = useSavedPosition ? screen(containing: anchorMouse) : (panel.screen ?? screen(containing: NSEvent.mouseLocation)) else {
            hide(); return
        }
        let visible = targetScreen.visibleFrame
        let size = OverlayMetrics.size(lines: displayedLines, sticky: true, preferences: presentationPreferences, visibleFrame: visible)
        let origin = useSavedPosition ? savedOrigin(for: targetScreen, size: size) : PanelPlacement.clamped(origin: panel.frame.origin, size: size, visibleFrame: visible)
        updatePanelSizeLimits(for: targetScreen)
        syncViewState()
        isPositioningProgrammatically = true; panel.setFrame(CGRect(origin: origin, size: size), display: true); isPositioningProgrammatically = false
        if shouldRemainFocused { panel.makeKey() }
    }

    private func syncViewState() {
        viewState.lines = displayedLines
        viewState.selectedIndex = selectedIndex
        viewState.navigationGeneration = navigationGeneration
        viewState.sticky = isSticky
        viewState.shortcutLabel = shortcutLabel
        viewState.statusText = statusText
        viewState.inputText = inputText
        viewState.projectPreview = projectPreview
        viewState.preferences = presentationPreferences
        viewState.scrollModifier = interactionPreferences.scrollModifier
    }

    private func updatePanelSizeLimits(for screen: NSScreen) {
        panel.contentMinSize = OverlaySizePolicy.minimum
        panel.contentMaxSize = OverlaySizePolicy.clamped(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            visibleFrame: screen.visibleFrame
        )
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
