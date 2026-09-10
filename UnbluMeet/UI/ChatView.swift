import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatView: View {
    let chat: ChatService
    let ownPersonId: String
    let width: CGFloat

    @State private var draft = ""
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chat.messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if let error = chat.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }

            HStack(spacing: 6) {
                Button { chooseFile() } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.plain)
                .help("Attach a file")

                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendDraft)
                Button("Send", action: sendDraft).disabled(draft.isEmpty)
            }
            .padding(8)
        }
        .frame(width: width)
        .task { chat.startPolling() }
        .onDisappear { chat.stopPolling() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(4)
            }
        }
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            handleDrop(providers)
        }
    }

    /// Own messages say "You"; everyone else uses the name ChatService
    /// resolved, falling back to the raw id until it arrives.
    @ViewBuilder
    private func attachmentView(_ attachment: ChatService.Attachment) -> some View {
        if attachment.isImage, let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 220, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { open(attachment) }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                Text(attachment.fileName).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            .onTapGesture { open(attachment) }
        }
    }

    /// Writes to a temp file and hands it to the system, so a click opens the
    /// attachment in whatever app owns that type.
    private func open(_ attachment: ChatService.Attachment) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(attachment.fileName)
        try? attachment.data.write(to: url)
        NSWorkspace.shared.open(url)
    }

    private func senderName(for message: MessageData, isOwn: Bool) -> String {
        if isOwn { return "You" }
        guard let sender = message.senderPersonId else { return "System" }
        return chat.senderNames[sender] ?? sender
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        send(fileAt: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in send(fileAt: url) }
            }
            return true
        }

        // A pasted screenshot arrives as raw image data with no file name.
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    let caption = draft
                    draft = ""
                    await chat.sendFile(named: "pasted-image.png", mimeType: "image/png",
                                        data: data, caption: caption)
                }
            }
            return true
        }
        return false
    }

    private func send(fileAt url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        let caption = draft
        draft = ""
        Task {
            await chat.sendFile(named: url.lastPathComponent,
                                mimeType: ChatService.mimeType(forFileNamed: url.lastPathComponent),
                                data: data,
                                caption: caption)
        }
    }

    private func sendDraft() {
        let text = draft
        guard !text.isEmpty else { return }
        draft = ""
        Task { await chat.send(text) }
    }

    private func messageRow(_ message: MessageData) -> some View {
        let isOwn = message.senderPersonId == ownPersonId
        return VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
            Text(senderName(for: message, isOwn: isOwn))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let attachment = chat.attachments[message.id] {
                attachmentView(attachment)
            } else {
                Text(message.text ?? "")
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isOwn ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.2),
                                in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}
