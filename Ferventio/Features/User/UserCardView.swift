import Foundation
import FerventioDomain
import SwiftUI

struct UserCardView: View {
    let author: ChatAuthor
    let messages: [ChatMessage]
    let loadProfile: () async -> TwitchUser?

    @Environment(\.dismiss) private var dismiss
    @State private var profile: TwitchUser?
    @State private var didFinishProfileLoad = false

    var body: some View {
        NavigationStack {
            List {
                identitySection
                rolesAndBadgesSection
                twitchProfileSection
                chatContextSection
                recentMessagesSection
            }
            .navigationTitle(Text(localized("user_card.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("user_card.done")) {
                        dismiss()
                    }
                }
            }
            .task(id: author.id + ":" + author.login) {
                didFinishProfileLoad = false
                profile = await loadProfile()
                didFinishProfileLoad = true
            }
        }
    }

    private var identitySection: some View {
        Section {
            HStack(spacing: 14) {
                profileImage

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.displayName ?? author.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text("@\(profile?.login ?? author.login)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var rolesAndBadgesSection: some View {
        if !roleBadgeSetIDs.isEmpty || !author.badges.isEmpty {
            Section {
                if !roleBadgeSetIDs.isEmpty {
                    LabeledContent(localized("user_card.roles")) {
                        Text(roleBadgeSetIDs.map(roleName).joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                }

                ForEach(Array(author.badges.enumerated()), id: \.offset) { _, badge in
                    HStack {
                        Text(badge.setID)
                        Spacer(minLength: 12)
                        Text(badge.info?.isEmpty == false ? badge.info! : badge.id)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } header: {
                Text(localized("user_card.badges"))
            }
        }
    }

    @ViewBuilder
    private var twitchProfileSection: some View {
        Section {
            if let profile {
                if let createdAt = formattedCreatedAt(profile.createdAt) {
                    LabeledContent(localized("user_card.account_created"), value: createdAt)
                }
                if let broadcasterType = nonEmpty(profile.broadcasterType) {
                    LabeledContent(
                        localized("user_card.broadcaster_type"),
                        value: broadcasterType
                    )
                }
                if let description = nonEmpty(profile.description) {
                    Text(description)
                        .font(.body)
                        .textSelection(.enabled)
                }
            } else if didFinishProfileLoad {
                Label(
                    localized("user_card.profile_unavailable"),
                    systemImage: "wifi.exclamationmark"
                )
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    ProgressView()
                    Text(localized("user_card.loading_profile"))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(localized("user_card.twitch_profile"))
        }
    }

    private var chatContextSection: some View {
        Section {
            LabeledContent(
                localized("user_card.loaded_messages"),
                value: matchingMessages.count.formatted()
            )
            if let first = matchingMessages.first {
                LabeledContent(
                    localized("user_card.first_loaded_message"),
                    value: formattedMessageTime(first.timestampMilliseconds)
                )
            }
            if let last = matchingMessages.last, matchingMessages.count > 1 {
                LabeledContent(
                    localized("user_card.latest_message"),
                    value: formattedMessageTime(last.timestampMilliseconds)
                )
            }
        } header: {
            Text(localized("user_card.chat_context"))
        }
    }

    @ViewBuilder
    private var recentMessagesSection: some View {
        if !recentMessages.isEmpty {
            Section {
                ForEach(recentMessages) { message in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.text)
                            .font(.body)
                            .textSelection(.enabled)
                        Text(formattedMessageTime(message.timestampMilliseconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(localized("user_card.recent_messages"))
            }
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let rawURL = profile?.profileImageURL ?? author.profileImageURL,
           let url = URL(string: rawURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
        }
    }

    private var matchingMessages: [ChatMessage] {
        UserCardContext.messages(for: author, in: messages)
    }

    private var recentMessages: [ChatMessage] {
        UserCardContext.recentMessages(for: author, in: messages)
    }

    private var roleBadgeSetIDs: [String] {
        UserCardContext.protectedRoleBadgeSetIDs(for: author)
    }

    private func roleName(_ role: String) -> String {
        switch role {
        case "broadcaster": localized("user_card.role.broadcaster")
        case "moderator": localized("user_card.role.moderator")
        case "vip": localized("user_card.role.vip")
        default: role
        }
    }

    private func formattedCreatedAt(_ rawValue: String?) -> String? {
        guard let rawValue = nonEmpty(rawValue),
              let date = ISO8601DateFormatter().date(from: rawValue) else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedMessageTime(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "UserCard")
    }
}
