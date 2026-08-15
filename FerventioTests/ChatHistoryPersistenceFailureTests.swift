import FerventioDomain
import FerventioPersistence
import Testing
@testable import Ferventio

struct ChatHistoryPersistenceFailureTests {
    @Test
    func failedBatchRemainsPendingForNextFlush() async throws {
        let store = try PersistenceStore.inMemory()
        let saver = FailFirstHistorySaver(store: store)
        let history = PersistenceChatHistory(
            store: store,
            saveBatch: { messages in
                try await saver.save(messages)
            },
            automaticFlushDelay: .seconds(3_600)
        )
        let message = makeMessage(text: "Persist me")

        await history.enqueue(message)
        await history.flush()

        #expect(try await store.recentMessages(channelID: "channel", limit: 10).isEmpty)

        await history.flush()

        #expect(try await store.recentMessages(channelID: "channel", limit: 10) == [message])
        #expect(await saver.attemptCount() == 2)
    }

    @Test
    func successfulStaleBatchDoesNotRemoveNewerPendingMessage() async throws {
        let store = try PersistenceStore.inMemory()
        let saver = BlockingFirstHistorySaver(store: store)
        let history = PersistenceChatHistory(
            store: store,
            saveBatch: { messages in
                try await saver.save(messages)
            },
            automaticFlushDelay: .seconds(3_600)
        )
        let original = makeMessage(text: "Original")
        let updated = makeMessage(text: "Updated")

        await history.enqueue(original)
        let firstFlush = Task {
            await history.flush()
        }
        await saver.waitUntilFirstSaveStarts()

        await history.enqueue(updated)
        await saver.releaseFirstSave()
        await firstFlush.value

        await history.flush()

        let persisted = try await store.recentMessages(channelID: "channel", limit: 10)
        #expect(persisted == [updated])
        #expect(await saver.attemptCount() == 2)
    }

    private func makeMessage(text: String) -> ChatMessage {
        ChatMessage(
            id: "message",
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: "viewer",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: text,
            timestamp: "2026-08-15T19:00:00Z",
            timestampMilliseconds: 1
        )
    }
}

private actor FailFirstHistorySaver {
    enum Failure: Swift.Error {
        case injected
    }

    private let store: PersistenceStore
    private var attempts = 0

    init(store: PersistenceStore) {
        self.store = store
    }

    func save(_ messages: [ChatMessage]) async throws {
        attempts += 1
        if attempts == 1 {
            throw Failure.injected
        }
        try await store.save(messages)
    }

    func attemptCount() -> Int {
        attempts
    }
}

private actor BlockingFirstHistorySaver {
    private let store: PersistenceStore
    private var attempts = 0
    private var firstSaveStarted = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(store: PersistenceStore) {
        self.store = store
    }

    func save(_ messages: [ChatMessage]) async throws {
        attempts += 1
        if attempts == 1 {
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
                firstSaveStarted = true
                let waiters = firstSaveWaiters
                firstSaveWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }
        try await store.save(messages)
    }

    func waitUntilFirstSaveStarts() async {
        guard !firstSaveStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstSaveWaiters.append(continuation)
        }
    }

    func releaseFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }

    func attemptCount() -> Int {
        attempts
    }
}
