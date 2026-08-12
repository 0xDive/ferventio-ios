import FerventioDomain
import SwiftUI

struct NukePreviewView: View {
    let messages: [ChatMessage]

    @Environment(\.dismiss) private var dismiss
    @State private var config: NukePreviewConfig

    init(messages: [ChatMessage], initialQuery: String) {
        self.messages = messages
        _config = State(
            initialValue: NukePreviewConfig(
                query: String(initialQuery.prefix(NukePreviewPlanner.maximumQueryLength))
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                querySection
                matchingSection
                exclusionsSection
                summarySection
                samplesSection
                usersSection
                previewOnlySection
            }
            .navigationTitle(Text(localized("nuke.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("nuke.done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var querySection: some View {
        Section {
            TextField(
                localized("nuke.query"),
                text: $config.query,
                axis: .vertical
            )
            .lineLimit(1...3)
            .onChange(of: config.query) { _, value in
                if value.count > NukePreviewPlanner.maximumQueryLength {
                    config.query = String(value.prefix(NukePreviewPlanner.maximumQueryLength))
                }
            }
        }
    }

    private var matchingSection: some View {
        Section {
            Picker(localized("nuke.match_mode"), selection: $config.matchMode) {
                Text(localized("nuke.plain_text"))
                    .tag(NukeMatchMode.plainText)
                Text(localized("nuke.regex"))
                    .tag(NukeMatchMode.regex)
            }
            .pickerStyle(.segmented)

            Toggle(localized("nuke.case_sensitive"), isOn: $config.caseSensitive)

            Picker(localized("nuke.time_window"), selection: $config.windowMilliseconds) {
                ForEach(Self.windowPresets, id: \.self) { milliseconds in
                    Text("\(milliseconds / 1_000)s")
                        .tag(milliseconds)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(localized("nuke.matching"))
        }
    }

    private var exclusionsSection: some View {
        Section {
            Toggle(localized("nuke.exclude_broadcaster"), isOn: $config.excludeBroadcaster)
            Toggle(localized("nuke.exclude_moderators"), isOn: $config.excludeModerators)
            Toggle(localized("nuke.exclude_vips"), isOn: $config.excludeVIPs)
        } header: {
            Text(localized("nuke.exclusions"))
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            switch previewResult {
            case let .failure(error):
                Text(errorMessage(error))
                    .foregroundStyle(.red)

            case let .success(preview):
                LabeledContent(
                    localized("nuke.matched_messages"),
                    value: preview.matchedMessageCount.formatted()
                )
                LabeledContent(
                    localized("nuke.matched_users"),
                    value: preview.matchedUserCount.formatted()
                )
                if preview.excludedMatchCount > 0 {
                    LabeledContent(
                        localized("nuke.excluded_matches"),
                        value: preview.excludedMatchCount.formatted()
                    )
                }
                if preview.matchedMessageCount == 0 {
                    Text(localized("nuke.no_matches"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(localized("nuke.summary"))
        }
    }

    @ViewBuilder
    private var samplesSection: some View {
        if let preview = previewResult.preview, !preview.samples.isEmpty {
            Section {
                ForEach(preview.samples) { sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.userDisplayName.isEmpty ? sample.userLogin : sample.userDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(sample.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(localized("nuke.samples"))
            }
        }
    }

    @ViewBuilder
    private var usersSection: some View {
        if let preview = previewResult.preview, !preview.matchedUsers.isEmpty {
            Section {
                ForEach(preview.matchedUsers) { user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.userDisplayName.isEmpty ? user.userLogin : user.userDisplayName)
                            .font(.subheadline.weight(.semibold))
                        if !user.userLogin.isEmpty {
                            Text("@\(user.userLogin)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(localized("nuke.target_users"))
            }
        }
    }

    private var previewOnlySection: some View {
        Section {
            Label(localized("nuke.preview_only"), systemImage: "shield.lefthalf.filled")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var previewResult: NukePreviewResult {
        NukePreviewPlanner.build(
            messages: messages,
            config: config,
            nowMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    private func errorMessage(_ error: NukePreviewError) -> String {
        switch error {
        case .emptyQuery:
            localized("nuke.error.empty_query")
        case .queryTooLong:
            localized("nuke.error.query_too_long")
        case .invalidRegularExpression:
            localized("nuke.error.invalid_regex")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Moderation")
    }

    private static let windowPresets: [Int64] = [10_000, 30_000, 60_000]
}
