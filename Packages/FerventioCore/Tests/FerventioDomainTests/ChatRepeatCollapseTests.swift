import Testing
@testable import FerventioDomain

struct ChatRepeatCollapseTests {
    @Test
    func collapsesThreeConsecutiveCopiesAcrossAuthorsAndNormalizationVariants() {
        let messages = [
            makeMessage(id: "one", authorID: "a", text: "OMEGALUL", timestamp: 1_000),
            makeMessage(id: "two", authorID: "b", text: "  omegalul  ", timestamp: 2_000),
            makeMessage(id: "three", authorID: "c", text: "OMEGALUL", timestamp: 3_000),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.count == 1)
        #expect(groups[0].id == "repeat:one")
        #expect(groups[0].repeatCount == 3)
        #expect(groups[0].representative.id == "one")
        #expect(groups[0].memberIDs == ["one", "two", "three"])
        #expect(groups[0].participants.map(\.userID) == ["a", "b", "c"])
        #expect(groups[0].totalParticipantCount == 3)
    }

    @Test
    func twoCopiesStayVisibleUntilMinimumRepeatCountIsReached() {
        let groups = ChatRepeatCollapsePlanner.collapse([
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "two", text: "same", timestamp: 2_000),
        ])

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.repeatCount == 1 })
    }

    @Test
    func keepsCopiesSeparateWhenAnotherMessageInterruptsRun() {
        let messages = [
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "middle", text: "different", timestamp: 2_000),
            makeMessage(id: "three", text: "same", timestamp: 3_000),
            makeMessage(id: "four", text: "same", timestamp: 4_000),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.map(\.repeatCount) == [1, 1, 1, 1])
        #expect(groups.flatMap(\.memberIDs) == messages.map(\.id))
    }

    @Test
    func repeatWindowIsMeasuredFromFirstMessageInRun() {
        let groups = ChatRepeatCollapsePlanner.collapse([
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "two", text: "same", timestamp: 6_000),
            makeMessage(id: "three", text: "same", timestamp: 11_000),
            makeMessage(id: "four", text: "same", timestamp: 11_001),
        ])

        #expect(groups.map(\.repeatCount) == [3, 1])
    }

    @Test
    func disablingCollapseReturnsCanonicalMessagesAsSingles() {
        let groups = ChatRepeatCollapsePlanner.collapse(
            [
                makeMessage(id: "one", text: "same", timestamp: 1_000),
                makeMessage(id: "two", text: "same", timestamp: 2_000),
                makeMessage(id: "three", text: "same", timestamp: 3_000),
            ],
            config: ChatRepeatCollapseConfig(enabled: false)
        )

        #expect(groups.map(\.repeatCount) == [1, 1, 1])
    }

    @Test
    func actionMessagesCanCollapse() {
        let groups = ChatRepeatCollapsePlanner.collapse([
            makeMessage(id: "one", text: "waves", timestamp: 1_000, type: .action),
            makeMessage(id: "two", text: "WAVES", timestamp: 2_000, type: .action),
            makeMessage(id: "three", text: "waves", timestamp: 3_000, type: .action),
        ])

        #expect(groups.count == 1)
        #expect(groups[0].repeatCount == 3)
    }

    @Test
    func protectedModerationBadgesNeverCollapse() {
        let badge = ChatBadge(setID: "moderator", id: "1")
        let groups = ChatRepeatCollapsePlanner.collapse([
            makeMessage(id: "one", text: "same", timestamp: 1_000, badges: [badge]),
            makeMessage(id: "two", text: "same", timestamp: 2_000, badges: [badge]),
            makeMessage(id: "three", text: "same", timestamp: 3_000, badges: [badge]),
        ])

        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.repeatCount == 1 })
    }

    @Test
    func doesNotCollapseRepliesDeletedSystemOrUnsettledMessages() {
        let messages = [
            makeMessage(id: "plain", text: "same", timestamp: 1_000),
            makeMessage(
                id: "reply",
                text: "same",
                timestamp: 2_000,
                reply: ReplyContext(parentMessageID: "parent")
            ),
            makeMessage(
                id: "deleted",
                text: "same",
                timestamp: 3_000,
                flags: MessageFlags(isDeleted: true)
            ),
            makeMessage(
                id: "system",
                text: "same",
                timestamp: 4_000,
                flags: MessageFlags(isSystem: true)
            ),
            makeMessage(
                id: "sending",
                text: "same",
                timestamp: 5_000,
                outgoingState: .sending
            ),
            makeMessage(
                id: "failed",
                text: "same",
                timestamp: 6_000,
                outgoingState: .failed
            ),
        ]

        let groups = ChatRepeatCollapsePlanner.collapse(messages)

        #expect(groups.count == messages.count)
        #expect(groups.allSatisfy { $0.repeatCount == 1 })
    }

    @Test
    func participantSummaryIsBoundedWithoutLosingTotalCount() {
        let groups = ChatRepeatCollapsePlanner.collapse(
            [
                makeMessage(id: "one", authorID: "a", text: "same", timestamp: 1_000),
                makeMessage(id: "two", authorID: "b", text: "same", timestamp: 2_000),
                makeMessage(id: "three", authorID: "c", text: "same", timestamp: 3_000),
            ],
            config: ChatRepeatCollapseConfig(maximumParticipants: 2)
        )

        #expect(groups[0].participants.map(\.userID) == ["a", "b"])
        #expect(groups[0].totalParticipantCount == 3)
        #expect(groups[0].omittedParticipantCount == 1)
    }

    @Test
    func preservesEveryCanonicalMessageExactlyOnce() {
        let messages = [
            makeMessage(id: "one", text: "same", timestamp: 1_000),
            makeMessage(id: "two", text: "same", timestamp: 2_000),
            makeMessage(id: "three", text: "same", timestamp: 3_000),
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
        outgoingState: OutgoingMessageState = .none,
        badges: [ChatBadge] = []
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: authorID,
                login: authorID,
                displayName: authorID,
                badges: badges
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
