import FerventioDomain
import FerventioNetworking
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatHistorySettingsView: View {
    let save: (ChatHistoryPreferences, ChatPresentationPreferences) async -> Void
    let applyWorkspaceImport: (SettingsBackupImportPlan) async -> Void
    let pushNotificationCoordinator: PushNotificationCoordinator
    let authenticationGrant: AuthenticationGrant?
    let pushChannelLogins: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var repeatCollapseEnabled: Bool
    @State private var presentationRules: [ChatPresentationRule]
    @State private var recentMessagesEnabled: Bool
    @State private var localHistoryEnabled: Bool
    @State private var localHistoryLimit: Int
    @State private var retentionDays: Int
    @State private var maxDatabaseSizeMB: Int
    @State private var pendingWorkspaceImport: SettingsBackupImportPlan?
    @State private var showsBackupImporter = false
    @State private var showsBackupExporter = false
    @State private var showsBackupExportWarning = false
    @State private var backupExportDocument: SettingsBackupFileDocument?
    @State private var backupExportOmittedRuleCount = 0
    @State private var backupErrorMessage: String?
    @State private var isSaving = false
    @State private var isCloudSyncing = false
    @State private var cloudSyncStatus: String?
    @State private var cloudConflictSnapshot: BackendSettingsSyncSnapshot?
    @State private var pendingCloudUploadPayload: String?
    @State private var showsCloudConflict = false

    private let initialWorkspaceSnapshot: ChatWorkspaceRegistrySnapshot

    init(
        preferences: ChatHistoryPreferences,
        presentationPreferences: ChatPresentationPreferences,
        workspaceSnapshot: ChatWorkspaceRegistrySnapshot,
        pushNotificationCoordinator: PushNotificationCoordinator,
        authenticationGrant: AuthenticationGrant?,
        pushChannelLogins: [String],
        save: @escaping (ChatHistoryPreferences, ChatPresentationPreferences) async -> Void,
        applyWorkspaceImport: @escaping (SettingsBackupImportPlan) async -> Void
    ) {
        self.save = save
        self.applyWorkspaceImport = applyWorkspaceImport
        self.pushNotificationCoordinator = pushNotificationCoordinator
        self.authenticationGrant = authenticationGrant
        self.pushChannelLogins = pushChannelLogins
        initialWorkspaceSnapshot = workspaceSnapshot
        _repeatCollapseEnabled = State(
            initialValue: presentationPreferences.repeatCollapseEnabled
        )
        _presentationRules = State(initialValue: presentationPreferences.rules)
        _recentMessagesEnabled = State(initialValue: preferences.recentMessagesEnabled)
        _localHistoryEnabled = State(initialValue: preferences.localHistoryEnabled)
        _localHistoryLimit = State(initialValue: preferences.localHistoryLimit)
        _retentionDays = State(initialValue: preferences.retentionDays)
        _maxDatabaseSizeMB = State(initialValue: preferences.maxDatabaseSizeMB)
        _pendingWorkspaceImport = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        localized("chat.repeat_collapse"),
                        isOn: $repeatCollapseEnabled
                    )
                } header: {
                    Text(localized("chat.section"))
                } footer: {
                    Text(localized("chat.repeat_collapse.footer"))
                }

                Section {
                    NavigationLink {
                        ChatPresentationRulesSettingsView(rules: $presentationRules)
                    } label: {
                        HStack {
                            Label(
                                filtersLocalized("title"),
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                            Spacer(minLength: 12)
                            Text(presentationRules.count.formatted())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text(filtersLocalized("settings.footer"))
                }

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
                            in: ChatHistoryPreferences.minimumLocalHistoryLimit...ChatHistoryPreferences.maximumLocalHistoryLimit,
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

                Section {
                    NavigationLink {
                        PushNotificationSettingsView(
                            coordinator: pushNotificationCoordinator,
                            grant: authenticationGrant,
                            channelLogins: pushChannelLogins
                        )
                    } label: {
                        Label(
                            pushLocalized("open"),
                            systemImage: "bell.badge"
                        )
                    }
                } footer: {
                    Text(pushLocalized("settings.footer"))
                }

                Section {
                    Button {
                        showsBackupImporter = true
                    } label: {
                        Label(
                            localized("backup.import"),
                            systemImage: "square.and.arrow.down"
                        )
                    }

                    Button {
                        prepareBackupExport()
                    } label: {
                        Label(
                            localized("backup.export"),
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    if let pendingWorkspaceImport {
                        backupImportSummary(pendingWorkspaceImport)
                    }
                } header: {
                    Text(localized("backup.section"))
                } footer: {
                    Text(localized("backup.footer"))
                }

                Section {
                    Button {
                        Task { await downloadCloudBackup() }
                    } label: {
                        Label(
                            cloudLocalized("download"),
                            systemImage: "icloud.and.arrow.down"
                        )
                    }
                    .disabled(isCloudSyncing)

                    Button {
                        Task { await uploadCloudBackup() }
                    } label: {
                        Label(
                            cloudLocalized("upload"),
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .disabled(isCloudSyncing)

                    NavigationLink {
                        CloudSettingsHistoryView(
                            presentationPreferences: currentPresentationPreferences
                        ) { plan, revision in
                            applyBackupImportPlan(plan)
                            cloudSyncStatus = String(
                                format: cloudLocalized("history.restored"),
                                revision
                            )
                        }
                    } label: {
                        Label(
                            cloudLocalized("history.open"),
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                    .disabled(isCloudSyncing)

                    if isCloudSyncing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(cloudLocalized("working"))
                                .foregroundStyle(.secondary)
                        }
                    } else if let cloudSyncStatus {
                        Label(cloudSyncStatus, systemImage: "checkmark.icloud")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(cloudLocalized("section"))
                } footer: {
                    Text(cloudLocalized("footer"))
                }
            }
            .navigationTitle(Text(localized("settings.title")))
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
                            await save(currentHistoryPreferences, currentPresentationPreferences)
                            if let pendingWorkspaceImport {
                                await applyWorkspaceImport(pendingWorkspaceImport)
                            }
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || isCloudSyncing)
                }
            }
        }
        .fileImporter(
            isPresented: $showsBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleBackupImport
        )
        .fileExporter(
            isPresented: $showsBackupExporter,
            document: backupExportDocument,
            contentType: .json,
            defaultFilename: "ferventio-settings-backup",
            onCompletion: handleBackupExportCompletion
        )
        .confirmationDialog(
            localized("backup.export.warning.title"),
            isPresented: $showsBackupExportWarning,
            titleVisibility: .visible
        ) {
            Button(localized("backup.export.anyway")) {
                showsBackupExporter = true
            }
            Button(localized("cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: localized("backup.export.warning.message"),
                    backupExportOmittedRuleCount
                )
            )
        }
        .confirmationDialog(
            cloudLocalized("conflict.title"),
            isPresented: $showsCloudConflict,
            titleVisibility: .visible
        ) {
            Button(cloudLocalized("conflict.use_cloud")) {
                useCloudConflictSnapshot()
            }
            Button(cloudLocalized("conflict.overwrite"), role: .destructive) {
                Task { await overwriteCloudConflict() }
            }
            Button(localized("cancel"), role: .cancel) {
                clearCloudConflict()
            }
        } message: {
            Text(cloudLocalized("conflict.message"))
        }
        .alert(
            localized("backup.error.title"),
            isPresented: backupErrorIsPresented
        ) {
            Button(localized("ok"), role: .cancel) {
                backupErrorMessage = nil
            }
        } message: {
            Text(backupErrorMessage ?? "")
        }
    }

    private var currentHistoryPreferences: ChatHistoryPreferences {
        ChatHistoryPreferences(
            recentMessagesEnabled: recentMessagesEnabled,
            localHistoryEnabled: localHistoryEnabled,
            localHistoryLimit: localHistoryLimit,
            retentionDays: retentionDays,
            maxDatabaseSizeMB: maxDatabaseSizeMB
        )
    }

    private var currentPresentationPreferences: ChatPresentationPreferences {
        ChatPresentationPreferences(
            repeatCollapseEnabled: repeatCollapseEnabled,
            rules: presentationRules
        )
    }

    private var effectiveWorkspaceSnapshot: ChatWorkspaceRegistrySnapshot {
        guard let pendingWorkspaceImport else {
            return initialWorkspaceSnapshot
        }
        let workspaces = pendingWorkspaceImport.channelLogins.map { login in
            ChatWorkspace(login: login)
        }
        let activeWorkspaceID = pendingWorkspaceImport.selectedChannelLogin.flatMap { selectedLogin in
            workspaces.first(where: { $0.login == selectedLogin })?.id
        } ?? workspaces.first?.id
        return ChatWorkspaceRegistrySnapshot(
            workspaces: workspaces,
            activeWorkspaceID: activeWorkspaceID
        )
    }

    private var backupErrorIsPresented: Binding<Bool> {
        Binding(
            get: { backupErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    backupErrorMessage = nil
                }
            }
        )
    }

    private func prepareBackupExport() {
        do {
            let export = try makeBackupExport()
            let rawValue = try SettingsBackupBridge.encode(export, pretty: true)
            backupExportDocument = SettingsBackupFileDocument(rawValue: rawValue)
            backupExportOmittedRuleCount = export.omittedPresentationRuleCount
            if export.omittedPresentationRuleCount > 0 {
                showsBackupExportWarning = true
            } else {
                showsBackupExporter = true
            }
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func makeBackupExport() throws -> SettingsBackupExportResult {
        try SettingsBackupBridge.capture(
            historyPreferences: currentHistoryPreferences,
            presentationPreferences: currentPresentationPreferences,
            workspaceSnapshot: effectiveWorkspaceSnapshot,
            appVersion: appVersion,
            createdAt: currentTimestamp
        )
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                backupErrorMessage = localized("backup.error.no_file")
                return
            }
            let rawValue = try SettingsBackupFileIO.readUTF8(from: url)
            let plan = try SettingsBackupBridge.importPlan(
                raw: rawValue,
                existingPresentationPreferences: currentPresentationPreferences
            )
            applyBackupImportPlan(plan)
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func handleBackupExportCompletion(_ result: Result<URL, Error>) {
        backupExportDocument = nil
        if case let .failure(error) = result {
            backupErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func downloadCloudBackup() async {
        guard !isCloudSyncing else {
            return
        }
        isCloudSyncing = true
        cloudSyncStatus = nil
        defer { isCloudSyncing = false }

        do {
            guard let snapshot = try await SettingsSyncService.live().current() else {
                cloudSyncStatus = cloudLocalized("empty")
                return
            }
            try stageCloudSnapshot(snapshot)
            cloudSyncStatus = String(
                format: cloudLocalized("downloaded"),
                snapshot.revision
            )
        } catch {
            backupErrorMessage = cloudErrorMessage(error)
        }
    }

    @MainActor
    private func uploadCloudBackup() async {
        guard !isCloudSyncing else {
            return
        }
        isCloudSyncing = true
        cloudSyncStatus = nil
        defer { isCloudSyncing = false }

        do {
            let export = try makeBackupExport()
            let payload = try SettingsBackupBridge.encode(export, pretty: false)
            let service = SettingsSyncService.live()
            let current = try await service.current()
            do {
                let snapshot = try await service.upload(
                    payloadJSON: payload,
                    baseRevision: current?.revision ?? 0,
                    force: false
                )
                cloudSyncStatus = String(
                    format: cloudLocalized("uploaded"),
                    snapshot.revision
                )
            } catch let BackendSettingsSyncError.conflict(snapshot) {
                cloudConflictSnapshot = snapshot
                pendingCloudUploadPayload = payload
                showsCloudConflict = true
            }
        } catch {
            backupErrorMessage = cloudErrorMessage(error)
        }
    }

    @MainActor
    private func overwriteCloudConflict() async {
        guard !isCloudSyncing,
              let snapshot = cloudConflictSnapshot,
              let payload = pendingCloudUploadPayload else {
            clearCloudConflict()
            return
        }
        showsCloudConflict = false
        isCloudSyncing = true
        cloudSyncStatus = nil
        defer {
            isCloudSyncing = false
            clearCloudConflict()
        }

        do {
            let uploaded = try await SettingsSyncService.live().upload(
                payloadJSON: payload,
                baseRevision: snapshot.revision,
                force: true
            )
            cloudSyncStatus = String(
                format: cloudLocalized("uploaded"),
                uploaded.revision
            )
        } catch {
            backupErrorMessage = cloudErrorMessage(error)
        }
    }

    private func useCloudConflictSnapshot() {
        guard let snapshot = cloudConflictSnapshot else {
            clearCloudConflict()
            return
        }
        do {
            try stageCloudSnapshot(snapshot)
            cloudSyncStatus = String(
                format: cloudLocalized("downloaded"),
                snapshot.revision
            )
        } catch {
            backupErrorMessage = cloudErrorMessage(error)
        }
        clearCloudConflict()
    }

    private func stageCloudSnapshot(_ snapshot: BackendSettingsSyncSnapshot) throws {
        let plan = try SettingsBackupBridge.importPlan(
            raw: snapshot.payloadJSON,
            existingPresentationPreferences: currentPresentationPreferences
        )
        applyBackupImportPlan(plan)
    }

    private func clearCloudConflict() {
        showsCloudConflict = false
        cloudConflictSnapshot = nil
        pendingCloudUploadPayload = nil
    }

    private func cloudErrorMessage(_ error: Swift.Error) -> String {
        switch error {
        case let BackendSettingsSyncError.httpStatus(_, message):
            return message
        case BackendSettingsSyncError.invalidPayload:
            return cloudLocalized("error.invalid_payload")
        case BackendSettingsSyncError.invalidResponse,
             BackendSettingsSyncError.malformedResponse,
             BackendSettingsSyncError.conflict:
            return cloudLocalized("error.generic")
        case SettingsSyncServiceError.notAuthenticated:
            return cloudLocalized("error.not_authenticated")
        default:
            return error.localizedDescription
        }
    }

    private func applyBackupImportPlan(_ plan: SettingsBackupImportPlan) {
        recentMessagesEnabled = plan.historyPreferences.recentMessagesEnabled
        localHistoryEnabled = plan.historyPreferences.localHistoryEnabled
        localHistoryLimit = plan.historyPreferences.localHistoryLimit
        retentionDays = plan.historyPreferences.retentionDays
        maxDatabaseSizeMB = plan.historyPreferences.maxDatabaseSizeMB
        repeatCollapseEnabled = plan.presentationPreferences.repeatCollapseEnabled
        presentationRules = plan.presentationPreferences.rules
        pendingWorkspaceImport = plan
    }

    @ViewBuilder
    private func backupImportSummary(_ plan: SettingsBackupImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                localized("backup.import.ready"),
                systemImage: "checkmark.circle"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                String(
                    format: localized("backup.import.channels"),
                    plan.channelLogins.count
                )
            )
            .foregroundStyle(.secondary)

            if plan.droppedChannelCount > 0 {
                Text(
                    String(
                        format: localized("backup.import.dropped"),
                        plan.droppedChannelCount
                    )
                )
                .foregroundStyle(.secondary)
            }

            if plan.unsupportedContent.hasAny {
                Text(localized("backup.import.unsupported"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.vertical, 2)
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    }

    private var currentTimestamp: String {
        ISO8601DateFormatter().string(from: Date())
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

    private func cloudLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "CloudSettings")
    }

    private func pushLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "PushNotifications")
    }

    private func filtersLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ChatFilters")
    }
}
