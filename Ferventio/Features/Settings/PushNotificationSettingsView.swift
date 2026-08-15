import FerventioDomain
import SwiftUI

struct PushNotificationSettingsView: View {
    @Bindable var coordinator: PushNotificationCoordinator
    let grant: AuthenticationGrant?
    let channelLogins: [String]

    var body: some View {
        Form {
            Section {
                Toggle(
                    localized("enabled"),
                    isOn: enabledBinding
                )
                .disabled(coordinator.isWorking || grant == nil)

                if coordinator.preferences.enabled {
                    Toggle(
                        localized("replies_mentions"),
                        isOn: categoryBinding(\.repliesAndMentions)
                    )
                    Toggle(
                        localized("moderation"),
                        isOn: categoryBinding(\.moderation)
                    )
                    Toggle(
                        localized("channel_activity"),
                        isOn: categoryBinding(\.channelActivity)
                    )
                }
            } header: {
                Text(localized("delivery.section"))
            } footer: {
                Text(localized("delivery.footer"))
            }

            if coordinator.preferences.enabled {
                Section {
                    HStack {
                        Label(
                            coordinator.isTransportRegistered
                                ? localized("transport.ready")
                                : localized("transport.waiting"),
                            systemImage: coordinator.isTransportRegistered
                                ? "checkmark.circle"
                                : "clock"
                        )
                        Spacer(minLength: 12)
                        if coordinator.isWorking {
                            ProgressView()
                        }
                    }

                    Button {
                        Task { await coordinator.sendSelfTest() }
                    } label: {
                        Label(localized("self_test"), systemImage: "bell.badge")
                    }
                    .disabled(
                        coordinator.isWorking || !coordinator.isTransportRegistered
                    )

                    if coordinator.selfTestSucceeded == true {
                        Label(
                            localized("self_test.sent"),
                            systemImage: "checkmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(localized("status.section"))
                } footer: {
                    Text(localized("status.footer"))
                }
            }

            if let errorMessage = coordinator.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text(localized("title")))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.preferences.enabled },
            set: { enabled in
                Task {
                    if enabled {
                        _ = await coordinator.enable(
                            grant: grant,
                            channelLogins: channelLogins
                        )
                    } else {
                        await coordinator.disable()
                    }
                }
            }
        )
    }

    private func categoryBinding(
        _ keyPath: KeyPath<PushNotificationPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { coordinator.preferences[keyPath: keyPath] },
            set: { newValue in
                var repliesAndMentions = coordinator.preferences.repliesAndMentions
                var moderation = coordinator.preferences.moderation
                var channelActivity = coordinator.preferences.channelActivity
                if keyPath == \.repliesAndMentions {
                    repliesAndMentions = newValue
                } else if keyPath == \.moderation {
                    moderation = newValue
                } else {
                    channelActivity = newValue
                }
                Task {
                    await coordinator.updateCategories(
                        repliesAndMentions: repliesAndMentions,
                        moderation: moderation,
                        channelActivity: channelActivity,
                        grant: grant,
                        channelLogins: channelLogins
                    )
                }
            }
        )
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "PushNotifications")
    }
}
