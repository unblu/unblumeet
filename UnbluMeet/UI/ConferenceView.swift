import SwiftUI
import AVFoundation
import LiveKit

struct ConferenceView: View {
    let settings: SettingsStore
    let conversationId: String
    let topic: String
    let identity: String
    let onLeave: () -> Void

    @State private var controller: RoomController?
    @State private var compositor: MetalCompositor?
    @State private var chat: ChatService?
    @State private var subscriptionPolicy: SubscriptionPolicy?

    @State private var micOn = true
    @State private var cameraOn = false
    @State private var chatShown = true
    @State private var captionsOn = false
    @State private var captions = CaptionService()
    @State private var summary = SummaryService()
    @State private var summaryShown = false
    @State private var summaryWidth: CGFloat = 320
    @State private var backgroundMode: BackgroundMode = .none
    @State private var layoutMode: LayoutMode = .grid
    @State private var focusID: String?
    @State private var page = 0
    @State private var stripOffset = 0
    @State private var stripScrollAccumulator: CGFloat = 0
    @State private var barPosition = BarPosition()
    @State private var stageSize: CGSize = .zero
    @State private var chatWidth: CGFloat = 300
    @State private var shareError: String?
    @State private var showSharePicker = false
    @State private var markTool: MarkTool = .pen
    @State private var presenterOverlay = false
    /// Distinguishes "not started yet" from "dropped after being in the
    /// call", which look identical on the controller.
    @State private var didConnect = false
    @State private var speakerSwitcher = SpeakerSwitcher()
    @State private var speakerFocusID: String?
    /// The arrangement the user has dragged tiles into.
    @State private var tileOrder: [String] = []
    @State private var shareCatalog = ShareCatalog()
    @State private var zooms: [String: ZoomState] = [:]
    @State private var cameraDeviceID = ""
    @State private var audioOutputID = ""
    @State private var audioInputID = ""
    @State private var micLevels = AudioLevelMonitor()

    var body: some View {
        HStack(spacing: 0) {
            if summaryShown {
                SummaryPanel(summary: summary,
                             width: summaryWidth,
                             recognitionIssue: recognitionIssue)
                    .transition(.move(edge: .leading))
                ResizableDivider(width: $summaryWidth, range: 260 ... 560)
            }
            stage
            if chatShown, let chat {
                ResizableDivider(width: $chatWidth, range: 220 ... 640)
                ChatView(chat: chat, ownPersonId: identity, width: chatWidth)
                    // Slides in from the edge it lives on; the stage resizes
                    // to meet it rather than the panel appearing on top.
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.28), value: chatShown)
        .animation(.snappy(duration: 0.28), value: summaryShown)
        .frame(minWidth: 940, minHeight: 560)
        .sheet(isPresented: $showSharePicker) {
            SharePicker(catalog: shareCatalog,
                        onPick: { target in
                            showSharePicker = false
                            shareCatalog.cancel()
                            startShare(target)
                        },
                        onSelectRegion: { target in
                            // Hide the sheet first: the overlay covers the
                            // display, and picking a region out from under a
                            // modal window is not possible.
                            showSharePicker = false
                            shareCatalog.cancel()
                            selectRegion(of: target)
                        },
                        onCancel: {
                            showSharePicker = false
                            shareCatalog.cancel()
                        })
        }
        .task { await join() }
        .task {
            // Not a TimelineView: this mutates state, and doing that while a
            // body is being evaluated is undefined behaviour in SwiftUI — the
            // switcher's dwell never completed, so the large tile in speaker
            // mode never changed hands.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                speakerTick()
            }
        }
        .onChange(of: captionsOn) { _, _ in Task { await syncRecognition() } }
        .onChange(of: summaryShown) { _, on in
            Task {
                await syncRecognition()
                on ? summary.start() : summary.stop()
            }
        }
        .onChange(of: controller?.state) { _, state in
            if state == .connected { didConnect = true }
        }
        .onChange(of: layoutMode) { _, mode in
            // Picking pinned with nothing pinned used to show an empty stage
            // until you happened to double-click a tile.
            guard mode == .pinned, focusID == nil, let controller else { return }
            focusID = speakerFocusID
                ?? TileOrder.apply(tileOrder, to: controller.allTileKeys()).first
        }
        .onChange(of: micOn) { _, on in Task { await controller?.setMicrophone(on) } }
        .onChange(of: cameraOn) { _, on in Task { await controller?.setCamera(on) } }
        .onChange(of: backgroundMode) { _, mode in controller?.setBackgroundMode(mode) }
        .onChange(of: presenterOverlay) { _, on in
            settings.presenterOverlay = on
            controller?.setPresenterOverlay(on)
            refreshLocalPreview()
        }
        .onChange(of: controller?.isSharingScreen) { _, _ in refreshLocalPreview() }
        .onChange(of: cameraDeviceID) { _, id in
            guard !id.isEmpty else { return }
            controller?.selectCamera(id)
        }
        .onChange(of: controller?.activeScreenShareID) { _, shareID in
            // A share appearing nudges everyone to pin it.
            guard let shareID else {
                // Share ended: back to the grid rather than stranding
                // everyone pinned to a tile that no longer exists.
                if layoutMode == .pinned, focusID.map(RoomController.isScreenKey) == true {
                    layoutMode = .grid
                    focusID = nil
                    stripOffset = 0
                }
                return
            }
            focusID = shareID
            layoutMode = .pinned
        }
        .onChange(of: audioInputID) { _, id in
            guard let device = AudioManager.shared.inputDevices
                .first(where: { $0.deviceId == id }) else { return }
            AudioManager.shared.inputDevice = device
        }
        .onChange(of: audioOutputID) { _, id in
            guard let device = AudioManager.shared.outputDevices
                .first(where: { $0.deviceId == id }) else { return }
            AudioManager.shared.outputDevice = device
        }
    }

    /// Video fills the window; everything else floats on top of it.
    private var stage: some View {
        ZStack(alignment: .bottom) {
            videoArea
            emptyRoomOverlay
            titleOverlay
            statusOverlay
            stripPager
            captionBar
            MovableBar(position: barPosition) { controlBar }.padding(.bottom, 18)
        }
        .overlay(alignment: .leading) { markToolbar }
        .overlay(alignment: .bottomTrailing) { chatButton }
        .overlay(alignment: .bottomLeading) { summaryButton }
        .background(Color.black)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { stageSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in stageSize = size }
            }
        }
    }

    private var controlBar: some View {
        ControlBar(micOn: $micOn,
                   cameraOn: $cameraOn,
                   backgroundMode: $backgroundMode,
                   layoutMode: $layoutMode,
                   captionsOn: $captionsOn,
                   cameraDeviceID: $cameraDeviceID,
                   audioOutputID: $audioOutputID,
                   audioInputID: $audioInputID,
                   presenterOverlay: $presenterOverlay,
                   canPin: true,
                   isSharing: controller?.isSharingScreen ?? false,
                   micLevel: micLevels.level,
                   onOpenSharePicker: {
                       showSharePicker = true
                       shareCatalog.load()
                   },
                   onStopShare: { Task { await controller?.stopScreenShare() } },
                   onLeave: { Task { await leave() } },
                   onDragChanged: { translation in
                       barPosition.drag(translation, within: stageSize)
                   },
                   onDragEnded: { barPosition.endDrag() })
    }

    @ViewBuilder private var videoArea: some View {
        if let controller, let compositor {
            GeometryReader { proxy in
                let pageTiles = tiles(for: controller)
                let _ = recoverIfPinnedTileVanished(pageTiles)
                CompositorView(compositor: compositor,
                               participantIDs: pageTiles.map(\.participantID),
                               mode: layoutMode,
                               focusID: focusID,
                               stripOffset: stripOffset,
                               onScrollZoom: { participantID, delta, framePoint in
                                   var zoom = zooms[participantID] ?? .identity
                                   let newScale = min(max(zoom.scale + delta, 1), 6)
                                   // Ease the centre toward whatever is under
                                   // the cursor, so zooming goes where you
                                   // are looking instead of always at the
                                   // middle.
                                   if newScale > 1 {
                                       let pull: CGFloat = 0.3
                                       zoom.center = CGPoint(
                                           x: zoom.center.x + (framePoint.x - zoom.center.x) * pull,
                                           y: zoom.center.y + (framePoint.y - zoom.center.y) * pull)
                                   } else {
                                       zoom.center = CGPoint(x: 0.5, y: 0.5)
                                   }
                                   zoom.scale = newScale
                                   zooms[participantID] = zoom
                                   compositor.setZoom(zoom, for: participantID)
                               },
                               onStripScroll: { delta in scrollStrip(delta, controller: controller) },
                               onPin: { participantID in togglePin(participantID) },
                               onDraw: { participantID, points, strokeID, isFinal in
                                   guard let transport = controller.markTransport else { return }
                                   let mark = Mark(targetParticipantID: participantID,
                                                   authorID: identity,
                                                   points: points,
                                                   colorIndex: markColorIndex,
                                                   createdAt: Date().timeIntervalSince1970,
                                                   id: strokeID)
                                   Task {
                                       isFinal ? await transport.send(mark)
                                               : await transport.stream(mark)
                                   }
                               },
                               tool: markTool,
                               markColorIndex: markColorIndex,
                               onCallout: { participantID, region in
                                   guard let transport = controller.markTransport else { return }
                                   let callout = Callout(targetParticipantID: participantID,
                                                         authorID: identity,
                                                         region: region,
                                                         colorIndex: markColorIndex,
                                                         createdAt: Date().timeIntervalSince1970)
                                   Task { await transport.send(callout) }
                               },
                               onReorder: { source, target in
                                   let ids = TileOrder.apply(tileOrder, to: controller.allTileKeys())
                                   tileOrder = TileOrder.moving(source, onto: target, in: ids)
                               })
                    .onChange(of: pageTiles) { _, newTiles in
                        policy(for: controller).apply(tiles: newTiles, viewportSize: proxy.size)
                    }
                    .overlay {
                        tileBadges(controller: controller,
                                   compositor: compositor,
                                   size: proxy.size)
                    }
            }
        } else {
            Color.black
        }
    }

    /// Speaking ring and mute badge per tile.
    private func tileBadges(controller: RoomController,
                            compositor: MetalCompositor,
                            size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let state = controller.audioState()
            let live = controller.subscribedTileKeys()
            let rendered = compositor.renderedIDs
            ZStack(alignment: .topLeading) {
                // Zero-size anchor: without it the ZStack sizes to its
                // largest child, so offsets would be measured from a centred
                // origin rather than the video's top-left.
                Color.clear.frame(width: 0, height: 0)

                ForEach(compositor.drawnTiles, id: \.participantID) { tile in
                    let frame = CGRect(x: tile.rect.minX * size.width,
                                       y: tile.rect.minY * size.height,
                                       width: tile.rect.width * size.width,
                                       height: tile.rect.height * size.height)
                    let speaking = state.speaking.contains(tile.participantID)
                    let muted = state.muted.contains(tile.participantID)
                    let paused = !live.contains(tile.participantID)
                    let hasVideo = rendered.contains(tile.participantID)

                    ZStack(alignment: .bottomLeading) {
                        if hasVideo {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(speaking ? Color.green : .clear, lineWidth: 3)
                        } else {
                            TileCard(name: controller.displayName(for: tile.participantID),
                                     speaking: speaking,
                                     muted: muted,
                                     level: state.levels[tile.participantID] ?? 0)
                        }

                        HStack(spacing: 5) {
                            if paused, hasVideo {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                            if muted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.system(size: 9))
                            } else if AudioLevelBars.isAudible(state.levels[tile.participantID] ?? 0,
                                                               speaking: speaking) {
                                AudioLevelBars(level: state.levels[tile.participantID] ?? 0)
                            }
                            Text(controller.displayName(for: tile.participantID))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
            .animation(nil, value: state.speaking)
        }
    }

    /// Live captions for whoever is speaking, above the control bar.
    private func speakerTick() {
        guard let controller else { return }
        let speaker = controller.activeSpeaker()
        followSpeaker(speaker)

        guard captionsOn || summaryShown else { return }
        let name = speaker.map { controller.displayName(for: RoomController.identityKey(for: $0)) } ?? ""
        captions.retarget(to: speaker, displayName: name)
        captions.flushNow()
    }

    private func followSpeaker(_ speaker: RemoteParticipant?) {
        let key = speaker.map(RoomController.identityKey(for:))
        let chosen = speakerSwitcher.update(speaking: key, now: Date().timeIntervalSince1970)
        if chosen != speakerFocusID { speakerFocusID = chosen }
    }

    /// Surfaced in the summary panel, which may be the only place it is
    /// visible: the caption bubble that normally reports this is hidden
    /// whenever captions are off.
    private var recognitionIssue: String? {
        if case .unavailable(let reason) = captions.mode { return reason }
        return nil
    }

    @ViewBuilder private var captionBar: some View {
        if captionsOn {
            VStack {
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.4)) { _ in
                    captionContent
                }
                .padding(.bottom, 86)
                .padding(.horizontal, 40)
            }
        }
    }

    @ViewBuilder private var captionContent: some View {
        switch captions.mode {
        case .unavailable(let reason):
            captionBubble(Text(reason).foregroundStyle(.orange))
        case .server:
            captionBubble(VStack(alignment: .leading, spacing: 2) {
                Text("Captions are using Apple's servers — audio leaves this Mac.")
                    .font(.caption2).foregroundStyle(.orange)
                captionLine
            })
        case .onDevice:
            if !captions.text.isEmpty || !captions.history.isEmpty {
                captionBubble(captionLine)
            } else if let failure = captions.lastFailure {
                captionBubble(Text("Captions: \(failure)").foregroundStyle(.orange))
            } else {
                // Silence and a broken recogniser look identical without this.
                captionBubble(
                    Text(captions.isListening
                         ? "Listening for speech…"
                         : "Waiting for someone to speak…")
                        .foregroundStyle(.secondary))
            }
        case .off:
            EmptyView()
        }
    }

    /// Two lines of room, always.
    private var captionLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let previous = captions.history.last, previous.text != captions.text {
                spokenLine(speaker: previous.speaker, text: previous.text)
                    .lineLimit(1)
                    .opacity(0.55)
            }
            spokenLine(speaker: captions.speakerName, text: captions.text)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .bottomLeading)
    }

    private func spokenLine(speaker: String, text: String) -> some View {
        (Text(speaker.isEmpty ? "" : "\(speaker): ").foregroundStyle(.secondary)
         + Text(text))
            .font(.system(size: 15, weight: .medium))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captionBubble(_ content: some View) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: 720, alignment: .leading)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
    }

    /// Arrows over the speaker strip.
    @ViewBuilder private var stripPager: some View {
        if layoutMode == .speaker, let controller {
            let total = max(0, controller.remoteParticipants.count - 1)
            let maxOffset = TileLayout.maxStripOffset(participantCount: controller.remoteParticipants.count)
            if maxOffset > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Button { stripOffset = max(0, stripOffset - 1) } label: {
                            Image(systemName: "chevron.left")
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(stripOffset == 0)

                        Spacer()

                        Text("\(stripOffset + 1)–\(min(stripOffset + TileLayout.stripCapacity, total)) of \(total)")
                            .font(.caption).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Button { stripOffset = min(maxOffset, stripOffset + 1) } label: {
                            Image(systemName: "chevron.right")
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(stripOffset >= maxOffset)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 92)
                }
            }
        }
    }

    private var titleOverlay: some View {
        VStack {
            HStack {
                // Back sits top-left where macOS puts it.
                Button {
                    Task { await leave() }
                } label: {
                    Label("Conferences", systemImage: "chevron.left")
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
                .help("Leave and return to the conference list")

                if layoutMode != .grid {
                    Button {
                        layoutMode = .grid
                        focusID = nil
                        stripOffset = 0
                    } label: {
                        Label("Grid", systemImage: "chevron.left")
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help("Back to grid")
                }
                Text(topic)
                    .font(.headline)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                pageControl
            }
            .padding(16)
            Spacer()
        }
    }

    @ViewBuilder private var pageControl: some View {
        if layoutMode == .grid, let controller {
            let pages = TileLayout.pageCount(
                participantCount: controller.remoteParticipants.count, mode: .grid)
            if pages > 1 {
                HStack(spacing: 8) {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0)
                    Text("\(page + 1)/\(pages)").monospacedDigit().font(.caption)
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pages - 1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    /// Only surfaces while something is wrong or pending — a working call
    /// needs no status text cluttering the video.
    private var statusOverlay: some View {
        statusContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder private var statusContent: some View {
        if let shareError {
            failureCard(title: "Screen sharing failed",
                        message: shareError,
                        retry: {
                            self.shareError = nil
                            showSharePicker = true
                            shareCatalog.load()
                        },
                        dismiss: { self.shareError = nil })
        } else if let microphoneFailure = controller?.microphoneFailure {
            failureCard(title: "Microphone failed",
                        message: microphoneFailure,
                        retry: {
                            controller?.clearMicrophoneFailure()
                            Task { await controller?.setMicrophone(true) }
                        },
                        dismiss: {
                            controller?.clearMicrophoneFailure()
                            micOn = false
                        })
        } else if let cameraFailure = controller?.cameraFailure {
            failureCard(title: "Camera failed",
                        message: cameraFailure,
                        retry: {
                            controller?.clearCameraFailure()
                            Task { await controller?.setCamera(true) }
                        },
                        dismiss: {
                            controller?.clearCameraFailure()
                            cameraOn = false
                        })
        } else {
            connectionStatus
        }
    }

    /// Every error gets the same two ways out: try the thing again, or stop
    /// trying.
    private func failureCard(title: String,
                             message: String,
                             retry: @escaping () -> Void,
                             dismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ScrollView {
                Text(message)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack {
                Button("Try again", action: retry).keyboardShortcut(.defaultAction)
                Button("Dismiss", action: dismiss).keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var connectionStatus: some View {
        switch controller?.state ?? .disconnected {
        case .connected:
            EmptyView()
        case .connecting:
            JoinProgressView(topic: topic, phase: controller?.joinPhase ?? .preparing)
        case .disconnected:
            // Before the first connect this is just the starting state; after
            // one it means the call dropped, which needs a way out.
            if didConnect {
                JoinProgressView(topic: topic,
                                 phase: .failed("The connection to the call was lost."),
                                 onRetry: { Task { await join() } },
                                 onLeave: { Task { await leave() } })
            } else {
                JoinProgressView(topic: topic, phase: .preparing)
            }
        case .failed(let message):
            JoinProgressView(topic: topic,
                             phase: .failed(message),
                             onRetry: { Task { await join() } },
                             onLeave: { Task { await leave() } })
        }
    }

    private var summaryButton: some View {
        CircleButton(system: "sparkles",
                     help: summaryShown ? "Hide call summary" : "Show call summary",
                     active: summaryShown) {
            summaryShown.toggle()
        }
        .padding(.leading, 18)
        .padding(.bottom, 18)
    }

    /// Chat sits in its own corner rather than in the media controls: it is
    /// not a call control, and the bar is draggable, so a chat toggle inside
    /// it moves around unpredictably.
    private var chatButton: some View {
        CircleButton(system: chatShown ? "bubble.left.fill" : "bubble.left",
                     help: chatShown ? "Hide chat" : "Show chat",
                     active: chatShown) {
            chatShown.toggle()
        }
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    /// Annotation tools, only while there is a share to annotate.
    @ViewBuilder private var markToolbar: some View {
        if controller?.activeScreenShareID != nil {
            MarkToolbar(tool: $markTool) { controller?.markStore.clearAll() }
                .padding(.leading, 16)
        }
    }

    /// Stable per person, so a mark's colour identifies who drew it.
    private var markColorIndex: Int {
        abs(identity.hashValue) % 4
    }

    /// Connected, but nobody else is here yet.
    @ViewBuilder private var emptyRoomOverlay: some View {
        if let controller, controller.state == .connected,
           controller.remoteParticipants.isEmpty, !controller.isSharingScreen {
            EmptyRoomView(topic: topic, cameraOn: cameraOn)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
        }
    }

    private func join() async {
        let c = controller ?? RoomController(settings: settings)
        controller = c
        if compositor == nil {
            compositor = MetalCompositor(store: c.frameStore, markStore: c.markStore)
        }
        if chat == nil, let url = URL(string: settings.unbluBaseURL) {
            chat = ChatService(
                client: UnbluClient(baseURL: url,
                                    username: settings.unbluUsername,
                                    password: settings.unbluPassword),
                conversationId: conversationId,
                botPersonId: identity)
        }
        if cameraDeviceID.isEmpty {
            cameraDeviceID = CameraCapture.availableDevices().first?.uniqueID ?? ""
        }
        await c.connect(roomName: conversationId, identity: identity)

        // Only after connecting: the audio device module enumerates nothing
        // until it is running, so reading the active device before this point
        // returned an empty id and left both pickers blank.
        syncAudioSelections()

        // Must be the session identity, not the bare person id:
        // CameraPublisher files frames under the suffixed identity, and a
        // mismatch here means the compositor looks up a key nothing ever
        // writes — no preview.
        presenterOverlay = settings.presenterOverlay
        c.setPresenterOverlay(presenterOverlay)
        refreshLocalPreview()

        await c.setMicrophone(micOn)
    }

    private func startShare(_ target: ShareTarget) {
        Task {
            do { try await controller?.startScreenShare(target: target) }
            catch { shareError = "\(error)" }
        }
    }

    private func selectRegion(of target: ShareTarget) {
        guard let displayID = target.displayID else { return }
        Task {
            guard let region = await RegionSelector.selectRegion(displayID: displayID) else {
                // Cancelled: back to the picker rather than to nothing.
                showSharePicker = true
                shareCatalog.load()
                return
            }
            var regional = target
            regional.region = region
            startShare(regional)
        }
    }

    /// Points the pickers at whatever audio is actually in use.
    private func syncAudioSelections() {
        let inputs = AudioDevices.entries(
            from: AudioManager.shared.inputDevices.map { (id: $0.deviceId, name: $0.name) })
        let outputs = AudioDevices.entries(
            from: AudioManager.shared.outputDevices.map { (id: $0.deviceId, name: $0.name) })
        audioInputID = AudioDevices.resolvedSelection(
            current: audioInputID,
            activeID: AudioManager.shared.inputDevice.deviceId,
            entries: inputs)
        audioOutputID = AudioDevices.resolvedSelection(
            current: audioOutputID,
            activeID: AudioManager.shared.outputDevice.deviceId,
            entries: outputs)
    }

    /// One recogniser serves both features.
    private func syncRecognition() async {
        captions.transcript = summary.transcript
        captions.room = controller?.room
        if captionsOn || summaryShown {
            await captions.start()
        } else {
            captions.stop()
        }
    }

    /// No corner preview while the presenter is drawn onto their own share —
    /// they are already on screen, larger.
    private func refreshLocalPreview() {
        guard let controller else { return }
        compositor?.setLocalPreview(
            participantID: controller.isPresenterOverlayActive ? nil : controller.localIdentity)
    }

    private func leave() async {
        summary.stop()
        captions.stop()
        micLevels.stop()
        await controller?.disconnect()
        onLeave()
    }

    private func policy(for controller: RoomController) -> SubscriptionPolicy {
        if let subscriptionPolicy { return subscriptionPolicy }
        let created = SubscriptionPolicy(controller: controller)
        subscriptionPolicy = created
        return created
    }

    /// Remote participants only.
    private func tiles(for controller: RoomController) -> [Tile] {
        var ids = TileOrder.apply(tileOrder, to: controller.allTileKeys())
        if let active = controller.activeScreenShareID, !ids.contains(active) {
            ids.insert(active, at: 0)
        }
        // Speaker mode follows the talker; pinned mode follows the pin.
        let focus = layoutMode == .speaker ? (speakerFocusID ?? focusID) : focusID
        return TileLayout.layout(mode: layoutMode, participantIDs: ids,
                                 focusID: focus, aspect: 16.0 / 9.0,
                                 page: page, stripOffset: stripOffset)
    }

    /// Trackpad deltas are small and continuous; accumulate them so one
    /// thumbnail moves per notch rather than the strip flying past.
    private func scrollStrip(_ delta: CGFloat, controller: RoomController) {
        stripScrollAccumulator += delta
        let step: CGFloat = 12
        guard abs(stripScrollAccumulator) >= step else { return }
        let direction = stripScrollAccumulator > 0 ? -1 : 1
        stripScrollAccumulator = 0
        let maxOffset = TileLayout.maxStripOffset(
            participantCount: controller.remoteParticipants.count)
        stripOffset = min(max(stripOffset + direction, 0), maxOffset)
    }

    /// Pinned mode shows nothing when its focus is unavailable, which reads
    /// as a black screen.
    @discardableResult
    private func recoverIfPinnedTileVanished(_ tiles: [Tile]) -> Bool {
        guard layoutMode == .pinned, tiles.isEmpty, focusID != nil else { return false }
        Task { @MainActor in
            layoutMode = .grid
            focusID = nil
        }
        return true
    }

    /// Double-clicking a tile pins it; double-clicking the pinned one returns
    /// to the grid.
    private func togglePin(_ participantID: String) {
        if layoutMode == .pinned, focusID == participantID {
            layoutMode = .grid
            focusID = nil
        } else {
            focusID = participantID
            layoutMode = .pinned
        }
    }
}
