import Foundation

@MainActor
final class ChatWorkspaceRuntime: Identifiable {
    let id: UUID
    private(set) var workspace: ChatWorkspace
    private(set) var isClosed = false
    let chatStore: ChatStore
    let chatAssetStore: ChatAssetStore
    let chatHistoryPager: ChatHistoryPager
    let chatComposerStore: ChatComposerStore
    let interactiveMutationStore: InteractiveChatMutationStore

    init(
        workspace: ChatWorkspace,
        chatStore: ChatStore,
        chatAssetStore: ChatAssetStore,
        chatHistoryPager: ChatHistoryPager,
        chatComposerStore: ChatComposerStore,
        interactiveMutationStore: InteractiveChatMutationStore
    ) {
        id = workspace.id
        self.workspace = workspace
        self.chatStore = chatStore
        self.chatAssetStore = chatAssetStore
        self.chatHistoryPager = chatHistoryPager
        self.chatComposerStore = chatComposerStore
        self.interactiveMutationStore = interactiveMutationStore
        if chatStore.channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatStore.channelInput = workspace.login
        }
    }

    static func live(
        workspace: ChatWorkspace,
        historyPreferences: ChatHistoryPreferences
    ) -> ChatWorkspaceRuntime {
        let history = ChatHistoryFactory.live()
        let chatStore = ChatStore(
            history: history,
            recentMessagesLoader: RecentMessagesLoaderFactory.live(),
            historyPreferences: historyPreferences
        )
        return ChatWorkspaceRuntime(
            workspace: workspace,
            chatStore: chatStore,
            chatAssetStore: ChatAssetStore(),
            chatHistoryPager: ChatHistoryPager(
                history: history,
                preferences: historyPreferences
            ),
            chatComposerStore: ChatComposerStore.live(),
            interactiveMutationStore: InteractiveChatMutationStore()
        )
    }

    func updateWorkspace(_ workspace: ChatWorkspace) {
        guard workspace.id == id, !isClosed else {
            return
        }
        self.workspace = workspace
    }

    func close() async {
        guard !isClosed else {
            return
        }
        isClosed = true
        await chatComposerStore.flush()
        await chatStore.disconnect()
        chatHistoryPager.reset(channelID: nil)
        chatAssetStore.reset()
        interactiveMutationStore.clear()
    }
}

@MainActor
final class ChatWorkspaceRuntimePool {
    typealias Factory = @MainActor (ChatWorkspace, ChatHistoryPreferences) -> ChatWorkspaceRuntime

    // Twitch currently allows at most three EventSub WebSocket connections with
    // enabled subscriptions for a user-token/client-ID tuple. Keep navigation
    // capacity separate so additional tabs may remain persisted but offline.
    static let maximumLiveConnections = 3

    private var runtimes: [UUID: ChatWorkspaceRuntime] = [:]
    private var connectionReservations: Set<UUID> = []
    private var historyPreferences: ChatHistoryPreferences
    private var wantsSuspended = false
    private let factory: Factory

    init(
        historyPreferences: ChatHistoryPreferences,
        factory: @escaping Factory = { workspace, preferences in
            ChatWorkspaceRuntime.live(
                workspace: workspace,
                historyPreferences: preferences
            )
        }
    ) {
        self.historyPreferences = historyPreferences
        self.factory = factory
    }

    var runtimeCount: Int {
        runtimes.count
    }

    var liveConnectionCount: Int {
        runtimes.values.reduce(into: 0) { count, runtime in
            if Self.reservesLiveConnection(runtime.chatStore.connectionState) {
                count += 1
            }
        }
    }

    var occupiedConnectionSlotCount: Int {
        var occupiedIDs = connectionReservations
        for (id, runtime) in runtimes
        where Self.reservesLiveConnection(runtime.chatStore.connectionState) {
            occupiedIDs.insert(id)
        }
        return occupiedIDs.count
    }

    func runtime(for workspace: ChatWorkspace) -> ChatWorkspaceRuntime {
        if let existing = runtimes[workspace.id], !existing.isClosed {
            existing.updateWorkspace(workspace)
            return existing
        }
        let runtime = factory(workspace, historyPreferences)
        runtimes[workspace.id] = runtime
        return runtime
    }

    func preload(_ workspaces: [ChatWorkspace]) {
        for workspace in workspaces {
            _ = runtime(for: workspace)
        }
    }

    func existingRuntime(id: UUID) -> ChatWorkspaceRuntime? {
        guard let runtime = runtimes[id], !runtime.isClosed else {
            return nil
        }
        return runtime
    }

    func beginConnection(for runtime: ChatWorkspaceRuntime) -> Bool {
        guard !runtime.isClosed,
              let pooledRuntime = runtimes[runtime.id],
              pooledRuntime === runtime,
              !connectionReservations.contains(runtime.id) else {
            return false
        }
        if !Self.reservesLiveConnection(runtime.chatStore.connectionState) {
            guard occupiedConnectionSlotCount < Self.maximumLiveConnections else {
                return false
            }
        }
        connectionReservations.insert(runtime.id)
        return true
    }

    func finishConnectionAttempt(for runtime: ChatWorkspaceRuntime) {
        connectionReservations.remove(runtime.id)
    }

    func remove(id: UUID) async {
        connectionReservations.remove(id)
        guard let runtime = runtimes.removeValue(forKey: id) else {
            return
        }
        await runtime.close()
    }

    func removeAll() async {
        for id in Array(runtimes.keys) {
            await remove(id: id)
        }
        connectionReservations.removeAll(keepingCapacity: false)
    }

    func updateHistoryPreferences(_ preferences: ChatHistoryPreferences) async {
        historyPreferences = preferences
        for runtime in runtimes.values where !runtime.isClosed {
            await runtime.chatStore.updateHistoryPreferences(preferences)
            runtime.chatHistoryPager.updatePreferences(preferences)
        }
    }

    func suspendAll() async {
        wantsSuspended = true
        for runtime in runtimes.values where !runtime.isClosed {
            await runtime.chatComposerStore.flush()
            guard wantsSuspended else {
                return
            }
            await runtime.chatStore.suspend()
            guard wantsSuspended else {
                await runtime.chatStore.resumeIfNeeded()
                return
            }
        }
    }

    func resumeAll() async {
        wantsSuspended = false
        for runtime in runtimes.values where !runtime.isClosed {
            await runtime.chatStore.resumeIfNeeded()
            guard !wantsSuspended else {
                return
            }
        }
    }

    func disconnectAll() async {
        connectionReservations.removeAll(keepingCapacity: false)
        for runtime in runtimes.values where !runtime.isClosed {
            await runtime.chatComposerStore.flush()
            await runtime.chatStore.disconnect()
            runtime.chatHistoryPager.reset(channelID: nil)
            runtime.chatAssetStore.reset()
            runtime.interactiveMutationStore.clear()
        }
    }

    static func reservesLiveConnection(_ state: ChatStore.ConnectionState) -> Bool {
        switch state {
        case .connecting, .connected, .reconnecting, .suspended:
            true
        case .disconnected, .failed:
            false
        }
    }
}
