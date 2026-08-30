import AppKit
import SwiftUI

struct ReleaseNoteItem: Equatable {
    let label: String
    let detail: String
}

struct ReleaseNote: Identifiable, Equatable {
    let version: String
    let isoDate: String
    let date: String
    let theme: String
    let headline: String
    let intro: String
    let items: [ReleaseNoteItem]

    var id: String { version }
}

enum ReleaseHistory {
    static let notes: [ReleaseNote] = [
        ReleaseNote(
            version: "0.3.3",
            isoDate: "2026-08-30",
            date: "30 August 2026",
            theme: "A clearer story",
            headline: "See what gets better, release by release.",
            intro: "GLINT now explains every update in clear, positive language—right inside the app.",
            items: [
                ReleaseNoteItem(label: "Easy to find", detail: "Open Version History from the menu, About window, or the version in Settings."),
                ReleaseNoteItem(label: "Quick to scan", detail: "Every release leads with the benefit, followed by short details that matter in everyday use."),
                ReleaseNoteItem(label: "Always oriented", detail: "Your running version is highlighted, so you immediately know what is new for you.")
            ]
        ),
        ReleaseNote(
            version: "0.3.2",
            isoDate: "2026-08-30",
            date: "30 August 2026",
            theme: "Activation",
            headline: "Scanning now does exactly what you expect.",
            intro: "Three clear choices replace the old overlapping hover behaviors, with visible status whenever hands-free scanning is active.",
            items: [
                ReleaseNoteItem(label: "Clear choices", detail: "Choose Off, Toggle Hover, or Press to Scan."),
                ReleaseNoteItem(label: "Calm hover", detail: "A settled pointer location is scanned once instead of restarting in a loop."),
                ReleaseNoteItem(label: "Visible status", detail: "The menu bar icon shows when hover is on and confirms when GLINT finds a ticket."),
                ReleaseNoteItem(label: "Tidier Settings", detail: "Your setup is summarized one item at a time, without a distracting scrollbar.")
            ]
        ),
        ReleaseNote(
            version: "0.3.1",
            isoDate: "2026-08-29",
            date: "29 August 2026",
            theme: "Open source",
            headline: "GLINT is open and easier to explore.",
            intro: "The project is now published under the GNU AGPL v3.0 with a refreshed public home on GitHub.",
            items: [
                ReleaseNoteItem(label: "Open by design", detail: "Read, learn from, and improve the source under a strong free-software license."),
                ReleaseNoteItem(label: "A better front door", detail: "Updated visuals and documentation make the workflow easier to understand before installing.")
            ]
        ),
        ReleaseNote(
            version: "0.3.0",
            isoDate: "2026-08-29",
            date: "29 August 2026",
            theme: "Everyday flow",
            headline: "Ticket context feels immediate and personal.",
            intro: "GLINT became a polished daily companion with anchored feedback, smarter matching, and cards that adapt to you.",
            items: [
                ReleaseNoteItem(label: "See the scan", detail: "Subtle on-screen cues show where GLINT is looking and which ticket it recognized."),
                ReleaseNoteItem(label: "Trust the result", detail: "Evidence-ranked resolution favors real, relevant records across connected trackers."),
                ReleaseNoteItem(label: "Make it yours", detail: "Tune card size, density, surface, and alternative previews in Settings.")
            ]
        ),
        ReleaseNote(
            version: "0.2.2",
            isoDate: "2026-08-29",
            date: "29 August 2026",
            theme: "Settings",
            headline: "Everything important has a clear home.",
            intro: "Settings were reorganized into focused panes with native controls and plain-language guidance.",
            items: [
                ReleaseNoteItem(label: "Easy navigation", detail: "General, Shortcuts, and Privacy are separated into calm, focused pages."),
                ReleaseNoteItem(label: "Immediate confidence", detail: "Changes apply as you make them, with visible feedback and straightforward defaults.")
            ]
        ),
        ReleaseNote(
            version: "0.2.1",
            isoDate: "2026-08-28",
            date: "28 August 2026",
            theme: "Reliability",
            headline: "The pinned navigator stays in your rhythm.",
            intro: "Focus handling is more dependable, so keyboard entry and navigation remain with the ticket card when you need them.",
            items: [
                ReleaseNoteItem(label: "Steady focus", detail: "Pinned-card interaction remains reliable while moving between results and projects."),
                ReleaseNoteItem(label: "Safer changes", detail: "Expanded regression checks protect the navigator’s most important state transitions.")
            ]
        ),
        ReleaseNote(
            version: "0.2.0",
            isoDate: "2026-08-28",
            date: "28 August 2026",
            theme: "Navigator",
            headline: "Point, inspect, and keep the right ticket close.",
            intro: "GLINT grew from a quick lookup into a flexible ticket navigator that can stay on screen while you work.",
            items: [
                ReleaseNoteItem(label: "Richer context", detail: "The primary card shows useful ticket detail with nearby alternatives ready to browse."),
                ReleaseNoteItem(label: "Pinned when useful", detail: "Keep a result visible, move it between screens, and navigate with the wheel or keyboard."),
                ReleaseNoteItem(label: "Your shortcuts", detail: "Choose global shortcuts for inspecting and opening the pinned card.")
            ]
        ),
        ReleaseNote(
            version: "0.1.0",
            isoDate: "2026-08-28",
            date: "28 August 2026",
            theme: "First release",
            headline: "Ticket context, right where you point.",
            intro: "The first GLINT release turned a ticket key on screen into a real tracker record without interrupting your work.",
            items: [
                ReleaseNoteItem(label: "Local understanding", detail: "Apple Vision reads only a small region beneath the pointer, entirely on your Mac."),
                ReleaseNoteItem(label: "Real records", detail: "Read-only lookups connect visible keys to PPM, PMA, and GitHub."),
                ReleaseNoteItem(label: "No invented answers", detail: "When a record cannot be verified, GLINT does not fill the gap with a placeholder.")
            ]
        )
    ]

    static func isValid(currentVersion: String) -> Bool {
        let versions = notes.map(\.version)
        return !notes.isEmpty
            && Set(versions).count == versions.count
            && versions.first == currentVersion
            && notes.allSatisfy { !$0.headline.isEmpty && !$0.intro.isEmpty && !$0.items.isEmpty }
    }
}

struct VersionHistoryView: View {
    let currentVersion: String
    @State private var selectedVersion: String

    init(currentVersion: String) {
        self.currentVersion = currentVersion
        _selectedVersion = State(initialValue: ReleaseHistory.notes.first(where: { $0.version == currentVersion })?.version ?? ReleaseHistory.notes.first?.version ?? "")
    }

    private var selectedNote: ReleaseNote? {
        ReleaseHistory.notes.first(where: { $0.version == selectedVersion })
    }

    var body: some View {
        HStack(spacing: 0) {
            versionRail
            Divider()
            detail
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 480, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var versionRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Version History", systemImage: "clock.arrow.circlepath")
                    .font(.title2.weight(.bold))
                Text("What’s new in GLINT")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 15)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(ReleaseHistory.notes) { note in
                        versionButton(note)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Running v\(currentVersion)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 210)
        .background(VersionRailMaterial())
    }

    private func versionButton(_ note: ReleaseNote) -> some View {
        let selected = note.version == selectedVersion
        let current = note.version == currentVersion
        return Button {
            selectedVersion = note.version
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(current ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("v\(note.version)")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                        if current {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.accentColor)
                        }
                    }
                    Text(note.date)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.72) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Version \(note.version)\(current ? ", current" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var detail: some View {
        if let note = selectedNote {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: note.version == currentVersion ? "sparkles" : "checkmark.circle")
                            .font(.system(size: 24, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("v\(note.version)").font(.title2.monospacedDigit().weight(.bold))
                                Text(note.theme.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.7)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(note.date).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 24)

                    Text(note.headline)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(note.intro)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 9)
                        .padding(.bottom, 26)

                    VStack(spacing: 0) {
                        ForEach(Array(note.items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24, height: 24)
                                    .background(Color.accentColor.opacity(0.09), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label).font(.headline)
                                    Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 13)
                            if index < note.items.count - 1 { Divider().padding(.leading, 36) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.09)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(30)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct VersionRailMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
