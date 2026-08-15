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
    func successfulSendClearsAlreadyClearedDraftAndRefreshesNewestFirstHistory() async {
        let persistence = StubChatComposerPersistence(
            drafts: ["channel": "Hello"]
        )
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel")
        store.updateDraft(channelID: "channel", text: "Hello")
        // ChatStore clears the composer when a send begins, before the network
        // response determines whether the message was accepted.
        store.updateDraft(channelID: "channel", text: "")
        await store.recordSuccessfulSend(channelID: "channel", text: "Hello")

        #expect(await persistence.draft(channelID: "channel") == nil)
        #expect(store.sentHistory.count == 1)
        #expect(store.sentHistory.first?.text == "Hello")
        #expect(await persistence.recordedKeepingLatest() == ChatComposerStore.maximumSentHistory)
    }

    @Test
    func successfulSendPreservesNewDraftTypedWhileRequestWasInFlight() async {
        let persistence = StubChatComposerPersistence(
            drafts: ["channel": "Hello"]
        )
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel")
        store.updateDraft(channelID: "channel", text: "")
        store.updateDraft(channelID: "channel", text: "Next message")
        await store.recordSuccessfulSend(channelID: "channel", text: "Hello")

        #expect(await persistence.draft(channelID: "channel") == "Next message")
        #expect(store.sentHistory.first?.text == "Hello")
    }

    @Test
    func staleActivationCannotReplaceNewerChannelAfterDraftFlush() async {
        let persistence = BlockingDraftFlushPersistence(
            drafts: [
                "channel-a": "Draft A",
                "channel-c": "Draft C",
            ]
        )
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel-a")
        store.updateDraft(channelID: "channel-a", text: "Edited A")

        let staleActivation = Task { @MainActor in
            await store.activate(channelID: "channel-b")
        }
        await persistence.waitUntilFirstSaveStarts()

        #expect(await store.activate(channelID: "channel-c") == "Draft C")
        #expect(store.activeChannelID == "channel-c")

        await persistence.releaseFirstSave()
        _ = await staleActivation.value

        #expect(store.activeChannelID == "channel-c")
    }

    @Test
    func switchingChannelsPersistsEditMadeWhilePreviousDraftFlushes() async {
        let persistence = BlockingDraftFlushPersistence(
            drafts: [
                "channel-a": "Draft A",
                "channel-b": "Draft B",
            ]
        )
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel-a")
        store.updateDraft(channelID: "channel-a", text: "First edit")

        let switchTask = Task { @MainActor in
            await store.activate(channelID: "channel-b")
        }
        await persistence.waitUntilFirstSaveStarts()

        store.updateDraft(channelID: "channel-a", text: "Newest A")
        await persistence.releaseFirstSave()

        #expect(await switchTask.value == "Draft B")
        #expect(await persistence.draft(channelID: "channel-a") == "Newest A")
        #expect(store.activeChannelID == "channel-b")
    }

    @Test
    func staleSentHistoryReloadCannotReplaceNewChannelHistory() async {
        let persistence = BlockingSentHistoryPersistence()
        let store = ChatComposerStore(persistence: persistence)

        _ = await store.activate(channelID: "channel-a")
        let staleRecord = Task { @MainActor in
            await store.recordSuccessfulSend(channelID: "channel-a", text: "Sent A")
        }
        await persistence.waitUntilRecordedHistoryLoadStarts()

        _ = await store.activate(channelID: "channel-b")
        #expect(store.activeChannelID == "channel-b")
        #expect(store.sentHistory.first?.text == "Existing B")

        await persistence.releaseRecordedHistoryLoad()
        await staleRecord.value

        #expect(store.activeChannelID == "channel-b")
        #expect(store.sentHistory.first?.text == "Existing B")
    }

    @Test
    func activationReturnsDraftEditedWhileHistoryLoads() async {
        let persistence = BlockingActivationHistoryPersistence(draft: "Stored draft")
        let store = ChatComposerStore(persistence: persistence)

        let activation = Task { @MainActor in
            await store.activate(channelID: "channel")
        }
        await persistence.waitUntilHistoryLoadStarts()

        store.updateDraft(channelID: "channel", text: "Fresh input")
        await persistence.releaseHistoryLoad()

        #expect(await activation.value == "Fresh input")
        #expect(store.activeChannelID == "channel")
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

private actor BlockingDraftFlushPersistence: ChatComposerPersisting {
    private var drafts: [String: String]
    private var firstSaveStarted = false
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var shouldBlockFirstSave = true

    init(drafts: [String: String]) {
        self.drafts = drafts
    }

    func draft(channelID: String) -> String? {
        drafts[channelID]
    }

    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) async {
        if shouldBlockFirstSave {
            shouldBlockFirstSave = false
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
        drafts[channelID] = text
    }

    func deleteDraft(channelID: String) {
        drafts.removeValue(forKey: channelID)
    }

    func sentMessages(channelID: String, limit: Int) -> [SentChatMessageRecord] {
        []
    }

    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) {}

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
}

private actor BlockingSentHistoryPersistence: ChatComposerPersisting {
    private var history: [String: [SentChatMessageRecord]] = [
        "channel-b": [
            SentChatMessageRecord(
                id: "existing-b",
                channelID: "channel-b",
                text: "Existing B",
                sentAtMilliseconds: 1
            )
        ]
    ]
    private var shouldBlockRecordedHistoryLoad = false
    private var recordedHistoryLoadStarted = false
    private var recordedHistoryLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var recordedHistoryLoadContinuation: CheckedContinuation<Void, Never>?

    func draft(channelID: String) -> String? {
        nil
    }

    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) {}

    func deleteDraft(channelID: String) {}

    func sentMessages(channelID: String, limit: Int) async -> [SentChatMessageRecord] {
        if channelID == "channel-a", shouldBlockRecordedHistoryLoad {
            shouldBlockRecordedHistoryLoad = false
            await withCheckedContinuation { continuation in
                recordedHistoryLoadContinuation = continuation
                recordedHistoryLoadStarted = true
                let waiters = recordedHistoryLoadWaiters
                recordedHistoryLoadWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }
        return Array((history[channelID] ?? []).prefix(limit))
    }

    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) {
        var entries = history[entry.channelID] ?? []
        entries.insert(entry, at: 0)
        history[entry.channelID] = Array(entries.prefix(limit))
        if entry.channelID == "channel-a" {
            shouldBlockRecordedHistoryLoad = true
        }
    }

    func waitUntilRecordedHistoryLoadStarts() async {
        guard !recordedHistoryLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            recordedHistoryLoadWaiters.append(continuation)
        }
    }

    func releaseRecordedHistoryLoad() {
        recordedHistoryLoadContinuation?.resume()
        recordedHistoryLoadContinuation = nil
    }
}

private actor BlockingActivationHistoryPersistence: ChatComposerPersisting {
    private let storedDraft: String
    private var historyLoadStarted = false
    private var historyLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var historyLoadContinuation: CheckedContinuation<Void, Never>?

    init(draft: String) {
        storedDraft = draft
    }

    func draft(channelID: String) -> String? {
        storedDraft
    }

    func saveDraft(channelID: String, text: String, updatedAtMilliseconds: Int64) {}

    func deleteDraft(channelID: String) {}

    func sentMessages(channelID: String, limit: Int) async -> [SentChatMessageRecord] {
        await withCheckedContinuation { continuation in
            historyLoadContinuation = continuation
            historyLoadStarted = true
            let waiters = historyLoadWaiters
            historyLoadWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
        return []
    }

    func recordSentMessage(_ entry: SentChatMessageRecord, keepingLatest limit: Int) {}

    func waitUntilHistoryLoadStarts() async {
        guard !historyLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            historyLoadWaiters.append(continuation)
        }
    }

    func releaseHistoryLoad() {
        historyLoadContinuation?.resume()
        historyLoadContinuation = nil
    }
}
