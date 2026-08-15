import Foundation
import FerventioDomain
import FerventioNetworking
import SwiftUI

struct CloudSettingsHistoryView: View {
    let presentationPreferences: ChatPresentationPreferences
    let onRestored: (SettingsBackupImportPlan, Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [BackendSettingsSyncHistoryEntry] = []
    @State private var isLoading = true
    @State private var restoringRevision: Int64?
    @State private var pendingRestoreRevision: Int64?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView(cloudLocalized("working"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView {
                    Label(
                        cloudLocalized("history.empty.title"),
                        systemImage: "clock.arrow.circlepath"
                    )
                } description: {
                    Text(cloudLocalized("history.empty.message"))
                } actions: {
                    Button(cloudLocalized("history.retry")) {
                        Task { await loadHistory() }
                    }
                }
            } else {
                List {
                    ForEach(entries, id: \.revision) { entry in
                        revisionRow(entry)
                    }
                }
                .refreshable {
                    await loadHistory()
                }
            }
        }
        .navigationTitle(Text(cloudLocalized("history.title")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
        .confirmationDialog(
            restoreTitle,
            isPresented: restoreConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            if let pendingRestoreRevision {
                Button(cloudLocalized("history.restore"), role: .destructive) {
                    Task { await restore(revision: pendingRestoreRevision) }
                }
            }
            Button(cloudLocalized("history.cancel"), role: .cancel) {
                pendingRestoreRevision = nil
            }
        } message: {
            Text(cloudLocalized("history.restore.message"))
        }
        .alert(
            cloudLocalized("history.error.title"),
            isPresented: errorIsPresented
        ) {
            Button(cloudLocalized("history.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func revisionRow(_ entry: BackendSettingsSyncHistoryEntry) -> some View {
        let isCurrent = entry.revision == entries.first?.revision
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(
                        String(
                            format: cloudLocalized("history.revision"),
                            entry.revision
                        )
                    )
                    .font(.body.weight(.semibold))

                    if isCurrent {
                        Text(cloudLocalized("history.current"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(formattedUpdatedAt(entry.updatedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let appVersion = entry.appVersion,
                   !appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(
                        String(
                            format: cloudLocalized("history.app_version"),
                            appVersion
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if restoringRevision == entry.revision {
                ProgressView()
            } else {
                Button(cloudLocalized("history.restore")) {
                    pendingRestoreRevision = entry.revision
                }
                .buttonStyle(.borderless)
                .disabled(restoringRevision != nil)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadHistory() async {
        guard restoringRevision == nil else {
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entries = try await SettingsSyncService.live().history()
        } catch {
            errorMessage = cloudErrorMessage(error)
        }
    }

    @MainActor
    private func restore(revision: Int64) async {
        guard restoringRevision == nil else {
            return
        }
        pendingRestoreRevision = nil
        restoringRevision = revision
        errorMessage = nil
        defer { restoringRevision = nil }

        do {
            let snapshot = try await SettingsSyncService.live().restore(revision: revision)
            let plan = try SettingsBackupBridge.importPlan(
                raw: snapshot.payloadJSON,
                existingPresentationPreferences: presentationPreferences
            )
            onRestored(plan, snapshot.revision)
            dismiss()
        } catch {
            errorMessage = cloudErrorMessage(error)
        }
    }

    private var restoreConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRestoreRevision != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRestoreRevision = nil
                }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private var restoreTitle: String {
        guard let pendingRestoreRevision else {
            return cloudLocalized("history.restore.title.generic")
        }
        return String(
            format: cloudLocalized("history.restore.title"),
            pendingRestoreRevision
        )
    }

    private func formattedUpdatedAt(_ rawValue: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: rawValue) else {
            return rawValue
        }
        return date.formatted(date: .abbreviated, time: .shortened)
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

    private func cloudLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "CloudSettings")
    }
}
