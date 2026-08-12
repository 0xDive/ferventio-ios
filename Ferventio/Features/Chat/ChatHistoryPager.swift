import FerventioDomain
import FerventioPersistence
import Observation

@MainActor
@Observable
final class ChatHistoryPager {
    static let pageSize = 200

    private(set) var olderMessages: [ChatMessage] = []
    private(set) var isLoadingOlderHistory = false
    private(set) var canLoadOlderHistory = false

    @ObservationIgnored private let history: any ChatHistoryPersisting
    @ObservationIgnored private var preferences: ChatHistoryPreferences
    @ObservationIgnored private var channelID: String?
    @ObservationIgnored private var cursor: ChatHistoryCursor?
    @ObservationIgnored private var generation = 0

    init(
        history: any ChatHistoryPersisting,
        preferences: ChatHistoryPreferences
    ) {
        self.history = history
        self.preferences = preferences
    }

    func reset(channelID: String?) {
        generation &+= 1
        self.channelID = channelID
        cursor = nil
        olderMessages.removeAll(keepingCapacity: false)
        isLoadingOlderHistory = false
        canLoadOlderHistory = preferences.localHistoryEnabled && channelID != nil
    }

    func updatePreferences(_ preferences: ChatHistoryPreferences) {
        let wasEnabled = self.preferences.localHistoryEnabled
        self.preferences = preferences

        guard preferences.localHistoryEnabled else {
            generation &+= 1
            cursor = nil
            olderMessages.removeAll(keepingCapacity: false)
            isLoadingOlderHistory = false
            canLoadOlderHistory = false
            return
        }

        if !wasEnabled {
            cursor = nil
        }
        canLoadOlderHistory = channelID != nil
    }

    func mergedMessages(with liveMessages: [ChatMessage]) -> [ChatMessage] {
        guard !olderMessages.isEmpty else {
            return liveMessages
        }
        let liveIDs = Set(liveMessages.map(\.id))
        return olderMessages.filter { !liveIDs.contains($0.id) } + liveMessages
    }

    @discardableResult
    func loadOlderHistory(
        before firstVisibleMessage: ChatMessage?,
        excluding liveMessageIDs: Set<String>
    ) async -> String? {
        guard preferences.localHistoryEnabled,
              canLoadOlderHistory,
              !isLoadingOlderHistory,
              let channelID,
              let firstVisibleMessage else {
            return nil
        }

        let requestCursor = cursor ?? ChatHistoryCursor(
            timestampMilliseconds: firstVisibleMessage.timestampMilliseconds,
            messageID: firstVisibleMessage.id
        )
        let currentGeneration = generation
        isLoadingOlderHistory = true
        defer {
            if generation == currentGeneration {
                isLoadingOlderHistory = false
            }
        }

        let page = await history.olderMessages(
            channelID: channelID,
            before: requestCursor,
            limit: Self.pageSize
        )
        guard generation == currentGeneration,
              self.channelID == channelID,
              preferences.localHistoryEnabled else {
            return nil
        }

        if let oldest = page.first {
            cursor = ChatHistoryCursor(
                timestampMilliseconds: oldest.timestampMilliseconds,
                messageID: oldest.id
            )
        }
        if page.count < Self.pageSize {
            canLoadOlderHistory = false
        }
        guard !page.isEmpty else {
            canLoadOlderHistory = false
            return nil
        }

        var knownIDs = liveMessageIDs
        knownIDs.formUnion(olderMessages.map(\.id))
        let uniquePage = page.filter { knownIDs.insert($0.id).inserted }
        guard !uniquePage.isEmpty else {
            return nil
        }

        olderMessages = uniquePage + olderMessages
        return firstVisibleMessage.id
    }
}
