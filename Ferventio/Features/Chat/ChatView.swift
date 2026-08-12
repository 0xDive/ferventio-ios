import FerventioDomain
import SwiftUI

struct ChatView: View {
    @Bindable var store: ChatStore
    @Bindable var assets: ChatAssetStore
    @Bindable var historyPager: ChatHistoryPager
    let connect: () async -> Void

    @State private var hasPositionedInitialFeed = false

    var body: some View {
        VStack(spacing: 0) {
            channelBar
            Divider()
            messageFeed
            Divider()
            composerBar
        }
        .onChange(of: store.channel?.id, initial: true) { _, channelID in
            historyPager.reset(channelID: channelID)
            hasPositionedInitialFeed = false
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
        if displayedMessages.isEmpty {
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
                        if historyPager.canLoadOlderHistory {
                            historyPagingSentinel(proxy: proxy)
                        }

                        ForEach(displayedGroups) { group in
                            repeatGroup(group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: displayedMessages.last?.id, initial: true) { _, messageID in
                    guard let messageID else { return }
                    proxy.scrollTo(messageID, anchor: .bottom)
                    hasPositionedInitialFeed = true
                }
            }
        }
    }

    private func repeatGroup(_ group: ChatRepeatGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(group.messages.dropLast(), id: \.id) { message in
                Color.clear
                    .frame(height: 0)
                    .id(message.id)
            }

            ChatMessageRow(
                message: group.representative,
                badgeAssets: assets.badgeAssets
            ) {
                store.beginReply(to: group.representative)
            }
            .overlay(alignment: .topTrailing) {
                if group.repeatCount > 1 {
                    Text("×\(group.repeatCount)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel(Text("×\(group.repeatCount)"))
                }
            }
            .id(group.representative.id)
        }
    }

    @ViewBuilder
    private func historyPagingSentinel(proxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer(minLength: 0)
            if historyPager.isLoadingOlderHistory {
                ProgressView()
                    .controlSize(.small)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .onAppear {
            guard hasPositionedInitialFeed else {
                return
            }
            Task {
                let visibleMessages = displayedMessages
                let anchorID = await historyPager.loadOlderHistory(
                    before: visibleMessages.first,
                    excluding: Set(store.messages.map(\.id))
                )
                guard let anchorID else {
                    return
                }
                await Task.yield()
                proxy.scrollTo(anchorID, anchor: .top)
            }
        }
    }

    private var displayedMessages: [ChatMessage] {
        historyPager.mergedMessages(with: store.messages)
    }

    private var displayedGroups: [ChatRepeatGroup] {
        ChatRepeatCollapsePlanner.collapse(displayedMessages)
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
