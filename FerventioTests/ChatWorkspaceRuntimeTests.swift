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

        #expect(first.isClosed)
        #expect(pool.existingRuntime(id: firstWorkspace.id) == nil)
        #expect(pool.existingRuntime(id: secondWorkspace.id) === second)
        #expect(pool.runtimeCount == 1)
        #expect(first.chatStore.connectionState == .disconnected)
    }

    @Test
    func connectionReservationsAreAtomicAndBoundedToTwitchLimit() {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let runtimes = (1...4).map { index in
            pool.runtime(
                for: ChatWorkspace(id: UUID(), login: "channel\(index)")
            )
        }

        #expect(ChatWorkspaceRuntimePool.maximumLiveConnections == 3)
        #expect(pool.beginConnection(for: runtimes[0]))
        #expect(!pool.beginConnection(for: runtimes[0]))
        #expect(pool.beginConnection(for: runtimes[1]))
        #expect(pool.beginConnection(for: runtimes[2]))
        #expect(pool.occupiedConnectionSlotCount == 3)
        #expect(!pool.beginConnection(for: runtimes[3]))

        pool.finishConnectionAttempt(for: runtimes[0])

        #expect(pool.occupiedConnectionSlotCount == 2)
        #expect(pool.beginConnection(for: runtimes[3]))
        #expect(pool.occupiedConnectionSlotCount == 3)
    }

    @Test
    func removingReservedRuntimeReleasesSlotAndPreventsReuse() async {
        let factory = RuntimeFactory()
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: factory.make
        )
        let workspace = ChatWorkspace(id: UUID(), login: "channel")
        let runtime = pool.runtime(for: workspace)

        #expect(pool.beginConnection(for: runtime))
        #expect(pool.occupiedConnectionSlotCount == 1)

        await pool.remove(id: workspace.id)

        #expect(runtime.isClosed)
        #expect(pool.occupiedConnectionSlotCount == 0)
        #expect(!pool.beginConnection(for: runtime))

        let replacement = pool.runtime(for: workspace)
        #expect(replacement !== runtime)
        #expect(pool.beginConnection(for: replacement))
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
