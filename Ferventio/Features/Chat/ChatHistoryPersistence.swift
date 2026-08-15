import Foundation
import FerventioDomain
import FerventioPersistence

protocol ChatHistoryPersisting: Sendable {
    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage]
    func olderMessages(
        channelID: String,
        before cursor: ChatHistoryCursor,
        limit: Int
    ) async -> [ChatMessage]
    func enqueue(_ message: ChatMessage) async
    func maintain(
        channelID: String,
        retentionBoundaryMilliseconds: Int64?,
        keepingLatest: Int,
        maxDatabaseSizeMB: Int
    ) async
    func flush() async
}

extension ChatHistoryPersisting {
    func olderMessages(
        channelID: String,
        before cursor: ChatHistoryCursor,
        limit: Int
    ) async -> [ChatMessage] {
        []
    }
}

actor PersistenceChatHistory: ChatHistoryPersisting {
    typealias SaveBatch = @Sendable ([ChatMessage]) async throws -> Void

    static let flushDelay = Duration.milliseconds(250)

    private struct PendingMessage: Sendable {
        let message: ChatMessage
        let revision: UInt64
    }

    private let store: PersistenceStore
    private let saveBatch: SaveBatch
    private let automaticFlushDelay: Duration
    private var pendingMessages: [String: PendingMessage] = [:]
    private var nextRevision: UInt64 = 0
    private var flushTask: Task<Void, Never>?

    init(
        store: PersistenceStore,
        saveBatch: SaveBatch? = nil,
        automaticFlushDelay: Duration = PersistenceChatHistory.flushDelay
    ) {
        self.store = store
        self.automaticFlushDelay = automaticFlushDelay
        self.saveBatch = saveBatch ?? { messages in
            try await store.save(messages)
        }
    }

    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage] {
        (try? await store.recentMessages(channelID: channelID, limit: limit)) ?? []
    }

    func olderMessages(
        channelID: String,
        before cursor: ChatHistoryCursor,
        limit: Int
    ) async -> [ChatMessage] {
        (try? await store.recentMessages(
            channelID: channelID,
            limit: limit,
            before: cursor
        )) ?? []
    }

    func enqueue(_ message: ChatMessage) async {
        nextRevision &+= 1
        pendingMessages[Self.key(for: message)] = PendingMessage(
            message: message,
            revision: nextRevision
        )
        guard flushTask == nil else {
            return
        }
        flushTask = Task {
            try? await Task.sleep(for: automaticFlushDelay)
            guard !Task.isCancelled else {
                return
            }
            await self.flush()
        }
    }

    func maintain(
        channelID: String,
        retentionBoundaryMilliseconds: Int64?,
        keepingLatest: Int,
        maxDatabaseSizeMB: Int
    ) async {
        if let retentionBoundaryMilliseconds {
            _ = try? await store.prune(
                olderThanTimestampMilliseconds: retentionBoundaryMilliseconds
            )
        }
        _ = try? await store.trim(
            channelID: channelID,
            keepingLatest: keepingLatest
        )
        if maxDatabaseSizeMB > 0 {
            _ = try? await store.enforceMaximumSize(megabytes: maxDatabaseSizeMB)
        }
    }

    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingMessages.isEmpty else {
            return
        }

        let batch = pendingMessages
        do {
            try await saveBatch(batch.values.map(\.message))
            for (key, saved) in batch
            where pendingMessages[key]?.revision == saved.revision {
                pendingMessages.removeValue(forKey: key)
            }
        } catch {
            // Persistence remains best-effort for live chat, but failed rows stay
            // pending so a later enqueue, background, or disconnect flush can retry.
        }
    }

    private static func key(for message: ChatMessage) -> String {
        "\(message.channelID)\u{0}\(message.id)"
    }
}

struct NoopChatHistory: ChatHistoryPersisting {
    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage] {
        []
    }

    func olderMessages(
        channelID: String,
        before cursor: ChatHistoryCursor,
        limit: Int
    ) async -> [ChatMessage] {
        []
    }

    func enqueue(_ message: ChatMessage) async {}

    func maintain(
        channelID: String,
        retentionBoundaryMilliseconds: Int64?,
        keepingLatest: Int,
        maxDatabaseSizeMB: Int
    ) async {}

    func flush() async {}
}

enum ChatPersistenceStoreFactory {
    private static let sharedStore: PersistenceStore? = {
        do {
            let fileManager = FileManager.default
            guard var directory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return nil
            }
            directory.appendPathComponent("Ferventio", isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? directory.setResourceValues(resourceValues)

            let databaseURL = directory.appendingPathComponent(
                "chat-history.sqlite",
                isDirectory: false
            )
            return try PersistenceStore(path: databaseURL.path)
        } catch {
            return nil
        }
    }()

    static func liveStore() -> PersistenceStore? {
        sharedStore
    }
}

enum ChatHistoryFactory {
    static func live() -> any ChatHistoryPersisting {
        guard let store = ChatPersistenceStoreFactory.liveStore() else {
            return NoopChatHistory()
        }
        return PersistenceChatHistory(store: store)
    }
}
