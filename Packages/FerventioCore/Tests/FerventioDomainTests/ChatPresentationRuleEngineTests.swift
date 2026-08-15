import Foundation
import Testing
@testable import FerventioDomain

struct ChatPresentationRuleEngineTests {
    @Test
    func hidesMatchingMessageWithoutMutatingCanonicalInput() {
        let visible = makeMessage(id: "visible", text: "hello")
        let hidden = makeMessage(id: "hidden", text: "BUY followers now")
        let messages = [visible, hidden]
        let rule = ChatPresentationRule(
            action: .hide,
            target: .message,
            query: "buy followers"
        )

        let projection = ChatPresentationRuleEngine.project(
            messages: messages,
            rules: [rule]
        )

        #expect(projection.visibleMessages == [visible])
        #expect(messages == [visible, hidden])
        #expect(projection.highlightedMessageIDs.isEmpty)
    }

    @Test
    func highlightsAuthorByLoginOrDisplayName() {
        let byLogin = makeMessage(
            id: "login",
            authorLogin: "trusted_mod",
            authorDisplayName: "Trusted Mod",
            text: "one"
        )
        let byDisplayName = makeMessage(
            id: "display",
            authorLogin: "someone",
            authorDisplayName: "TRUSTED MOD",
            text: "two"
        )
        let other = makeMessage(id: "other", text: "three")
        let displayNameRule = ChatPresentationRule(
            action: .highlight,
            target: .author,
            query: "trusted mod"
        )

        let displayNameProjection = ChatPresentationRuleEngine.project(
            messages: [byLogin, byDisplayName, other],
            rules: [displayNameRule]
        )

        #expect(displayNameProjection.visibleMessages == [byLogin, byDisplayName, other])
        #expect(displayNameProjection.highlightedMessageIDs == ["login", "display"])

        let loginRule = ChatPresentationRule(
            action: .highlight,
            target: .author,
            query: "trusted_mod"
        )
        let loginProjection = ChatPresentationRuleEngine.project(
            messages: [byLogin, byDisplayName, other],
            rules: [loginRule]
        )
        #expect(loginProjection.highlightedMessageIDs == ["login"])
    }

    @Test
    func regexSupportsCaseSensitivity() {
        let upper = makeMessage(id: "upper", text: "ALERT-42")
        let lower = makeMessage(id: "lower", text: "alert-42")
        let insensitive = ChatPresentationRule(
            action: .highlight,
            target: .message,
            matchMode: .regex,
            query: #"alert-\d+"#,
            caseSensitive: false
        )
        let sensitive = ChatPresentationRule(
            action: .highlight,
            target: .message,
            matchMode: .regex,
            query: #"alert-\d+"#,
            caseSensitive: true
        )

        let insensitiveProjection = ChatPresentationRuleEngine.project(
            messages: [upper, lower],
            rules: [insensitive]
        )
        let sensitiveProjection = ChatPresentationRuleEngine.project(
            messages: [upper, lower],
            rules: [sensitive]
        )

        #expect(insensitiveProjection.highlightedMessageIDs == ["upper", "lower"])
        #expect(sensitiveProjection.highlightedMessageIDs == ["lower"])
    }

    @Test
    func disabledAndInvalidRulesAreIgnoredAtRuntime() {
        let message = makeMessage(id: "message", text: "hide me")
        let disabled = ChatPresentationRule(
            isEnabled: false,
            action: .hide,
            target: .message,
            query: "hide me"
        )
        let invalidRegex = ChatPresentationRule(
            action: .hide,
            target: .message,
            matchMode: .regex,
            query: "["
        )

        let projection = ChatPresentationRuleEngine.project(
            messages: [message],
            rules: [disabled, invalidRegex]
        )

        #expect(projection.visibleMessages == [message])
        #expect(
            ChatPresentationRuleEngine.validate(invalidRegex)
                == .invalidRegularExpression
        )
    }

    @Test
    func hideWinsOverHighlightForSameMessage() {
        let message = makeMessage(id: "message", text: "keyword")
        let rules = [
            ChatPresentationRule(
                action: .highlight,
                target: .message,
                query: "keyword"
            ),
            ChatPresentationRule(
                action: .hide,
                target: .message,
                query: "keyword"
            ),
        ]

        let projection = ChatPresentationRuleEngine.project(
            messages: [message],
            rules: rules
        )

        #expect(projection.visibleMessages.isEmpty)
        #expect(projection.highlightedMessageIDs.isEmpty)
    }

    @Test
    func validatesEmptyAndOversizedQueries() {
        let empty = ChatPresentationRule(
            action: .hide,
            target: .message,
            query: "   "
        )
        let oversized = ChatPresentationRule(
            action: .hide,
            target: .message,
            query: String(
                repeating: "x",
                count: ChatPresentationRuleEngine.maximumQueryLength + 1
            )
        )

        #expect(ChatPresentationRuleEngine.validate(empty) == .emptyQuery)
        #expect(
            ChatPresentationRuleEngine.validate(oversized)
                == .queryTooLong(
                    maximumLength: ChatPresentationRuleEngine.maximumQueryLength
                )
        )
    }

    @Test
    func containsMatchingIsCaseAndDiacriticInsensitiveByDefault() {
        let message = makeMessage(id: "message", text: "Café STREAM")
        let rule = ChatPresentationRule(
            action: .highlight,
            target: .message,
            query: "cafe stream"
        )

        let projection = ChatPresentationRuleEngine.project(
            messages: [message],
            rules: [rule]
        )

        #expect(projection.isHighlighted(messageID: message.id))
    }

    @Test
    func compiledPlanCanProjectMultipleSnapshotsWithStableSemantics() {
        let rules = [
            ChatPresentationRule(
                action: .hide,
                target: .message,
                matchMode: .regex,
                query: #"spam-\d+"#
            ),
            ChatPresentationRule(
                action: .highlight,
                target: .author,
                query: "café mod"
            ),
        ]
        let plan = ChatPresentationRulePlan(rules: rules)
        let firstVisible = makeMessage(
            id: "first-visible",
            authorLogin: "mod",
            authorDisplayName: "CAFÉ MOD",
            text: "hello"
        )
        let firstHidden = makeMessage(id: "first-hidden", text: "SPAM-42")
        let secondVisible = makeMessage(id: "second-visible", text: "later")

        let first = plan.project(messages: [firstVisible, firstHidden])
        let second = plan.project(messages: [secondVisible])

        #expect(first.visibleMessages == [firstVisible])
        #expect(first.highlightedMessageIDs == [firstVisible.id])
        #expect(second.visibleMessages == [secondVisible])
        #expect(second.highlightedMessageIDs.isEmpty)
    }

    @Test
    func cachedPlansRemainCorrectWhileDifferentRulesProjectConcurrently() async {
        let spam = makeMessage(id: "spam", text: "spam")
        let safe = makeMessage(id: "safe", text: "safe")
        let hideSpam = [
            ChatPresentationRule(
                action: .hide,
                target: .message,
                query: "spam"
            ),
        ]
        let hideSafe = [
            ChatPresentationRule(
                action: .hide,
                target: .message,
                query: "safe"
            ),
        ]

        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<100 {
                let rules = index.isMultiple(of: 2) ? hideSpam : hideSafe
                let expectedID = index.isMultiple(of: 2) ? safe.id : spam.id
                group.addTask {
                    let projection = ChatPresentationRuleEngine.project(
                        messages: [spam, safe],
                        rules: rules
                    )
                    return projection.visibleMessages.map(\.id) == [expectedID]
                }
            }

            for await isCorrect in group {
                #expect(isCorrect)
            }
        }
    }

    private func makeMessage(
        id: String,
        authorLogin: String = "viewer",
        authorDisplayName: String = "Viewer",
        text: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: authorLogin,
                login: authorLogin,
                displayName: authorDisplayName
            ),
            text: text,
            timestamp: "2026-08-14T08:00:00Z",
            timestampMilliseconds: 1_000
        )
    }
}
