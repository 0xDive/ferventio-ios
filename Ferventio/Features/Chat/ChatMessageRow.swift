import FerventioDomain
import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage
    let badgeAssets: [String: ChatBadgeAsset]
    let onOpenUserCard: () -> Void
    let onReply: () -> Void
    let onPreviewNuke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reply = message.reply,
               let parentName = reply.parentUserName ?? reply.parentUserLogin {
                Text("↪ \(parentName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                ForEach(resolvedBadges) { asset in
                    if let url = ChatAssetResolver.preferredBadgeImageURL(asset) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(Text(asset.title ?? asset.setID))
                    }
                }

                Button(action: onOpenUserCard) {
                    Text(message.author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorColor)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    Text(String(localized: "user_card.open", table: "UserCard"))
                )

                Spacer(minLength: 4)

                outgoingIndicator
            }

            ChatFragmentFlow(fragments: message.fragments)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                onOpenUserCard()
            } label: {
                Label(
                    String(localized: "user_card.open", table: "UserCard"),
                    systemImage: "person.crop.circle"
                )
            }

            Button {
                onReply()
            } label: {
                Label("chat.reply", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(message.outgoingState == .sending || message.outgoingState == .failed)

            Button {
                onPreviewNuke()
            } label: {
                Label(
                    String(localized: "nuke.preview", table: "Moderation"),
                    systemImage: "shield.lefthalf.filled"
                )
            }
        }
    }

    private var resolvedBadges: [ChatBadgeAsset] {
        message.author.badges.compactMap {
            ChatAssetResolver.badgeAsset(for: $0, assets: badgeAssets)
        }
    }

    private var authorColor: Color {
        Color(twitchHex: message.author.color) ?? .primary
    }

    @ViewBuilder
    private var outgoingIndicator: some View {
        switch message.outgoingState {
        case .sending:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel(Text("chat.message.sending"))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel(Text("chat.message.failed"))
        case .none, .sent:
            EmptyView()
        }
    }
}

private struct ChatFragmentFlow: View {
    let fragments: [ChatFragment]

    var body: some View {
        let composition = BttvEmoteCompositionPlanner.build(fragments: fragments)
        ChatFlowLayout(spacing: 3) {
            ForEach(fragments.indices, id: \.self) { index in
                if !composition.hiddenFragmentIndices.contains(index) {
                    if let group = composition.group(forBaseFragment: index) {
                        BttvComposedEmoteView(
                            base: fragments[index],
                            overlays: group.overlayFragmentIndices.compactMap { overlayIndex in
                                fragments.indices.contains(overlayIndex) ? fragments[overlayIndex] : nil
                            },
                            effects: group.effects
                        )
                    } else {
                        ChatFragmentView(fragment: fragments[index])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BttvComposedEmoteView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let base: ChatFragment
    let overlays: [ChatFragment]
    let effects: Set<BttvModifierEffect>

    var body: some View {
        if !reduceMotion && (effects.contains(.party) || FfzModifierVisualEffects.needsAnimation(effects)) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                styledStack(at: context.date)
            }
        } else {
            styledStack(at: nil)
        }
    }

    private func styledStack(at date: Date?) -> some View {
        let rotated = effects.contains(.rotateLeft) || effects.contains(.rotateRight)
        let wide = effects.contains(.wide) && !rotated
        let flipX = effects.contains(.flipX)
        let flipY = effects.contains(.flipY)
        let noSpace = effects.contains(.noSpace)
        let cursed = effects.contains(.cursed)
        let party = effects.contains(.party)
        let visualState = date.map {
            FfzModifierVisualEffects.state(effects: effects, at: $0)
        } ?? .identity
        let xScale: CGFloat = (wide ? 4 : 1)
            * (flipX ? -1 : 1)
            * visualState.scaleX
        let yScale: CGFloat = (flipY ? -1 : 1) * visualState.scaleY
        let rotation = rotationDegrees + visualState.rotationDegrees
        let width: CGFloat = wide ? 112 : 28
        let layoutWidth = max(1, width - (noSpace ? 4 : 0))
        let scaleAnchor: UnitPoint = visualState.usesBottomAnchor ? .bottom : .center

        return ZStack {
            ChatFragmentView(fragment: base)
            ForEach(Array(overlays.enumerated()), id: \.offset) { _, overlay in
                ChatFragmentView(fragment: overlay)
            }
        }
        .scaleEffect(x: xScale, y: yScale, anchor: scaleAnchor)
        .rotationEffect(.degrees(rotation))
        .grayscale(cursed ? 1 : 0)
        .brightness(cursed ? -0.3 : 0)
        .contrast(cursed ? 2.5 : 1)
        .saturation(party ? 2.5 : 1)
        .hueRotation(.degrees(partyHue(at: date) + visualState.hueRotationDegrees))
        .offset(
            x: visualState.offsetX - (noSpace ? 4 : 0),
            y: visualState.offsetY
        )
        .frame(width: layoutWidth, height: 28)
        .accessibilityElement(children: .combine)
    }

    private var rotationDegrees: Double {
        var degrees: Double = 0
        if effects.contains(.rotateLeft) {
            degrees -= 90
        }
        if effects.contains(.rotateRight) {
            degrees += 90
        }
        return degrees
    }

    private func partyHue(at date: Date?) -> Double {
        guard effects.contains(.party), let date else {
            return 0
        }
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.5)
        return (cycle / 1.5) * 360
    }
}

private struct ChatFragmentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fragment: ChatFragment

    var body: some View {
        switch fragment {
        case let .text(text):
            Text(text)
                .font(.body)
                .textSelection(.enabled)

        case let .twitchEmote(text, emoteID, _, _, formats):
            RemoteChatImage(
                url: ChatAssetResolver.twitchEmoteURL(
                    emoteID: emoteID,
                    formats: formats,
                    animate: !reduceMotion,
                    scale: .medium
                ),
                fallbackText: text,
                accessibilityLabel: text
            )

        case let .thirdPartyEmote(text, _, _, _, imageURL, _):
            RemoteChatImage(
                url: ChatAssetResolver.absoluteImageURL(imageURL),
                fallbackText: text,
                accessibilityLabel: text
            )

        case let .gif(text, _, url):
            RemoteChatImage(
                url: ChatAssetResolver.absoluteImageURL(url),
                fallbackText: text,
                accessibilityLabel: text
            )

        case let .mention(text, _, _, _):
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .textSelection(.enabled)

        case let .cheermote(text, _, _, _):
            Text(text)
                .font(.body.weight(.semibold))
                .textSelection(.enabled)

        case let .link(text, url):
            if let destination = URL(string: url) {
                Link(text, destination: destination)
                    .font(.body)
            } else {
                Text(text)
                    .font(.body)
            }

        case let .unknown(text, _):
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

private struct RemoteChatImage: View {
    let url: URL?
    let fallbackText: String
    let accessibilityLabel: String

    @State private var asset: ChatImageAsset?
    @State private var loadedURL: URL?
    @State private var failedURL: URL?

    var body: some View {
        Group {
            if let url, loadedURL == url, let asset {
                ChatUIImageView(image: asset.image)
            } else if let url, failedURL != url {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text(fallbackText)
                    .font(.body)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel(Text(accessibilityLabel))
        .task(id: url) {
            asset = nil
            loadedURL = nil
            failedURL = nil
            guard let url else {
                return
            }
            if let image = await ChatImagePipeline.shared.image(for: url), !Task.isCancelled {
                asset = image
                loadedURL = url
            } else if !Task.isCancelled {
                failedURL = url
            }
        }
    }
}

private struct ChatFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentWidth: CGFloat = 0
        var maximumWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let additionalWidth = currentWidth == 0 ? size.width : spacing + size.width
            if currentWidth > 0 && currentWidth + additionalWidth > maxWidth {
                maximumWidth = max(maximumWidth, currentWidth)
                totalHeight += currentRowHeight + spacing
                currentWidth = size.width
                currentRowHeight = size.height
            } else {
                currentWidth += additionalWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        maximumWidth = max(maximumWidth, currentWidth)
        totalHeight += currentRowHeight
        let resolvedWidth = proposal.width.map { min($0, maximumWidth) } ?? maximumWidth
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let nextX = x == bounds.minX ? x + size.width : x + spacing + size.width
            if x > bounds.minX && nextX > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension Color {
    init?(twitchHex: String?) {
        guard var hex = twitchHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
