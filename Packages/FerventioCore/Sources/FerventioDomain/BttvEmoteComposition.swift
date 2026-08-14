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
    case growX
    case slide
    case appear
    case leave
    case rotate
    case rotate90
    case greyscale
    case sepia
    case rainbow
    case hyperRed
    case jam
    case bounce
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

    public init(groups: [BttvEmoteGroup], hiddenFragmentIndices: Set<Int>) {
        self.groups = groups
        self.hiddenFragmentIndices = hiddenFragmentIndices
    }

    public func group(forBaseFragment index: Int) -> BttvEmoteGroup? {
        groups.first { $0.baseFragmentIndex == index }
    }

    public static let empty = BttvEmoteCompositionPlan(groups: [], hiddenFragmentIndices: [])
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
        "5e76d338d6581c3724c0f0b2", "5e76d399d6581c3724c0f0b8",
        "5849c9a4f52be01a7ee5f79d", "567b5b520e984428652809b6",
        "58487cc6f52be01a7ee5f205", "5849c9c8f52be01a7ee5f79e",
        "567b5c080e984428652809ba", "567b5dc00e984428652809bd",
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
        if FfzModifierFragmentMetadata.parse(provider: provider) != nil {
            return false
        }
        if provider.caseInsensitiveCompare("bttv") != .orderedSame {
            return zeroWidth
        }
        return zeroWidth || overlayIDs.contains(emoteID)
    }
}

public enum FfzModifierSemantics {
    public static let hidden = 1 << 0
    public static let noSpace = 1 << 17

    public static func metadata(for fragment: ChatFragment) -> (prefix: Bool, flags: Int)? {
        guard case let .thirdPartyEmote(_, _, provider, _, _, _) = fragment else {
            return nil
        }
        return FfzModifierFragmentMetadata.parse(provider: provider)
    }

    public static func effects(flags: Int) -> Set<BttvModifierEffect> {
        var result: Set<BttvModifierEffect> = []
        let mapping: [(Int, BttvModifierEffect)] = [
            (1 << 1, .flipX), (1 << 2, .flipY), (1 << 3, .growX),
            (1 << 4, .slide), (1 << 5, .appear), (1 << 6, .leave),
            (1 << 7, .rotate), (1 << 8, .rotate90), (1 << 9, .greyscale),
            (1 << 10, .sepia), (1 << 11, .rainbow), (1 << 12, .hyperRed),
            (1 << 13, .shake), (1 << 14, .cursed), (1 << 15, .jam),
            (1 << 16, .bounce), (1 << 17, .noSpace),
        ]
        for (flag, effect) in mapping where flags & flag != 0 {
            result.insert(effect)
        }
        return result
    }
}

public enum BttvEmoteCompositionPlanner {
    public static func build(fragments: [ChatFragment]) -> BttvEmoteCompositionPlan {
        guard !fragments.isEmpty else { return .empty }

        var groups: [BttvEmoteGroup] = []
        var hidden: Set<Int> = []
        var pendingEffects: Set<BttvModifierEffect> = []
        var pendingWhitespace: [Int] = []
        var pendingFfz: [(index: Int, flags: Int)] = []
        var pendingFfzWhitespace: [Int] = []
        var suffixWhitespace: [Int] = []

        for (index, fragment) in fragments.enumerated() {
            if let modifier = BttvEmoteSemantics.modifier(for: fragment) {
                hidden.insert(index)
                pendingEffects.formUnion(modifier.effects)
                suffixWhitespace.removeAll(keepingCapacity: true)
                continue
            }

            if let metadata = FfzModifierSemantics.metadata(for: fragment) {
                let effects = FfzModifierSemantics.effects(flags: metadata.flags)
                if metadata.prefix {
                    pendingFfz.append((index, metadata.flags))
                    pendingEffects.formUnion(effects)
                } else if !groups.isEmpty {
                    let groupIndex = groups.index(before: groups.endIndex)
                    let previous = groups[groupIndex]
                    let showModifier = metadata.flags & FfzModifierSemantics.hidden == 0
                    groups[groupIndex] = BttvEmoteGroup(
                        baseFragmentIndex: previous.baseFragmentIndex,
                        overlayFragmentIndices: previous.overlayFragmentIndices + (showModifier ? [index] : []),
                        effects: previous.effects.union(effects)
                    )
                    hidden.insert(index)
                    hidden.formUnion(suffixWhitespace)
                }
                suffixWhitespace.removeAll(keepingCapacity: true)
                continue
            }

            if case let .text(text) = fragment,
               !text.isEmpty,
               text.allSatisfy({ $0.isWhitespace }) {
                if !pendingEffects.isEmpty { pendingWhitespace.append(index) }
                if !pendingFfz.isEmpty { pendingFfzWhitespace.append(index) }
                if !groups.isEmpty { suffixWhitespace.append(index) }
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
                suffixWhitespace.removeAll(keepingCapacity: true)
                continue
            }

            if fragment.isRenderableEmote {
                if !pendingEffects.isEmpty { hidden.formUnion(pendingWhitespace) }
                if !pendingFfz.isEmpty {
                    hidden.formUnion(pendingFfz.map(\.index))
                    hidden.formUnion(pendingFfzWhitespace)
                }
                let visibleFfz = pendingFfz.compactMap { item in
                    item.flags & FfzModifierSemantics.hidden == 0 ? item.index : nil
                }
                groups.append(BttvEmoteGroup(
                    baseFragmentIndex: index,
                    overlayFragmentIndices: visibleFfz,
                    effects: pendingEffects
                ))
                pendingEffects.removeAll(keepingCapacity: true)
                pendingWhitespace.removeAll(keepingCapacity: true)
                pendingFfz.removeAll(keepingCapacity: true)
                pendingFfzWhitespace.removeAll(keepingCapacity: true)
                suffixWhitespace.removeAll(keepingCapacity: true)
                continue
            }

            pendingEffects.removeAll(keepingCapacity: true)
            pendingWhitespace.removeAll(keepingCapacity: true)
            pendingFfz.removeAll(keepingCapacity: true)
            pendingFfzWhitespace.removeAll(keepingCapacity: true)
            suffixWhitespace.removeAll(keepingCapacity: true)
        }

        return BttvEmoteCompositionPlan(groups: groups, hiddenFragmentIndices: hidden)
    }
}

private extension ChatFragment {
    var isRenderableEmote: Bool {
        switch self {
        case .twitchEmote, .thirdPartyEmote, .gif, .cheermote: true
        case .text, .mention, .link, .unknown: false
        }
    }
}
