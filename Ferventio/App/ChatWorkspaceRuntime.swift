import Foundation

@MainActor
final class ChatWorkspaceRuntime: Identifiable {
    let id: UUID
    private(set) var workspace: ChatWorkspace
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
        guard workspace.id == id else {
            return
        }
        self.workspace = workspace
    }
}

@MainActor
final class ChatWorkspaceRuntimePool {
    typealias Factory = @MainActor (ChatWorkspace, ChatHistoryPreferences) -> ChatWorkspaceRuntime

    private var runtimes: [UUID: ChatWorkspaceRuntime] = [:]
    private var historyPreferences: ChatHistoryPreferences
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

    func runtime(for workspace: ChatWorkspace) -> ChatWorkspaceRuntime {
        if let existing = runtimes[workspace.id] {
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
        runtimes[id]
    }

    func remove(id: UUID) async {
        guard let runtime = runtimes.removeValue(forKey: id) else {
            return
        }
        await runtime.chatComposerStore.flush()
        await runtime.chatStore.disconnect()
        runtime.chatHistoryPager.reset(channelID: nil)
        runtime.chatAssetStore.reset()
        runtime.interactiveMutationStore.clear()
    }

    func updateHistoryPreferences(_ preferences: ChatHistoryPreferences) async {
        historyPreferences = preferences
        for runtime in runtimes.values {
            await runtime.chatStore.updateHistoryPreferences(preferences)
            runtime.chatHistoryPager.updatePreferences(preferences)
        }
    }

    func suspendAll() async {
        for runtime in runtimes.values {
            await runtime.chatComposerStore.flush()
            await runtime.chatStore.suspend()
        }
    }

    func resumeAll() async {
        for runtime in runtimes.values {
            await runtime.chatStore.resumeIfNeeded()
        }
    }

    func disconnectAll() async {
        for runtime in runtimes.values {
            await runtime.chatComposerStore.flush()
            await runtime.chatStore.disconnect()
            runtime.chatHistoryPager.reset(channelID: nil)
            runtime.chatAssetStore.reset()
            runtime.interactiveMutationStore.clear()
        }
    }
}
