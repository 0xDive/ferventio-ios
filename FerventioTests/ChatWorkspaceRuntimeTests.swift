import Foundation
import Testing
@testable import Ferventio

@MainActor
struct ChatWorkspaceRuntimeTests {
    @Test
    func sameWorkspaceReturnsStableRuntimeAndPreservesStoreState() {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let workspace = ChatWorkspace(id: UUID(), login: "channel")

        let first = pool.runtime(for: workspace)
        first.chatStore.composerText = "draft in memory"
        let second = pool.runtime(for: workspace)

        #expect(first === second)
        #expect(second.chatStore.composerText == "draft in memory")
        #expect(factory.createdWorkspaceIDs == [workspace.id])
    }

    @Test
    func differentWorkspacesOwnIndependentChatState() {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let firstWorkspace = ChatWorkspace(id: UUID(), login: "one")
        let secondWorkspace = ChatWorkspace(id: UUID(), login: "two")

        let first = pool.runtime(for: firstWorkspace)
        let second = pool.runtime(for: secondWorkspace)
        first.chatStore.composerText = "only first"

        #expect(first !== second)
        #expect(first.chatStore !== second.chatStore)
        #expect(first.chatAssetStore !== second.chatAssetStore)
        #expect(first.chatHistoryPager !== second.chatHistoryPager)
        #expect(first.chatComposerStore !== second.chatComposerStore)
        #expect(second.chatStore.composerText.isEmpty)
        #expect(first.chatStore.channelInput == "one")
        #expect(second.chatStore.channelInput == "two")
    }

    @Test
    func preloadCreatesEachPersistedRuntimeWithoutDuplicatingExistingOne() {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let workspaces = [
            ChatWorkspace(id: UUID(), login: "one"),
            ChatWorkspace(id: UUID(), login: "two"),
            ChatWorkspace(id: UUID(), login: "three"),
        ]

        _ = pool.runtime(for: workspaces[1])
        pool.preload(workspaces)

        #expect(pool.runtimeCount == 3)
        #expect(Set(factory.createdWorkspaceIDs) == Set(workspaces.map(\.id)))
        #expect(factory.createdWorkspaceIDs.count == 3)
    }

    @Test
    func removeDestroysOnlyRequestedRuntime() async {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let firstWorkspace = ChatWorkspace(id: UUID(), login: "one")
        let secondWorkspace = ChatWorkspace(id: UUID(), login: "two")
        let first = pool.runtime(for: firstWorkspace)
        let second = pool.runtime(for: secondWorkspace)

        await pool.remove(id: firstWorkspace.id)

        #expect(pool.existingRuntime(id: firstWorkspace.id) == nil)
        #expect(pool.existingRuntime(id: secondWorkspace.id) === second)
        #expect(pool.runtimeCount == 1)
        #expect(first.chatStore.connectionState == .disconnected)
    }
}

@MainActor
private final class RuntimeFactory {
    private(set) var createdWorkspaceIDs: [UUID] = []

    func make(
        workspace: ChatWorkspace,
        preferences: ChatHistoryPreferences
    ) -> ChatWorkspaceRuntime {
        createdWorkspaceIDs.append(workspace.id)
        let history = NoopChatHistory()
        return ChatWorkspaceRuntime(
            workspace: workspace,
            chatStore: ChatStore(
                history: history,
                historyPreferences: preferences
            ),
            chatAssetStore: ChatAssetStore(),
            chatHistoryPager: ChatHistoryPager(
                history: history,
                preferences: preferences
            ),
            chatComposerStore: ChatComposerStore(),
            interactiveMutationStore: InteractiveChatMutationStore()
        )
    }
}
