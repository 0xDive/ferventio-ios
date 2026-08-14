import Testing
@testable import FerventioDomain

struct FfzEmoteCompositionPlannerTests {
    @Test
    func parserEncodesModifierMetadataWithoutChangingCanonicalTextContract() {
        let catalog = ThirdPartyEmoteCatalog(emotes: [
            ThirdPartyEmoteDefinition(
                code: "FlipIt",
                emoteID: "m1",
                provider: "ffz",
                animated: false,
                imageURL: "https://cdn.example/m1.png",
                modifier: true,
                modifierPrefix: true,
                modifierFlags: (1 << 1) | (1 << 17)
            )
        ])

        let fragments = ThirdPartyEmoteParser.apply(to: [.text("FlipIt Kappa")], catalog: catalog)

        guard case let .thirdPartyEmote(text, _, provider, _, _, _) = fragments[0] else {
            Issue.record("Expected FFZ modifier fragment")
            return
        }
        #expect(text == "FlipIt")
        #expect(FfzModifierFragmentMetadata.parse(provider: provider)?.prefix == true)
        #expect(FfzModifierFragmentMetadata.parse(provider: provider)?.flags == (1 << 1) | (1 << 17))
    }

    @Test
    func hiddenPrefixModifierAppliesEffectsToFollowingEmoteWithoutOverlay() {
        let modifier = ffzModifier(prefix: true, flags: (1 << 0) | (1 << 1) | (1 << 17))
        let fragments: [ChatFragment] = [modifier, .text(" "), twitchEmote()]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)
        let group = plan.group(forBaseFragment: 2)

        #expect(group?.effects.contains(.flipX) == true)
        #expect(group?.effects.contains(.noSpace) == true)
        #expect(group?.overlayFragmentIndices.isEmpty == true)
        #expect(plan.hiddenFragmentIndices == [0, 1])
    }

    @Test
    func visibleSuffixModifierAttachesToPreviousEmoteAndConsumesWhitespace() {
        let fragments: [ChatFragment] = [
            twitchEmote(),
            .text(" "),
            ffzModifier(prefix: false, flags: (1 << 2) | (1 << 13))
        ]

        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)
        let group = plan.group(forBaseFragment: 0)

        #expect(group?.effects.contains(.flipY) == true)
        #expect(group?.effects.contains(.shake) == true)
        #expect(group?.overlayFragmentIndices == [2])
        #expect(plan.hiddenFragmentIndices == [1, 2])
    }

    @Test
    func unattachedSuffixModifierRemainsVisible() {
        let fragments: [ChatFragment] = [ffzModifier(prefix: false, flags: 0), .text(" hello")]
        let plan = BttvEmoteCompositionPlanner.build(fragments: fragments)
        #expect(plan.hiddenFragmentIndices.isEmpty)
    }

    private func ffzModifier(prefix: Bool, flags: Int) -> ChatFragment {
        .thirdPartyEmote(
            text: "Modifier",
            emoteID: "m",
            provider: FfzModifierFragmentMetadata.providerMarker(prefix: prefix, flags: flags),
            animated: false,
            imageURL: "https://cdn.example/m.png",
            zeroWidth: false
        )
    }

    private func twitchEmote() -> ChatFragment {
        .twitchEmote(text: "Kappa", emoteID: "25", emoteSetID: nil, ownerID: nil, formats: [])
    }
}
