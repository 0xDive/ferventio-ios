import FerventioPersistence
import Testing
@testable import Ferventio

@MainActor
struct ChatComposerStoreTests {
    @Test
    func switchingChannelsFlushesAndRestoresIndependentDrafts() async {
        let persistence = StubChatComposerPersistence(
            drafts: [
                "channel-a": "Draft A",
                "channel-b": "Draft B",
            ]
        )
        let store = ChatComposerStore(persistence: persistence)

        #expect(await store.activate(channelID: "channel-a") == "Draft A")
        store.updateDraft(channelID: "channel-a", text: "Edited A")

        #expect(await store.activate(channelID: "channel-b") == "Draft B")
        #expect(await persistence.draft(channelID: "channel-a") == "Edited A")

        #expect(await store.activate(channelID: "channel-a") == "Edited A")
    }

    @Test
    func successfulSendClearsDraftAndRefreshesNewestFirstHistory() async {
        let persistence = StubChatComposerPersistence(
            drafts: ["channel": "Hello"]
        )
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel")
        store.updateDraft(channelID: "channel", text: "Hello")
        await store.recordSuccessfulSend(channelID: "channel", text: "Hello")

        #expect(await persistence.draft(channelID: "channel") == nil)
        #expect(store.sentHistory.count == 1)
        #expect(store.sentHistory.first?.text == "Hello")
        #expect(await persistence.recordedKeepingLatest() == ChatComposerStore.maximumSentHistory)
    }

    @Test
    func flushPersistsPendingDraftWithoutWaitingForDebounce() async {
        let persistence = StubChatComposerPersistence()
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel")
        store.updateDraft(channelID: "channel", text: "Last second draft")
        await store.flush()

        #expect(await persistence.draft(channelID: "channel") == "Last second draft")
    }
}

private actor StubChatComposerPersistence: ChatComposerPersisting {
    private var drafts: [String: String]
    private var history: [String: [SentChatMessageRecord]] = [:]
    private var lastKeepingLatest: Int?

    init(drafts: [String: String] = [:]) {
        self.drafts = drafts
    }

    func draft(channelID: String) -> String? {
        drafts[channelID]
    }

    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) {
        drafts[channelID] = text
    }

    func deleteDraft(channelID: String) {
        drafts.removeValue(forKey: channelID)
    }

    func sentMessages(channelID: String, limit: Int) -> [SentChatMessageRecord] {
        Array((history[channelID] ?? []).prefix(limit))
    }

    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) {
        lastKeepingLatest = limit
        var entries = history[entry.channelID] ?? []
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        history[entry.channelID] = entries
    }

    func recordedKeepingLatest() -> Int? {
        lastKeepingLatest
    }
}
