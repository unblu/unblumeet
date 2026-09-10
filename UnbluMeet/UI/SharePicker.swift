import SwiftUI

/// Sheet for choosing what to share.
struct SharePicker: View {
    let catalog: ShareCatalog
    let onPick: (ShareTarget) -> Void
    let onSelectRegion: (ShareTarget) -> Void
    let onCancel: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case screens = "Screens"
        case windows = "Windows"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .screens
    @State private var selectedID: String?

    private var shown: [ShareTarget] {
        tab == .screens ? catalog.screens : catalog.windows
    }

    private var selected: ShareTarget? {
        shown.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 880, height: 620)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("Share a screen or window")
                .font(.headline)
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(.vertical, 14)
        .onChange(of: tab) { _, _ in selectedID = nil }
    }

    @ViewBuilder private var content: some View {
        if let error = catalog.error {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(error)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .frame(maxWidth: 560, alignment: .leading)

                    if catalog.needsPermission {
                        HStack {
                            Button("Open System Settings") { ScreenPermission.openSettings() }
                            Button("Try again") { catalog.load() }
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shown.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text(catalog.isLoading ? "Looking for windows…" : "Nothing to share here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tab == .screens ? 260 : 190),
                                             spacing: 16)],
                          spacing: 16) {
                    ForEach(shown) { target in
                        ShareTargetCard(target: target,
                                        image: catalog.thumbnails[target.id],
                                        selected: target.id == selectedID)
                            .onTapGesture { selectedID = target.id }
                            .onTapGesture(count: 2) { onPick(target) }
                    }
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack {
            if catalog.isLoading {
                ProgressView().controlSize(.small)
                Text("Loading previews…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if tab == .screens {
                Button("Share part of the screen…") {
                    guard let selected else { return }
                    onSelectRegion(selected)
                }
                .disabled(selected == nil)
                .help("Drag a rectangle on the display to share only that area")
            }

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Share") {
                guard let selected else { return }
                onPick(selected)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil)
        }
        .padding(14)
    }
}

private struct ShareTargetCard: View {
    let target: ShareTarget
    let image: CGImage?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Placeholder rather than a spinner per card: thirty
                    // spinners read as thirty problems.
                    Image(systemName: target.kind == .display ? "display" : "macwindow")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)

            Text(target.name)
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
}
