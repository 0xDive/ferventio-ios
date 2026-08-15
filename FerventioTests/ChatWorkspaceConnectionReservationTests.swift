import Foundation
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatWorkspaceConnectionReservationTests {
    @Test
    func connectedRuntimeAllowsOnlyOneReconnectAttemptAtATime() {
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: makeRuntime
        )
        let workspace = ChatWorkspace(id: UUID(), login: "channel")
        let runtime = pool.runtime(for: workspace)
        runtime.chatStore.apply(.reconnected(sessionID: "session"))

        #expect(runtime.chatStore.connectionState == .connected)
        #expect(pool.occupiedConnectionSlotCount == 1)
        #expect(pool.beginConnection(for: runtime))
        #expect(pool.occupiedConnectionSlotCount == 1)
        #expect(!pool.beginConnection(for: runtime))

        pool.finishConnectionAttempt(for: runtime)

        #expect(pool.beginConnection(for: runtime))
        #expect(pool.occupiedConnectionSlotCount == 1)
    }

    @Test
    func reconnectReservationDoesNotConsumeAnExtraLiveSlot() {
        let pool = ChatWorkspaceRuntimePool(
            historyPreferences: .default,
            factory: makeRuntime
        )
        let connected = pool.runtime(
            for: ChatWorkspace(id: UUID(), login: "connected")
        )
        connected.chatStore.apply(.reconnected(sessionID: "session"))
        let second = pool.runtime(
            for: ChatWorkspace(id: UUID(), login: "second")
        )
        let third = pool.runtime(
            for: ChatWorkspace(id: UUID(), login: "third")
        )

        #expect(pool.beginConnection(for: connected))
        #expect(pool.occupiedConnectionSlotCount == 1)
        #expect(pool.beginConnection(for: second))
        #expect(pool.beginConnection(for: third))
        #expect(pool.occupiedConnectionSlotCount == ChatWorkspaceRuntimePool.maximumLiveConnections)
    }

    private func makeRuntime(
        workspace: ChatWorkspace,
        preferences: ChatHistoryPreferences
    ) -> ChatWorkspaceRuntime {
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
