import Foundation

public enum BttvModifierEffect: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case wide
    case flipX
    case flipY
    case rotateLeft
    case rotateRight
    case cursed
    case party
    case shake
    case noSpace
}

public struct BttvModifier: Equatable, Sendable {
    public let code: String
    public let effects: Set<BttvModifierEffect>

    public init(code: String, effects: Set<BttvModifierEffect>) {
        self.code = code
        self.effects = effects
    }
}

public struct BttvEmoteGroup: Equatable, Sendable {
    public let baseFragmentIndex: Int
    public let overlayFragmentIndices: [Int]
    public let effects: Set<BttvModifierEffect>

    public init(
        baseFragmentIndex: Int,
        overlayFragmentIndices: [Int] = [],
        effects: Set<BttvModifierEffect> = []
    ) {
        self.baseFragmentIndex = baseFragmentIndex
        self.overlayFragmentIndices = overlayFragmentIndices
        self.effects = effects
    }
}

public struct BttvEmoteCompositionPlan: Equatable, Sendable {
    public let groups: [BttvEmoteGroup]
    public let hiddenFragmentIndices: Set<Int>

    public init(
        groups: [BttvEmoteGroup],
        hiddenFragmentIndices: Set<Int>
    ) {
        self.groups = groups
        self.hiddenFragmentIndices = hiddenFragmentIndices
    }

    public func group(forBaseFragment index: Int) -> BttvEmoteGroup? {
        groups.first { $0.baseFragmentIndex == index }
    }

    public static let empty = BttvEmoteCompositionPlan(
        groups: [],
        hiddenFragmentIndices: []
    )
}

public enum BttvEmoteSemantics {
    private static let modifiers: [String: BttvModifier] = [
        "w!": BttvModifier(code: "w!", effects: [.wide]),
        "h!": BttvModifier(code: "h!", effects: [.flipX]),
        "v!": BttvModifier(code: "v!", effects: [.flipY]),
        "l!": BttvModifier(code: "l!", effects: [.rotateLeft]),
        "r!": BttvModifier(code: "r!", effects: [.rotateRight]),
        "c!": BttvModifier(code: "c!", effects: [.cursed]),
        "p!": BttvModifier(code: "p!", effects: [.party]),
        "s!": BttvModifier(code: "s!", effects: [.shake]),
        "z!": BttvModifier(code: "z!", effects: [.noSpace]),
    ]

    private static let overlayIDs: Set<String> = [
        "5e76d338d6581c3724c0f0b2",
        "5e76d399d6581c3724c0f0b8",
        "5849c9a4f52be01a7ee5f79d",
        "567b5b520e984428652809b6",
        "58487cc6f52be01a7ee5f205",
        "5849c9c8f52be01a7ee5f79e",
        "567b5c080e984428652809ba",
        "567b5dc00e984428652809bd",
    ]

    public static func modifier(for fragment: ChatFragment) -> BttvModifier? {
        guard case let .thirdPartyEmote(text, _, provider, _, _, _) = fragment,
              provider.caseInsensitiveCompare("bttv") == .orderedSame else {
            return nil
        }
        return modifiers[text]
    }

    public static func isOverlay(_ fragment: ChatFragment) -> Bool {
        guard case let .thirdPartyEmote(_, emoteID, provider, _, _, zeroWidth) = fragment else {
            return false
        }
        if provider.caseInsensitiveCompare("bttv") != .orderedSame {
            return zeroWidth
        }
        return zeroWidth || overlayIDs.contains(emoteID)
    }
}

public enum BttvEmoteCompositionPlanner {
    public static func build(fragments: [ChatFragment]) -> BttvEmoteCompositionPlan {
        guard !fragments.isEmpty else {
            return .empty
        }

        var groups: [BttvEmoteGroup] = []
        var hidden: Set<Int> = []
        var pendingEffects: Set<BttvModifierEffect> = []
        var pendingWhitespace: [Int] = []

        for (index, fragment) in fragments.enumerated() {
            if let modifier = BttvEmoteSemantics.modifier(for: fragment) {
                hidden.insert(index)
                pendingEffects.formUnion(modifier.effects)
                continue
            }

            if case let .text(text) = fragment,
               !text.isEmpty,
               text.allSatisfy({ $0.isWhitespace }),
               !pendingEffects.isEmpty {
                pendingWhitespace.append(index)
                continue
            }

            if BttvEmoteSemantics.isOverlay(fragment), !groups.isEmpty {
                let groupIndex = groups.index(before: groups.endIndex)
                let previous = groups[groupIndex]
                groups[groupIndex] = BttvEmoteGroup(
                    baseFragmentIndex: previous.baseFragmentIndex,
                    overlayFragmentIndices: previous.overlayFragmentIndices + [index],
                    effects: previous.effects
                )
                hidden.insert(index)
                continue
            }

            if fragment.isRenderableEmote {
                if !pendingEffects.isEmpty {
                    hidden.formUnion(pendingWhitespace)
                }
                groups.append(
                    BttvEmoteGroup(
                        baseFragmentIndex: index,
                        effects: pendingEffects
                    )
                )
                pendingEffects.removeAll(keepingCapacity: true)
                pendingWhitespace.removeAll(keepingCapacity: true)
                continue
            }

            pendingEffects.removeAll(keepingCapacity: true)
            pendingWhitespace.removeAll(keepingCapacity: true)
        }

        return BttvEmoteCompositionPlan(
            groups: groups,
            hiddenFragmentIndices: hidden
        )
    }
}

private extension ChatFragment {
    var isRenderableEmote: Bool {
        switch self {
        case .twitchEmote, .thirdPartyEmote, .gif, .cheermote:
            true
        case .text, .mention, .link, .unknown:
            false
        }
    }
}
