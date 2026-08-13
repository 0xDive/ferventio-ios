import FerventioDomain
import SwiftUI

struct RootView: View {
    @Bindable var environment: AppEnvironment
    @State private var showsChatHistorySettings = false
    @State private var showsInteractiveManagement = false

    var body: some View {
        NavigationStack {
            Group {
                switch environment.state {
                case .launching:
                    ProgressView()
                case .signedOut:
                    signedOutView
                case .signedIn:
                    signedInView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("app.title"))
        }
        .alert(
            String(localized: "auth.error.title"),
            isPresented: $environment.showsAuthenticationError
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("auth.error.message")
        }
        .sheet(isPresented: $showsChatHistorySettings) {
            ChatHistorySettingsView(
                preferences: environment.chatHistoryPreferences(),
                presentationPreferences: environment.chatPresentationPreferences
            ) { preferences, presentationPreferences in
                _ = await environment.updateChatHistoryPreferences(preferences)
                _ = environment.updateChatPresentationPreferences(presentationPreferences)
            }
        }
        .sheet(isPresented: $showsInteractiveManagement) {
            InteractiveChatManagementView(
                poll: currentPoll,
                prediction: currentPrediction,
                canManagePolls: environment.canManagePolls,
                canManagePredictions: environment.canManagePredictions,
                mutationStore: environment.interactiveMutationStore,
                createPoll: { draft in
                    await environment.createPoll(draft)
                },
                createPrediction: { draft in
                    await environment.createPrediction(draft)
                },
                endPoll: { poll, status in
                    await environment.endPoll(poll, status: status)
                },
                endPrediction: { prediction, status, winningOutcomeID in
                    await environment.endPrediction(
                        prediction,
                        status: status,
                        winningOutcomeID: winningOutcomeID
                    )
                }
            )
        }
    }

    private var signedOutView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                String(localized: "auth.signed_out.title"),
                systemImage: "bubble.left.and.bubble.right",
                description: Text("auth.signed_out.message")
            )
            Button {
                Task { await environment.signIn() }
            } label: {
                if environment.isAuthorizing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("auth.sign_in")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(environment.isAuthorizing)
            .padding(.horizontal, 32)
        }
    }

    private var signedInView: some View {
        VStack(spacing: 0) {
            accountHeader
            Divider()
            ChatView(
                store: environment.chatStore,
                assets: environment.chatAssetStore,
                historyPager: environment.chatHistoryPager,
                repeatCollapseEnabled: environment.chatPresentationPreferences.repeatCollapseEnabled,
                canExecuteNuke: environment.canExecuteNuke,
                loadUserProfile: { author in
                    await environment.loadUserProfile(for: author)
                },
                canTimeoutUser: { author in
                    environment.canTimeoutUser(author)
                },
                timeoutUser: { author in
                    try await environment.timeoutUserFromCard(author)
                },
                executeNuke: { plan in
                    try await environment.executeNuke(plan: plan)
                }
            ) {
                await environment.connectChat()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canOpenInteractiveManagement {
                    Button {
                        showsInteractiveManagement = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .accessibilityLabel(Text(interactiveLocalized("interactive.manage.title")))
                    }
                }

                Button {
                    showsChatHistorySettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel(Text(settingsLocalized("open")))
                }

                Button("auth.sign_out", role: .destructive) {
                    Task { await environment.signOut() }
                }
                .disabled(environment.isSigningOut)
            }
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 10) {
            profileImage
            VStack(alignment: .leading, spacing: 1) {
                Text(environment.currentUser?.displayName ?? environment.session?.login ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let login = environment.session?.login {
                    Text("@\(login)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let rawURL = environment.currentUser?.profileImageURL,
           let url = URL(string: rawURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 30))
                .accessibilityHidden(true)
        }
    }

    private var currentPoll: PollOverlay? {
        guard let channelID = environment.chatStore.channel?.id else {
            return nil
        }
        return environment.chatStore.interactiveOverlayState.pollsByChannel[channelID]
    }

    private var currentPrediction: PredictionOverlay? {
        guard let channelID = environment.chatStore.channel?.id else {
            return nil
        }
        return environment.chatStore.interactiveOverlayState.predictionsByChannel[channelID]
    }

    private var canOpenInteractiveManagement: Bool {
        environment.canManagePolls || environment.canManagePredictions
    }

    private func settingsLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Settings")
    }

    private func interactiveLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "InteractiveChat")
    }
}
