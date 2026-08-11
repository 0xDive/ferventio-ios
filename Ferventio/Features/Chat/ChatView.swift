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
            Divider()
            composerBar
        }
        .alert(
            String(localized: "chat.error.title"),
            isPresented: $store.showsConnectionError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("chat.error.message")
        }
        .alert(
            String(localized: "chat.send.error.title"),
            isPresented: $store.showsSendError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("chat.send.error.message")
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
                if store.connectionState == .connecting || store.connectionState == .reconnecting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .accessibilityLabel(Text("chat.connect"))
                }
            }
            .buttonStyle(.borderless)
            .disabled(
                store.connectionState == .connecting
                    || store.connectionState == .reconnecting
                    || store.connectionState == .suspended
            )
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
                            ChatMessageRow(message: message) {
                                store.beginReply(to: message)
                            }
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

    private var composerBar: some View {
        VStack(spacing: 0) {
            if let replyTarget = store.replyTarget {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .foregroundStyle(.secondary)
                    Text(replyTarget.author.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(replyTarget.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        store.cancelReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .accessibilityLabel(Text("chat.reply.cancel"))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("chat.composer.placeholder", text: $store.composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .disabled(store.connectionState != .connected)
                    .onSubmit {
                        Task { await store.sendCurrentMessage() }
                    }

                Button {
                    Task { await store.sendCurrentMessage() }
                } label: {
                    if store.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .accessibilityLabel(Text("chat.send"))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!store.canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var emptyTitleKey: String.LocalizationValue {
        switch store.connectionState {
        case .disconnected:
            "chat.empty.disconnected.title"
        case .connecting, .reconnecting, .suspended:
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
        case .connecting, .reconnecting, .suspended:
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
        case .suspended:
            "pause.circle"
        case .disconnected, .connected:
            "bubble.left.and.bubble.right"
        }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let onReply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
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

            Spacer(minLength: 4)

            switch message.outgoingState {
            case .sending:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(Text("chat.message.sending"))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("chat.message.failed"))
            case .none, .sent:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                onReply()
            } label: {
                Label("chat.reply", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(message.outgoingState == .sending || message.outgoingState == .failed)
        }
    }
}
