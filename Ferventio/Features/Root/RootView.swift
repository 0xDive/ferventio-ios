import FerventioDomain
import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var environment: AppEnvironment
    @State private var showsChatHistorySettings = false
    @State private var showsInteractiveManagement = false
    @State private var showsNewWorkspace = false
    @State private var showsWorkspaceLimit = false
    @State private var showsLiveWorkspaceLimit = false
    @State private var newWorkspaceLogin = ""
    @State private var workspaceRegistry = ChatWorkspaceRegistryStore()
    @State private var workspaceRuntimePool = ChatWorkspaceRuntimePool(
        historyPreferences: .default
    )

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
        .alert(
            String(localized: "chat.workspace.new.title"),
            isPresented: $showsNewWorkspace
        ) {
            TextField("chat.channel.placeholder", text: $newWorkspaceLogin)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("chat.workspace.cancel", role: .cancel) {}
            Button("chat.workspace.open") {
                openWorkspace()
            }
            .disabled(ChatWorkspaceRegistryStore.normalizedLogin(newWorkspaceLogin) == nil)
        } message: {
            Text("chat.workspace.new.message")
        }
        .alert(
            String(localized: "chat.workspace.limit.title"),
            isPresented: $showsWorkspaceLimit
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("chat.workspace.limit.message")
        }
        .alert(
            String(localized: "chat.workspace.live_limit.title"),
            isPresented: $showsLiveWorkspaceLimit
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("chat.workspace.live_limit.message")
        }
        .sheet(isPresented: $showsChatHistorySettings) {
            ChatHistorySettingsView(
                preferences: environment.chatHistoryPreferences(),
                presentationPreferences: environment.chatPresentationPreferences,
                workspaceSnapshot: workspaceSnapshot,
                save: { preferences, presentationPreferences in
                    let saved = await environment.updateChatHistoryPreferences(preferences)
                    await workspaceRuntimePool.updateHistoryPreferences(saved)
                    _ = environment.updateChatPresentationPreferences(presentationPreferences)
                },
                applyWorkspaceImport: { plan in
                    await applyWorkspaceImport(plan)
                }
            )
        }
        .sheet(isPresented: $showsInteractiveManagement) {
            if let runtime = activeWorkspaceRuntime {
                InteractiveChatManagementView(
                    poll: currentPoll(in: runtime),
                    prediction: currentPrediction(in: runtime),
                    canManagePolls: environment.canManagePolls(in: runtime),
                    canManagePredictions: environment.canManagePredictions(in: runtime),
                    mutationStore: runtime.interactiveMutationStore,
                    createPoll: { draft in
                        await environment.createPoll(draft, in: runtime)
                    },
                    createPrediction: { draft in
                        await environment.createPrediction(draft, in: runtime)
                    },
                    endPoll: { poll, status in
                        await environment.endPollAndReconcile(
                            poll,
                            status: status,
                            in: runtime
                        )
                    },
                    endPrediction: { prediction, status, winningOutcomeID in
                        await environment.endPredictionAndReconcile(
                            prediction,
                            status: status,
                            winningOutcomeID: winningOutcomeID,
                            in: runtime
                        )
                    }
                )
            }
        }
        .onChange(of: environment.session?.userID, initial: true) { _, userID in
            guard userID != nil else {
                return
            }
            Task { await prepareWorkspaceRuntimes() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard environment.state == .signedIn else {
                return
            }
            switch phase {
            case .background:
                Task { await workspaceRuntimePool.suspendAll() }
            case .active:
                Task { await workspaceRuntimePool.resumeAll() }
            case .inactive:
                break
            @unknown default:
                break
            }
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
            .accessibilityLabel(Text("auth.sign_in"))
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(environment.isAuthorizing)
            .padding(.horizontal, 32)
        }
    }

    private var signedInView: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWorkspaceLayout
            } else {
                compactWorkspaceLayout
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
                .keyboardShortcut(",", modifiers: .command)

                Button("auth.sign_out", role: .destructive) {
                    Task {
                        await workspaceRuntimePool.removeAll()
                        await environment.signOut()
                    }
                }
                .disabled(environment.isSigningOut)
            }
        }
    }

    private var compactWorkspaceLayout: some View {
        VStack(spacing: 0) {
            accountHeader
            Divider()
            workspaceBar
            Divider()
            workspaceContent
        }
    }

    private var regularWorkspaceLayout: some View {
        HStack(spacing: 0) {
            workspaceSidebar
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
            Divider()
            workspaceContent
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if let runtime = activeWorkspaceRuntime {
            workspaceChat(runtime)
        } else {
            emptyWorkspaceView
        }
    }

    private var workspaceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(workspaceRegistry.workspaces) { workspace in
                    workspaceChip(workspace)
                }

                Button {
                    presentNewWorkspace()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(Text("chat.workspace.add"))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            accountHeader
            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(workspaceRegistry.workspaces) { workspace in
                        workspaceSidebarRow(workspace)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            Divider()
            Button {
                presentNewWorkspace()
            } label: {
                Label("chat.workspace.add", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func workspaceSidebarRow(_ workspace: ChatWorkspace) -> some View {
        let isActive = workspaceRegistry.activeWorkspaceID == workspace.id
        return HStack(spacing: 8) {
            Button {
                selectWorkspace(workspace)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isActive ? "number.circle.fill" : "number.circle")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Text(workspace.login)
                        .font(.body.weight(isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("#\(workspace.login)"))
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Button(role: .destructive) {
                closeWorkspace(workspace)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .accessibilityLabel(Text("chat.workspace.close"))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 4)
        .background(
            isActive ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contextMenu {
            Button(role: .destructive) {
                closeWorkspace(workspace)
            } label: {
                Label("chat.workspace.close", systemImage: "xmark")
            }
        }
    }

    private func workspaceChip(_ workspace: ChatWorkspace) -> some View {
        let isActive = workspaceRegistry.activeWorkspaceID == workspace.id
        return HStack(spacing: 5) {
            Button {
                selectWorkspace(workspace)
            } label: {
                Text("#\(workspace.login)")
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])

            if isActive {
                Button(role: .destructive) {
                    closeWorkspace(workspace)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityLabel(Text("chat.workspace.close"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .contextMenu {
            Button(role: .destructive) {
                closeWorkspace(workspace)
            } label: {
                Label("chat.workspace.close", systemImage: "xmark")
            }
        }
    }

    private func workspaceChat(_ runtime: ChatWorkspaceRuntime) -> some View {
        ChatView(
            store: runtime.chatStore,
            assets: runtime.chatAssetStore,
            historyPager: runtime.chatHistoryPager,
            composerStore: runtime.chatComposerStore,
            workspaceLogin: runtime.workspace.login,
            repeatCollapseEnabled: environment.chatPresentationPreferences.repeatCollapseEnabled,
            presentationRules: environment.chatPresentationPreferences.rules,
            canExecuteNuke: environment.canExecuteNuke(in: runtime),
            loadUserProfile: { author in
                await environment.loadUserProfile(for: author)
            },
            canTimeoutUser: { author in
                environment.canTimeoutUser(author, in: runtime)
            },
            timeoutUser: { author in
                try await environment.timeoutUserFromCard(author, in: runtime)
            },
            executeNuke: { plan in
                try await environment.executeNuke(plan: plan, in: runtime)
            }
        ) {
            await connectWorkspace(runtime)
        }
    }

    private var emptyWorkspaceView: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                String(localized: "chat.workspace.empty.title"),
                systemImage: "rectangle.stack.badge.plus",
                description: Text("chat.workspace.empty.message")
            )
            Button("chat.workspace.add") {
                presentNewWorkspace()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 30))
                .accessibilityHidden(true)
        }
    }

    private var workspaceSnapshot: ChatWorkspaceRegistrySnapshot {
        ChatWorkspaceRegistrySnapshot(
            workspaces: workspaceRegistry.workspaces,
            activeWorkspaceID: workspaceRegistry.activeWorkspaceID
        )
    }

    private var activeWorkspaceRuntime: ChatWorkspaceRuntime? {
        guard let workspace = workspaceRegistry.activeWorkspace else {
            return nil
        }
        return workspaceRuntimePool.runtime(for: workspace)
    }

    private func currentPoll(in runtime: ChatWorkspaceRuntime) -> PollOverlay? {
        guard let channelID = runtime.chatStore.channel?.id else {
            return nil
        }
        return runtime.chatStore.interactiveOverlayState.pollsByChannel[channelID]
    }

    private func currentPrediction(in runtime: ChatWorkspaceRuntime) -> PredictionOverlay? {
        guard let channelID = runtime.chatStore.channel?.id else {
            return nil
        }
        return runtime.chatStore.interactiveOverlayState.predictionsByChannel[channelID]
    }

    private var canOpenInteractiveManagement: Bool {
        guard let runtime = activeWorkspaceRuntime else {
            return false
        }
        return environment.canManagePolls(in: runtime)
            || environment.canManagePredictions(in: runtime)
    }

    private func presentNewWorkspace() {
        guard workspaceRegistry.workspaces.count < ChatWorkspaceRegistryStore.maximumWorkspaces else {
            showsWorkspaceLimit = true
            return
        }
        newWorkspaceLogin = ""
        showsNewWorkspace = true
    }

    private func openWorkspace() {
        switch workspaceRegistry.open(login: newWorkspaceLogin) {
        case let .opened(workspace):
            showsInteractiveManagement = false
            let runtime = workspaceRuntimePool.runtime(for: workspace)
            newWorkspaceLogin = ""
            guard runtime.chatStore.connectionState != .connected else {
                return
            }
            Task { await connectWorkspace(runtime) }

        case .invalidLogin:
            break

        case .capacityReached:
            showsWorkspaceLimit = true
        }
    }

    private func connectWorkspace(_ runtime: ChatWorkspaceRuntime) async {
        guard workspaceRuntimePool.beginConnection(for: runtime) else {
            showsLiveWorkspaceLimit = true
            return
        }
        defer {
            workspaceRuntimePool.finishConnectionAttempt(for: runtime)
        }
        await environment.connectChat(in: runtime)
    }

    private func selectWorkspace(_ workspace: ChatWorkspace) {
        showsInteractiveManagement = false
        _ = workspaceRegistry.select(id: workspace.id)
        _ = workspaceRuntimePool.runtime(for: workspace)
    }

    private func closeWorkspace(_ workspace: ChatWorkspace) {
        showsInteractiveManagement = false
        _ = workspaceRegistry.close(id: workspace.id)
        Task { await workspaceRuntimePool.remove(id: workspace.id) }
    }

    private func applyWorkspaceImport(_ plan: SettingsBackupImportPlan) async {
        showsInteractiveManagement = false
        let previousIDs = Set(workspaceRegistry.workspaces.map(\.id))
        let snapshot = workspaceRegistry.replace(
            logins: plan.channelLogins,
            selectedLogin: plan.selectedChannelLogin
        )
        let retainedIDs = Set(snapshot.workspaces.map(\.id))

        for removedID in previousIDs.subtracting(retainedIDs) {
            await workspaceRuntimePool.remove(id: removedID)
        }
        workspaceRuntimePool.preload(snapshot.workspaces)
    }

    private func prepareWorkspaceRuntimes() async {
        guard environment.state == .signedIn else {
            return
        }
        if workspaceRegistry.workspaces.isEmpty,
           let login = environment.session?.login {
            _ = workspaceRegistry.open(login: login)
        }
        workspaceRuntimePool.preload(workspaceRegistry.workspaces)
        await workspaceRuntimePool.updateHistoryPreferences(
            environment.chatHistoryPreferences()
        )
    }

    private func settingsLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Settings")
    }

    private func interactiveLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "InteractiveChat")
    }
}
