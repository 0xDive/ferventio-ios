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
    static let flushDelay = Duration.milliseconds(250)

    private let store: PersistenceStore
    private var pendingMessages: [String: ChatMessage] = [:]
    private var flushTask: Task<Void, Never>?

    init(store: PersistenceStore) {
        self.store = store
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
        pendingMessages[Self.key(for: message)] = message
        guard flushTask == nil else {
            return
        }
        flushTask = Task {
            try? await Task.sleep(for: Self.flushDelay)
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

        let batch = Array(pendingMessages.values)
        pendingMessages.removeAll(keepingCapacity: true)
        do {
            try await store.save(batch)
        } catch {
            // Persistence is intentionally best-effort. Failed writes must not
            // affect EventSub connectivity or user-visible chat state.
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
