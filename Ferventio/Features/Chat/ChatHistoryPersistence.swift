import Foundation
import FerventioDomain
import FerventioPersistence

protocol ChatHistoryPersisting: Sendable {
    func recentMessages(channelID: String, limit: Int) async -> [ChatMessage]
    func enqueue(_ message: ChatMessage) async
    func maintain(
        channelID: String,
        olderThanTimestampMilliseconds: Int64,
        keepingLatest: Int
    ) async
    func flush() async
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
        olderThanTimestampMilliseconds: Int64,
        keepingLatest: Int
    ) async {
        _ = try? await store.prune(
            olderThanTimestampMilliseconds: olderThanTimestampMilliseconds
        )
        _ = try? await store.trim(
            channelID: channelID,
            keepingLatest: keepingLatest
        )
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

    func enqueue(_ message: ChatMessage) async {}

    func maintain(
        channelID: String,
        olderThanTimestampMilliseconds: Int64,
        keepingLatest: Int
    ) async {}

    func flush() async {}
}

enum ChatHistoryFactory {
    static func live() -> any ChatHistoryPersisting {
        do {
            let fileManager = FileManager.default
            guard var directory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return NoopChatHistory()
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
            let store = try PersistenceStore(path: databaseURL.path)
            return PersistenceChatHistory(store: store)
        } catch {
            return NoopChatHistory()
        }
    }
}
