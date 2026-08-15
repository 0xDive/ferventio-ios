import Foundation
import FerventioPersistence
import Observation

protocol ChatComposerPersisting: Sendable {
    func draft(channelID: String) async -> String?
    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) async
    func deleteDraft(channelID: String) async
    func sentMessages(channelID: String, limit: Int) async -> [SentChatMessageRecord]
    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) async
}

actor PersistenceChatComposer: ChatComposerPersisting {
    private let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
    }

    func draft(channelID: String) async -> String? {
        try? await store.draft(channelID: channelID)
    }

    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) async {
        try? await store.saveDraft(
            channelID: channelID,
            text: text,
            updatedAtMilliseconds: updatedAtMilliseconds
        )
    }

    func deleteDraft(channelID: String) async {
        try? await store.deleteDraft(channelID: channelID)
    }

    func sentMessages(channelID: String, limit: Int) async -> [SentChatMessageRecord] {
        (try? await store.sentMessages(channelID: channelID, limit: limit)) ?? []
    }

    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) async {
        try? await store.recordSentMessage(entry, keepingLatest: limit)
    }
}

struct NoopChatComposerPersistence: ChatComposerPersisting {
    func draft(channelID: String) async -> String? { nil }
    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) async {}
    func deleteDraft(channelID: String) async {}
    func sentMessages(channelID: String, limit: Int) async -> [SentChatMessageRecord] { [] }
    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) async {}
}

@MainActor
@Observable
final class ChatComposerStore {
    static let maximumSentHistory = 100
    static let visibleSentHistoryLimit = 20
    static let draftSaveDelay = Duration.milliseconds(300)

    private(set) var sentHistory: [SentChatMessageRecord] = []
    private(set) var activeChannelID: String?

    @ObservationIgnored private let persistence: any ChatComposerPersisting
    @ObservationIgnored private var pendingDrafts: [String: String] = [:]
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(persistence: (any ChatComposerPersisting)? = nil) {
        self.persistence = persistence ?? NoopChatComposerPersistence()
    }

    static func live() -> ChatComposerStore {
        guard let store = ChatPersistenceStoreFactory.liveStore() else {
            return ChatComposerStore()
        }
        return ChatComposerStore(persistence: PersistenceChatComposer(store: store))
    }

    func activate(channelID: String?) async -> String {
        generation &+= 1
        let currentGeneration = generation

        if let previousChannelID = activeChannelID,
           previousChannelID != channelID {
            await flushDraft(channelID: previousChannelID)
            guard generation == currentGeneration else {
                return ""
            }
        }

        draftSaveTask?.cancel()
        draftSaveTask = nil
        activeChannelID = channelID

        guard let channelID else {
            sentHistory = []
            return ""
        }

        let draft = if let pending = pendingDrafts[channelID] {
            pending
        } else {
            await persistence.draft(channelID: channelID) ?? ""
        }
        let history = await persistence.sentMessages(
            channelID: channelID,
            limit: Self.visibleSentHistoryLimit
        )

        guard generation == currentGeneration,
              activeChannelID == channelID else {
            return draft
        }
        sentHistory = history
        return pendingDrafts[channelID] ?? draft
    }

    func updateDraft(channelID: String?, text: String) {
        guard let channelID, activeChannelID == channelID else {
            return
        }

        pendingDrafts[channelID] = text
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.draftSaveDelay)
            guard !Task.isCancelled, let self else {
                return
            }
            await self.flushDraft(channelID: channelID)
        }
    }

    func recordSuccessfulSend(channelID: String, text: String) async {
        let currentGeneration = generation
        let nowMilliseconds = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded(.towardZero)
        )
        let entry = SentChatMessageRecord(
            id: UUID().uuidString.lowercased(),
            channelID: channelID,
            text: text,
            sentAtMilliseconds: nowMilliseconds
        )

        if activeChannelID == channelID {
            draftSaveTask?.cancel()
            draftSaveTask = nil
            await flushDraft(channelID: channelID)
        }
        await persistence.recordSentMessage(entry, keepingLatest: Self.maximumSentHistory)
        let history = await persistence.sentMessages(
            channelID: channelID,
            limit: Self.visibleSentHistoryLimit
        )

        guard generation == currentGeneration,
              activeChannelID == channelID else {
            return
        }
        sentHistory = history
    }

    func flush() async {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard let activeChannelID else {
            return
        }
        await flushDraft(channelID: activeChannelID)
    }

    private func flushDraft(channelID: String) async {
        while let text = pendingDrafts[channelID] {
            if text.isEmpty {
                await persistence.deleteDraft(channelID: channelID)
            } else {
                let nowMilliseconds = Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded(.towardZero)
                )
                await persistence.saveDraft(
                    channelID: channelID,
                    text: text,
                    updatedAtMilliseconds: nowMilliseconds
                )
            }

            guard pendingDrafts[channelID] != text else {
                return
            }
        }
    }
}
