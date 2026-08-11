import FerventioDomain
import SwiftUI

struct ChatView: View {
    @Bindable var store: ChatStore
    let connect: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            channelBar
            Divider()
            messageFeed
        }
        .alert(
            String(localized: "chat.error.title"),
            isPresented: $store.showsConnectionError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("chat.error.message")
        }
    }

    private var channelBar: some View {
        HStack(spacing: 10) {
            TextField("chat.channel.placeholder", text: $store.channelInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    Task { await connect() }
                }

            Button {
                Task { await connect() }
            } label: {
                if store.connectionState == .connecting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .accessibilityLabel(Text("chat.connect"))
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.connectionState == .connecting)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var messageFeed: some View {
        if store.messages.isEmpty {
            ContentUnavailableView(
                String(localized: emptyTitleKey),
                systemImage: emptySystemImage,
                description: Text(emptyMessageKey)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: store.messages.last?.id) { _, messageID in
                    guard let messageID else { return }
                    proxy.scrollTo(messageID, anchor: .bottom)
                }
            }
        }
    }

    private var emptyTitleKey: String.LocalizationValue {
        switch store.connectionState {
        case .disconnected:
            "chat.empty.disconnected.title"
        case .connecting, .reconnecting:
            "chat.empty.connecting.title"
        case .connected:
            "chat.empty.connected.title"
        case .failed:
            "chat.empty.failed.title"
        }
    }

    private var emptyMessageKey: LocalizedStringKey {
        switch store.connectionState {
        case .disconnected:
            "chat.empty.disconnected.message"
        case .connecting, .reconnecting:
            "chat.empty.connecting.message"
        case .connected:
            "chat.empty.connected.message"
        case .failed:
            "chat.empty.failed.message"
        }
    }

    private var emptySystemImage: String {
        switch store.connectionState {
        case .failed:
            "wifi.exclamationmark"
        case .connecting, .reconnecting:
            "antenna.radiowaves.left.and.right"
        case .disconnected, .connected:
            "bubble.left.and.bubble.right"
        }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let reply = message.reply,
               let parentName = reply.parentUserName ?? reply.parentUserLogin {
                Text("↪ \(parentName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
