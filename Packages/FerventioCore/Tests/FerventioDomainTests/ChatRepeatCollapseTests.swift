import Testing
@testable import FerventioDomain

struct ChatRepeatCollapseTests {
    @Test
    func collapsesConsecutiveCopiesAcrossAuthorsAndWhitespaceVariants() {
        let messages = [
            makeMessage(id: "one", authorID: "a", text: "OMEGALUL", timestamp: 1_000),
            makeMessage(id: "two", authorID: "b", text: "  OMEGALUL  ", timestamp: 2_000),
            makeMessage(id: "three", authorID: "c", text: "OMEGALUL", timestamp: 3_000),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.count == 1)
        #expect(groups[0].id == "repeat:one")
        #expect(groups[0].repeatCount == 3)
        #expect(groups[0].representative.id == "three")
        #expect(groups[0].memberIDs == ["one", "two", "three"])
    }

    @Test
    func keepsCopiesSeparateWhenAnotherMessageInterruptsRun() {
        let messages = [
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "middle", text: "different", timestamp: 2_000),
            makeMessage(id: "three", text: "same", timestamp: 3_000),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.map(\.repeatCount) == [1, 1, 1])
        #expect(groups.flatMap(\.memberIDs) == messages.map(\.id))
    }

    @Test
    func keepsCopiesSeparateOutsideTimeWindow() {
        let messages = [
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "two", text: "same", timestamp: 31_001),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.count == 2)
    }

    @Test
    func comparisonIsCaseSensitive() {
        let groups = ChatRepeatCollapsePlanner.collapse([
            makeMessage(id: "one", text: "Kappa", timestamp: 1_000),
            makeMessage(id: "two", text: "kappa", timestamp: 2_000),
        ])

        #expect(groups.count == 2)
    }

    @Test
    func doesNotCollapseSpecialOrUnsettledMessages() {
        let plain = makeMessage(id: "plain", text: "same", timestamp: 1_000)
        let reply = makeMessage(
            id: "reply",
            text: "same",
            timestamp: 2_000,
            reply: ReplyContext(parentMessageID: "parent")
        )
        let action = makeMessage(id: "action", text: "same", timestamp: 3_000, type: .action)
        let deleted = makeMessage(
            id: "deleted",
            text: "same",
            timestamp: 4_000,
            flags: MessageFlags(isDeleted: true)
        )
        let sending = makeMessage(
            id: "sending",
            text: "same",
            timestamp: 5_000,
            outgoingState: .sending
        )
        let failed = makeMessage(
            id: "failed",
            text: "same",
            timestamp: 6_000,
            outgoingState: .failed
        )

        let groups = ChatRepeatCollapsePlanner.collapse([
            plain,
            reply,
            action,
            deleted,
            sending,
            failed,
        ])

        #expect(groups.count == 6)
        #expect(groups.allSatisfy { $0.repeatCount == 1 })
    }

    @Test
    func preservesEveryCanonicalMessageExactlyOnce() {
        let messages = [
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "two", text: "same", timestamp: 2_000),
            makeMessage(id: "three", text: "other", timestamp: 3_000),
            makeMessage(id: "four", text: "other", timestamp: 4_000),
        ]

        let flattened = ChatRepeatCollapsePlanner.collapse(messages).flatMap(\.messages)

        #expect(flattened == messages)
    }

    private func makeMessage(
        id: String,
        authorID: String = "viewer",
        text: String,
        timestamp: Int64,
        reply: ReplyContext? = nil,
        type: ChatMessageType = .chat,
        flags: MessageFlags = MessageFlags(),
        outgoingState: OutgoingMessageState = .none
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: authorID,
                login: authorID,
                displayName: authorID
            ),
            text: text,
            timestamp: "2026-08-12T08:00:00Z",
            timestampMilliseconds: timestamp,
            reply: reply,
            type: type,
            flags: flags,
            outgoingState: outgoingState
        )
    }
}
