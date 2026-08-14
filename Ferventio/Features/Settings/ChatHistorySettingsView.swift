import FerventioDomain
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChatHistorySettingsView: View {
    let save: (ChatHistoryPreferences, ChatPresentationPreferences) async -> Void
    let applyWorkspaceImport: (SettingsBackupImportPlan) async -> Void

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

    private let initialWorkspaceSnapshot: ChatWorkspaceRegistrySnapshot

    init(
        preferences: ChatHistoryPreferences,
        presentationPreferences: ChatPresentationPreferences,
        workspaceSnapshot: ChatWorkspaceRegistrySnapshot,
        save: @escaping (ChatHistoryPreferences, ChatPresentationPreferences) async -> Void,
        applyWorkspaceImport: @escaping (SettingsBackupImportPlan) async -> Void
    ) {
        self.save = save
        self.applyWorkspaceImport = applyWorkspaceImport
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
                    .disabled(isSaving)
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
            let export = try SettingsBackupBridge.capture(
                historyPreferences: currentHistoryPreferences,
                presentationPreferences: currentPresentationPreferences,
                workspaceSnapshot: effectiveWorkspaceSnapshot,
                appVersion: appVersion,
                createdAt: currentTimestamp
            )
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

    private func filtersLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ChatFilters")
    }
}
