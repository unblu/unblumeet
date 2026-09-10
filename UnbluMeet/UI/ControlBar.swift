import SwiftUI
import AVFoundation
import LiveKit

/// The floating control capsule over the video.
struct ControlBar: View {
    @Binding var micOn: Bool
    @Binding var cameraOn: Bool
    @Binding var backgroundMode: BackgroundMode
    @Binding var layoutMode: LayoutMode
    @Binding var captionsOn: Bool
    @Binding var cameraDeviceID: String
    @Binding var audioOutputID: String
    @Binding var audioInputID: String
    @Binding var presenterOverlay: Bool
    let canPin: Bool
    let isSharing: Bool
    let micLevel: Float
    let onOpenSharePicker: () -> Void
    let onStopShare: () -> Void

    let onLeave: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            dragHandle

            SplitButton(system: micOn ? "mic.fill" : "mic.slash.fill",
                        help: micOn ? "Mute" : "Unmute",
                        menuHelp: "Microphone and speaker",
                        danger: !micOn,
                        action: { micOn.toggle() },
                        menu: { audioMenu })

            SplitButton(system: cameraOn ? "video.fill" : "video.slash.fill",
                        help: cameraOn ? "Stop video" : "Start video",
                        menuHelp: "Choose a camera",
                        danger: !cameraOn,
                        action: { cameraOn.toggle() },
                        menu: { cameraMenu })

            SplitButton(system: backgroundMode == .none ? "person.and.background.dotted" : "sparkles",
                        help: backgroundMode == .none ? "Blur background" : "Turn background off",
                        menuHelp: "Background options",
                        active: backgroundMode != .none,
                        action: { backgroundMode = backgroundMode == .none ? .blur : .none },
                        menu: { backgroundMenu })
                .disabled(!cameraOn)
                .opacity(cameraOn ? 1 : 0.45)

            groupGap

            LayoutSelector(mode: $layoutMode, canPin: canPin)

            groupGap

            CircleButton(system: isSharing ? "rectangle.inset.filled.badge.record" : "rectangle.on.rectangle",
                         help: isSharing ? "Stop sharing" : "Share screen",
                         active: isSharing) {
                isSharing ? onStopShare() : onOpenSharePicker()
            }

            CircleButton(system: captionsOn ? "captions.bubble.fill" : "captions.bubble",
                         help: captionsOn ? "Turn captions off" : "Turn captions on",
                         active: captionsOn) {
                captionsOn.toggle()
            }

            groupGap

            Button(action: onLeave) {
                Image(systemName: "phone.down.fill")
                    .hitArea(width: 48, height: 36)
            }
            .buttonStyle(PressableButtonStyle())
            .background(Color.red, in: Capsule())
            .foregroundStyle(.white)
            .help("Leave")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }

    /// Space plus a hairline, so groups read as groups without a heavy rule.
    private var groupGap: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }

    private var dragHandle: some View {
        // Dragging lives on its own handle so it cannot swallow button clicks
        // the way a gesture on the whole capsule would.
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 34)
            .contentShape(Rectangle())
            .gesture(
                // Global coordinate space, not local: this handle lives
                // inside the view it is moving, so in local space the origin
                // shifts with every update and each translation is measured
                // from a different place — which reads as jerking.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation) }
                    .onEnded { _ in onDragEnded() }
            )
            .help("Drag to move")
    }

    /// A popover rather than a Menu: the level meter has to animate, and menu
    /// content is only built when the menu opens.
    private var audioMenu: some View {
        let inputs = AudioDevices.entries(
            from: AudioManager.shared.inputDevices.map { (id: $0.deviceId, name: $0.name) })
        let outputs = AudioDevices.entries(
            from: AudioManager.shared.outputDevices.map { (id: $0.deviceId, name: $0.name) })

        return VStack(alignment: .leading, spacing: 10) {
            Text("Microphone").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $audioInputID) {
                ForEach(inputs) { entry in
                    Text(entry.label).tag(entry.id)
                }
            }
            .labelsHidden()

            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.caption)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(micLevel > 0.75 ? Color.orange : Color.green)
                            .frame(width: max(2, proxy.size.width * CGFloat(micLevel)))
                    }
                }
                .frame(height: 6)
            }
            Text("Speak to check the microphone.")
                .font(.caption2).foregroundStyle(.secondary)

            Divider()

            Text("Speaker").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $audioOutputID) {
                ForEach(outputs) { entry in
                    Text(entry.label).tag(entry.id)
                }
            }
            .labelsHidden()
        }
        .padding(14)
        .frame(width: 290)
        .onAppear {
            // The device module only enumerates properly once audio is
            // running, so the selection is resolved when the menu opens
            // rather than once at join time.
            audioInputID = AudioDevices.resolvedSelection(
                current: audioInputID,
                activeID: AudioManager.shared.inputDevice.deviceId,
                entries: inputs)
            audioOutputID = AudioDevices.resolvedSelection(
                current: audioOutputID,
                activeID: AudioManager.shared.outputDevice.deviceId,
                entries: outputs)
        }
    }

    private var cameraMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $cameraDeviceID) {
                ForEach(CameraCapture.availableDevices(), id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
            .labelsHidden()
        }
        .padding(14)
        .frame(width: 290)
    }

    private var backgroundMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Background").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $backgroundMode) {
                Text("None").tag(BackgroundMode.none)
                Text("Blur").tag(BackgroundMode.blur)
                Text("Colour").tag(BackgroundMode.image)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            Toggle("Show me on my screen share", isOn: $presenterOverlay)
            Text("Cuts you out of the camera and draws you over the shared screen.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
    }
}

/// All three layouts visible at once, so the current one is readable without
/// opening anything.
private struct LayoutSelector: View {
    @Binding var mode: LayoutMode
    let canPin: Bool

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutMode.allCases, id: \.self) { option in
                let enabled = option != .pinned || canPin
                Button {
                    withAnimation(.snappy(duration: 0.22)) { mode = option }
                } label: {
                    Image(systemName: Self.symbol(for: option))
                        .hitArea(width: 34, height: 28)
                        .background {
                            // One capsule that moves, rather than one
                            // appearing and another vanishing.
                            if mode == option {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "layout", in: highlight)
                            }
                        }
                        .foregroundStyle(mode == option ? .white : (enabled ? .primary : .secondary))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.94))
                .disabled(!enabled)
                .help(Self.help(for: option, enabled: enabled))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.10), in: Capsule())
    }

    static func symbol(for mode: LayoutMode) -> String {
        switch mode {
        case .grid: "square.grid.2x2"
        case .speaker: "person.crop.rectangle"
        case .pinned: "pin.fill"
        }
    }

    static func help(for mode: LayoutMode, enabled: Bool) -> String {
        switch mode {
        case .grid: "Grid"
        case .speaker: "Speaker"
        // Pinning is done by double-clicking a video, so the segment is inert
        // until something is pinned — saying so beats a segment that silently
        // bounces back to grid.
        case .pinned: "Pinned — double-click a video to choose a different one"
        }
    }
}

/// A toggle with its own options attached: click the icon to switch the thing
/// on or off, click the chevron to choose which device it uses.
private struct SplitButton<Menu: View>: View {
    let system: String
    let help: String
    let menuHelp: String
    var active: Bool = false
    var danger: Bool = false
    let action: () -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var showMenu = false

    @State private var hoveringMenu = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Image(systemName: system)
                    .contentTransition(.symbolEffect(.replace))
                    .hitArea(width: 36, height: 34)
            }
            .buttonStyle(PressableButtonStyle())
            .help(help)

            // The chevron was a 16pt sliver.
            Button {
                showMenu.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .hitArea(width: 26, height: 34)
                    .background(hoveringMenu ? Color.primary.opacity(0.12) : .clear,
                                in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .help(menuHelp)
            .onHover { hoveringMenu = $0 }
            .popover(isPresented: $showMenu, arrowEdge: .bottom) { menu() }
        }
        .background(background, in: Capsule())
        .overlay(alignment: .trailing) {
            // Hairline between the two halves, inset so it does not touch the
            // capsule edges.
            Rectangle()
                .fill(.primary.opacity(0.18))
                .frame(width: 1, height: 18)
                .offset(x: -26)
        }
        .foregroundStyle(danger ? .white : .primary)
        .animation(.snappy(duration: 0.2), value: danger)
        .animation(.snappy(duration: 0.2), value: active)
    }

    private var background: some ShapeStyle {
        if danger { return AnyShapeStyle(Color.red) }
        if active { return AnyShapeStyle(Color.accentColor.opacity(0.35)) }
        return AnyShapeStyle(Color.primary.opacity(0.10))
    }
}

/// A round icon button with three visual states: normal, active, danger.
struct CircleButton: View {
    let system: String
    let help: String
    var active: Bool = false
    var danger: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .contentTransition(.symbolEffect(.replace))
                .hitArea(width: 36, height: 36)
        }
        .buttonStyle(PressableButtonStyle())
        .background(background, in: Circle())
        .overlay(Circle().stroke(.primary.opacity(hovering ? 0.25 : 0), lineWidth: 1))
        .foregroundStyle(danger ? .white : .primary)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: active)
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(help)
    }

    private var background: some ShapeStyle {
        if danger { return AnyShapeStyle(Color.red) }
        if active { return AnyShapeStyle(Color.accentColor.opacity(0.35)) }
        return AnyShapeStyle(Color.primary.opacity(0.10))
    }
}
