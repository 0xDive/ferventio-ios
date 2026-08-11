import SwiftUI

struct ChatHistorySettingsView: View {
    let save: (ChatHistoryPreferences) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recentMessagesEnabled: Bool
    @State private var localHistoryEnabled: Bool
    @State private var localHistoryLimit: Int
    @State private var retentionDays: Int
    @State private var maxDatabaseSizeMB: Int
    @State private var isSaving = false

    init(
        preferences: ChatHistoryPreferences,
        save: @escaping (ChatHistoryPreferences) async -> Void
    ) {
        self.save = save
        _recentMessagesEnabled = State(initialValue: preferences.recentMessagesEnabled)
        _localHistoryEnabled = State(initialValue: preferences.localHistoryEnabled)
        _localHistoryLimit = State(initialValue: preferences.localHistoryLimit)
        _retentionDays = State(initialValue: preferences.retentionDays)
        _maxDatabaseSizeMB = State(initialValue: preferences.maxDatabaseSizeMB)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        localized("chat_history.recent_messages"),
                        isOn: $recentMessagesEnabled
                    )
                } footer: {
                    Text(localized("chat_history.recent_messages.footer"))
                }

                Section {
                    Toggle(
                        localized("chat_history.local_history"),
                        isOn: $localHistoryEnabled
                    )

                    if localHistoryEnabled {
                        Stepper(
                            value: $localHistoryLimit,
                            in: ChatHistoryPreferences.minimumLocalHistoryLimit
                                ...ChatHistoryPreferences.maximumLocalHistoryLimit,
                            step: 100
                        ) {
                            settingValueRow(
                                title: localized("chat_history.message_limit"),
                                value: localHistoryLimit.formatted()
                            )
                        }

                        Stepper(
                            value: $retentionDays,
                            in: 0...ChatHistoryPreferences.maximumRetentionDays
                        ) {
                            settingValueRow(
                                title: localized("chat_history.retention_days"),
                                value: retentionDays == 0
                                    ? localized("unlimited")
                                    : retentionDays.formatted()
                            )
                        }

                        Stepper(
                            value: $maxDatabaseSizeMB,
                            in: 0...ChatHistoryPreferences.maximumDatabaseSizeMB,
                            step: 64
                        ) {
                            settingValueRow(
                                title: localized("chat_history.database_limit"),
                                value: maxDatabaseSizeMB == 0
                                    ? localized("unlimited")
                                    : maxDatabaseSizeMB.formatted()
                            )
                        }
                    }
                } header: {
                    Text(localized("chat_history.local_section"))
                } footer: {
                    Text(localized("chat_history.local_history.footer"))
                }
            }
            .navigationTitle(Text(localized("chat_history.title")))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("cancel")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("done")) {
                        Task {
                            isSaving = true
                            await save(currentPreferences)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var currentPreferences: ChatHistoryPreferences {
        ChatHistoryPreferences(
            recentMessagesEnabled: recentMessagesEnabled,
            localHistoryEnabled: localHistoryEnabled,
            localHistoryLimit: localHistoryLimit,
            retentionDays: retentionDays,
            maxDatabaseSizeMB: maxDatabaseSizeMB
        )
    }

    private func settingValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Settings")
    }
}
