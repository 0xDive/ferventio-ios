import Foundation
import FerventioDomain
import SwiftUI

struct ChatView: View {
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var store: ChatStore
    @Bindable var assets: ChatAssetStore
    @Bindable var historyPager: ChatHistoryPager
    let composerStore: ChatComposerStore
    let workspaceLogin: String?
    let repeatCollapseEnabled: Bool
    let presentationRules: [ChatPresentationRule]
    let canExecuteNuke: Bool
    let loadUserProfile: (ChatAuthor) async -> TwitchUser?
    let canTimeoutUser: (ChatAuthor) -> Bool
    let timeoutUser: (ChatAuthor) async throws -> NukeExecutionResult
    let executeNuke: (NukeExecutionPlan) async throws -> NukeExecutionResult
    let connect: () async -> Void

    @State private var hasPositionedInitialFeed = false
    @State private var feedScrollPosition: String?
    @State private var unreadLiveMessageCount = 0
    @State private var sheetRequest: ChatSheetRequest?

    private static let feedBottomID = "__ferventio_feed_bottom__"

    var body: some View {
        VStack(spacing: 0) {
            channelBar
            if currentPoll != nil || currentPrediction != nil {
                Divider()
                InteractiveChatOverlayView(
                    poll: currentPoll,
                    prediction: currentPrediction
                )
            }
            Divider()
            messageFeed
            Divider()
            composerBar
        }
        .onChange(of: store.channel?.id, initial: true) { _, channelID in
            historyPager.prepare(channelID: channelID)
            hasPositionedInitialFeed = false
            feedScrollPosition = Self.feedBottomID
            unreadLiveMessageCount = 0
            sheetRequest = nil
        }
        .task(id: store.channel?.id) {
            let channelID = store.channel?.id
            let draft = await composerStore.activate(channelID: channelID)
            guard !Task.isCancelled,
                  store.channel?.id == channelID else {
                return
            }
            if store.composerText != draft {
                store.composerText = draft
            }
        }
        .onChange(of: store.composerText, initial: true) { _, text in
            composerStore.updateDraft(channelID: store.channel?.id, text: text)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else {
                return
            }
            Task { await composerStore.flush() }
        }
        .onDisappear {
            Task { await composerStore.flush() }
        }
        .sheet(item: $sheetRequest) { request in
            switch request.content {
            case let .nuke(query):
                NukePreviewView(
                    messages: canonicalDisplayedMessages,
                    initialQuery: query,
                    canExecute: canExecuteNuke,
                    execute: executeNuke
                )
            case let .user(author):
                UserCardView(
                    author: author,
                    messages: canonicalDisplayedMessages,
                    canTimeout: canTimeoutUser(author),
                    loadProfile: {
                        await loadUserProfile(author)
                    },
                    timeoutUser: {
                        try await timeoutUser(author)
                    }
                )
            }
        }
        .alert(
            String(localized: "chat.error.title"),
            isPresented: $store.showsConnectionError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("auth.error.message")
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
            if let workspaceLogin {
                Label("#\(workspaceLogin)", systemImage: channelStatusSystemImage)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                TextField("chat.channel.placeholder", text: $store.channelInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        Task { await connect() }
                    }
            }

            Button {
                Task { await connect() }
            } label: {
                if store.connectionState == .connecting || store.connectionState == .reconnecting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
            }
            .accessibilityLabel(Text("chat.connect"))
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
        let canonicalMessages = canonicalDisplayedMessages
        let projection = ChatPresentationRuleEngine.project(
            messages: canonicalMessages,
            rules: presentationRules
        )
        let visibleMessages = projection.visibleMessages
        let groups = ChatRepeatCollapsePlanner.collapse(
            visibleMessages,
            config: ChatRepeatCollapseConfig(enabled: repeatCollapseEnabled)
        )

        if canonicalMessages.isEmpty {
            defaultEmptyFeed
        } else if visibleMessages.isEmpty {
            ContentUnavailableView(
                filtersLocalized("feed.empty.title"),
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(filtersLocalized("feed.empty.message"))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if historyPager.canLoadOlderHistory {
                            historyPagingSentinel(
                                proxy: proxy,
                                visibleMessages: visibleMessages
                            )
                        }

                        ForEach(groups) { group in
                            repeatGroup(
                                group,
                                highlightedMessageIDs: projection.highlightedMessageIDs
                            )
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.feedBottomID)
                            .accessibilityHidden(true)
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollPosition(id: $feedScrollPosition, anchor: .bottom)
                .overlay(alignment: .bottomTrailing) {
                    if hasPositionedInitialFeed,
                       feedScrollPosition != Self.feedBottomID {
                        Button {
                            proxy.scrollTo(Self.feedBottomID, anchor: .bottom)
                            feedScrollPosition = Self.feedBottomID
                            unreadLiveMessageCount = 0
                        } label: {
                            HStack(spacing: 6) {
                                Label("chat.jump_to_live", systemImage: "arrow.down.to.line")
                                if unreadLiveMessageCount > 0 {
                                    Text(unreadLiveMessageCount > 999 ? "999+" : "\(unreadLiveMessageCount)")
                                        .font(.caption2.weight(.bold))
                                        .monospacedDigit()
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityLabel(Text("chat.jump_to_live"))
                        .accessibilityValue(Text(unreadLiveMessagesAccessibilityValue))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(12)
                    }
                }
                .onChange(of: feedScrollPosition) { _, position in
                    if position == Self.feedBottomID {
                        unreadLiveMessageCount = 0
                    }
                }
                .onChange(of: visibleMessages.last?.id, initial: true) { previousID, messageID in
                    guard messageID != nil else { return }
                    let shouldFollowLive = !hasPositionedInitialFeed
                        || feedScrollPosition == Self.feedBottomID
                    unreadLiveMessageCount = ChatUnreadLiveCounter.updatedCount(
                        currentCount: unreadLiveMessageCount,
                        previousLastMessageID: previousID,
                        visibleMessages: visibleMessages,
                        isFollowingLive: shouldFollowLive
                    )
                    if shouldFollowLive {
                        proxy.scrollTo(Self.feedBottomID, anchor: .bottom)
                        feedScrollPosition = Self.feedBottomID
                    }
                    hasPositionedInitialFeed = true
                }
            }
        }
    }

    private var defaultEmptyFeed: some View {
        ContentUnavailableView(
            String(localized: emptyTitleKey),
            systemImage: emptySystemImage,
            description: Text(emptyMessageKey)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repeatGroup(
        _ group: ChatRepeatGroup,
        highlightedMessageIDs: Set<String>
    ) -> some View {
        let isHighlighted = group.messages.contains { message in
            highlightedMessageIDs.contains(message.id)
        }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(group.messages.dropFirst(), id: \.id) { message in
                Color.clear
                    .frame(height: 0)
                    .id(message.id)
            }

            ChatMessageRow(
                message: group.representative,
                badgeAssets: assets.badgeAssets,
                onOpenUserCard: {
                    sheetRequest = ChatSheetRequest(.user(group.representative.author))
                },
                onReply: {
                    store.beginReply(to: group.representative)
                },
                onPreviewNuke: {
                    sheetRequest = ChatSheetRequest(.nuke(group.representative.text))
                }
            )
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
            .padding(.horizontal, isHighlighted ? 7 : 0)
            .padding(.vertical, isHighlighted ? 5 : 0)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .overlay(alignment: .leading) {
                if isHighlighted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 5)
                }
            }
            .id(group.representative.id)
        }
    }

    @ViewBuilder
    private func historyPagingSentinel(
        proxy: ScrollViewProxy,
        visibleMessages: [ChatMessage]
    ) -> some View {
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

    private var canonicalDisplayedMessages: [ChatMessage] {
        historyPager.mergedMessages(with: store.messages)
    }

    private var currentPoll: PollOverlay? {
        guard let channelID = store.channel?.id else {
            return nil
        }
        return store.interactiveOverlayState.pollsByChannel[channelID]
    }

    private var currentPrediction: PredictionOverlay? {
        guard let channelID = store.channel?.id else {
            return nil
        }
        return store.interactiveOverlayState.predictionsByChannel[channelID]
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
                if !composerStore.sentHistory.isEmpty {
                    Menu {
                        ForEach(composerStore.sentHistory) { entry in
                            Button {
                                store.composerText = entry.text
                            } label: {
                                Text(entry.text)
                                    .lineLimit(2)
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .accessibilityLabel(Text("chat.sent_history"))
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.connectionState != .connected || store.isSending)
                }

                TextField("chat.composer.placeholder", text: $store.composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .disabled(store.connectionState != .connected)
                    .onSubmit {
                        Task { await sendCurrentMessage() }
                    }

                Button {
                    Task { await sendCurrentMessage() }
                } label: {
                    if store.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .accessibilityLabel(Text("chat.send"))
                .buttonStyle(.borderless)
                .disabled(!store.canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func sendCurrentMessage() async {
        guard store.canSend,
              let channelID = store.channel?.id else {
            return
        }
        let text = store.composerText

        let didSend = await store.sendCurrentMessage()

        guard didSend,
              store.channel?.id == channelID else {
            return
        }
        // Synchronize the actual composer contents before recording history.
        // The user may already have typed the next message while the send was in flight.
        composerStore.updateDraft(channelID: channelID, text: store.composerText)
        await composerStore.recordSuccessfulSend(channelID: channelID, text: text)
    }

    private var unreadLiveMessagesAccessibilityValue: String {
        guard unreadLiveMessageCount > 0 else {
            return ""
        }
        return String.localizedStringWithFormat(
            String(localized: "jump_to_live.unread_count", table: "ChatAccessibility"),
            unreadLiveMessageCount
        )
    }

    private var channelStatusSystemImage: String {
        switch store.connectionState {
        case .connected:
            "checkmark.circle.fill"
        case .connecting, .reconnecting:
            "antenna.radiowaves.left.and.right"
        case .suspended:
            "pause.circle"
        case .failed:
            "exclamationmark.circle"
        case .disconnected:
            "number"
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

    private func filtersLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ChatFilters")
    }
}

private struct ChatSheetRequest: Identifiable {
    enum Content {
        case nuke(String)
        case user(ChatAuthor)
    }

    let id = UUID()
    let content: Content

    init(_ content: Content) {
        self.content = content
    }
}