import Testing
@testable import FerventioDomain

struct BttvEmoteCompositionPlannerTests {
    @Test
    func prefixModifierAppliesToNextEmoteAndHidesSpacing() {
        let fragments: [ChatFragment] = [
            .thirdPartyEmote(
                text: "h!",
                emoteID: "modifier",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
            .text(" "),
            .thirdPartyEmote(
                text: "OMEGALUL",
                emoteID: "base",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)

        #expect(plan.hiddenFragmentIndices == [0, 1])
        #expect(plan.groups == [
            BttvEmoteGroup(baseFragmentIndex: 2, effects: [.flipX])
        ])
    }

    @Test
    func zeroWidthEmoteAttachesToPreviousRenderableEmote() {
        let fragments: [ChatFragment] = [
            .thirdPartyEmote(
                text: "Base",
                emoteID: "base",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
            .thirdPartyEmote(
                text: "Overlay",
                emoteID: "overlay",
                provider: "7tv",
                animated: true,
                imageURL: nil,
                zeroWidth: true
            ),
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)

        #expect(plan.hiddenFragmentIndices == [1])
        #expect(plan.groups == [
            BttvEmoteGroup(baseFragmentIndex: 0, overlayFragmentIndices: [1])
        ])
    }

    @Test
    func knownBetterTTVOverlayIDComposesEvenWithoutZeroWidthFlag() {
        let fragments: [ChatFragment] = [
            .twitchEmote(
                text: "Kappa",
                emoteID: "25",
                emoteSetID: nil,
                ownerID: nil,
                formats: ["static"]
            ),
            .thirdPartyEmote(
                text: "SoSnowy",
                emoteID: "567b5b520e984428652809b6",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)

        #expect(plan.hiddenFragmentIndices == [1])
        #expect(plan.groups.first?.overlayFragmentIndices == [1])
    }

    @Test
    func textBreaksPendingModifierWithoutHidingWhitespace() {
        let fragments: [ChatFragment] = [
            .thirdPartyEmote(
                text: "w!",
                emoteID: "modifier",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
            .text(" "),
            .text("hello"),
            .thirdPartyEmote(
                text: "OMEGALUL",
                emoteID: "base",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)

        #expect(plan.hiddenFragmentIndices == [0])
        #expect(plan.groups.last?.effects.isEmpty == true)
    }

    @Test
    func multipleModifiersAccumulateOnOneBaseEmote() {
        let fragments: [ChatFragment] = [
            modifier("h!"),
            modifier("v!"),
            .thirdPartyEmote(
                text: "Base",
                emoteID: "base",
                provider: "bttv",
                animated: false,
                imageURL: nil,
                zeroWidth: false
            ),
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)

        #expect(plan.groups.first?.effects == [.flipX, .flipY])
        #expect(plan.hiddenFragmentIndices == [0, 1])
    }

    private func modifier(_ code: String) -> ChatFragment {
        .thirdPartyEmote(
            text: code,
            emoteID: "modifier-\(code)",
            provider: "bttv",
            animated: false,
            imageURL: nil,
            zeroWidth: false
        )
    }
}
