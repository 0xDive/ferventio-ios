import Foundation
import FerventioDomain
import SwiftUI

struct NukePreviewView: View {
    let messages: [ChatMessage]
    let canExecute: Bool
    let execute: (NukeExecutionPlan) async throws -> NukeExecutionResult

    @Environment(\.dismiss) private var dismiss
    @State private var config: NukePreviewConfig
    @State private var pendingPlan: NukeExecutionPlan?
    @State private var showsExecutionConfirmation = false
    @State private var isExecuting = false
    @State private var executionResult: NukeExecutionResult?
    @State private var executionError: String?

    init(
        messages: [ChatMessage],
        initialQuery: String,
        canExecute: Bool,
        execute: @escaping (NukeExecutionPlan) async throws -> NukeExecutionResult
    ) {
        self.messages = messages
        self.canExecute = canExecute
        self.execute = execute
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
                executionSection
                executionResultSection
            }
            .navigationTitle(Text(localized("nuke.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("nuke.done")) {
                        dismiss()
                    }
                    .disabled(isExecuting)
                }
            }
        }
        .interactiveDismissDisabled(isExecuting)
        .alert(
            executionLocalized("nuke.execution.confirm.title"),
            isPresented: $showsExecutionConfirmation,
            presenting: pendingPlan
        ) { plan in
            Button(executionLocalized("nuke.execution.cancel"), role: .cancel) {
                pendingPlan = nil
            }
            Button(executionLocalized("nuke.execution.confirm.action"), role: .destructive) {
                Task {
                    await performExecution(plan)
                }
            }
        } message: { plan in
            Text(confirmationMessage(for: plan))
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
            .disabled(isExecuting)
            .onChange(of: config.query) { _, value in
                if value.count > NukePreviewPlanner.maximumQueryLength {
                    config.query = String(value.prefix(NukePreviewPlanner.maximumQueryLength))
                }
                clearExecutionOutcome()
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
            .disabled(isExecuting)
            .onChange(of: config.matchMode) { _, _ in clearExecutionOutcome() }

            Toggle(localized("nuke.case_sensitive"), isOn: $config.caseSensitive)
                .disabled(isExecuting)
                .onChange(of: config.caseSensitive) { _, _ in clearExecutionOutcome() }

            Picker(localized("nuke.time_window"), selection: $config.windowMilliseconds) {
                ForEach(Self.windowPresets, id: \.self) { milliseconds in
                    Text("\(milliseconds / 1_000)s")
                        .tag(milliseconds)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isExecuting)
            .onChange(of: config.windowMilliseconds) { _, _ in clearExecutionOutcome() }
        } header: {
            Text(localized("nuke.matching"))
        }
    }

    private var exclusionsSection: some View {
        Section {
            Toggle(localized("nuke.exclude_broadcaster"), isOn: $config.excludeBroadcaster)
                .disabled(isExecuting)
                .onChange(of: config.excludeBroadcaster) { _, _ in clearExecutionOutcome() }
            Toggle(localized("nuke.exclude_moderators"), isOn: $config.excludeModerators)
                .disabled(isExecuting)
                .onChange(of: config.excludeModerators) { _, _ in clearExecutionOutcome() }
            Toggle(localized("nuke.exclude_vips"), isOn: $config.excludeVIPs)
                .disabled(isExecuting)
                .onChange(of: config.excludeVIPs) { _, _ in clearExecutionOutcome() }
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

    private var executionSection: some View {
        Section {
            if canExecute {
                Button(role: .destructive) {
                    prepareExecution()
                } label: {
                    if isExecuting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(executionLocalized("nuke.execution.running"))
                        }
                    } else {
                        Label(
                            executionLocalized("nuke.execution.action"),
                            systemImage: "person.crop.circle.badge.clock"
                        )
                    }
                }
                .disabled(!canPrepareExecution)

                Text(executionLocalized("nuke.execution.warning"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    executionLocalized("nuke.execution.unavailable"),
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(executionLocalized("nuke.execution.section"))
        }
    }

    @ViewBuilder
    private var executionResultSection: some View {
        if let result = executionResult {
            Section {
                LabeledContent(
                    executionLocalized("nuke.execution.attempted"),
                    value: result.attemptedUsers.formatted()
                )
                LabeledContent(
                    executionLocalized("nuke.execution.succeeded"),
                    value: result.succeededUsers.formatted()
                )
                LabeledContent(
                    executionLocalized("nuke.execution.failed_count"),
                    value: result.failedUsers.formatted()
                )

                ForEach(result.failures.prefix(5)) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            failure.user.userDisplayName.isEmpty
                                ? failure.user.userLogin
                                : failure.user.userDisplayName
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(executionLocalized("nuke.execution.result"))
            }
        } else if let executionError {
            Section {
                Text(executionError)
                    .foregroundStyle(.red)
            } header: {
                Text(executionLocalized("nuke.execution.result"))
            }
        }
    }

    private var previewResult: NukePreviewResult {
        NukePreviewPlanner.build(
            messages: messages,
            config: config,
            nowMilliseconds: Self.nowMilliseconds()
        )
    }

    private var canPrepareExecution: Bool {
        guard canExecute,
              !isExecuting,
              let count = previewResult.preview?.matchedUserCount else {
            return false
        }
        return count > 0 && count <= NukeExecutionPolicy().maxTargetUsers
    }

    private func prepareExecution() {
        executionResult = nil
        executionError = nil
        let previewedAt = Self.nowMilliseconds()
        let result = NukePreviewPlanner.build(
            messages: messages,
            config: config,
            nowMilliseconds: previewedAt
        )
        guard case let .success(preview) = result else {
            return
        }

        let limit = NukeExecutionPolicy().maxTargetUsers
        guard preview.matchedUserCount <= limit else {
            executionError = String(
                format: executionLocalized("nuke.execution.too_many"),
                limit
            )
            return
        }

        guard case let .success(plan) = NukeExecutionPlanner.freeze(
            config: config,
            preview: preview,
            previewedAtMilliseconds: previewedAt
        ) else {
            executionError = executionLocalized("nuke.execution.freeze_failed")
            return
        }

        pendingPlan = plan
        showsExecutionConfirmation = true
    }

    @MainActor
    private func performExecution(_ plan: NukeExecutionPlan) async {
        isExecuting = true
        executionResult = nil
        executionError = nil
        defer {
            isExecuting = false
            pendingPlan = nil
        }

        do {
            executionResult = try await execute(plan)
        } catch is CancellationError {
            return
        } catch {
            executionError = executionLocalized("nuke.execution.failed")
                + "\n"
                + String(describing: error)
        }
    }

    private func confirmationMessage(for plan: NukeExecutionPlan) -> String {
        String(
            format: executionLocalized("nuke.execution.confirm.message"),
            plan.targetUserCount,
            NukeExecutionPolicy().timeoutSeconds / 60
        )
    }

    private func clearExecutionOutcome() {
        guard !isExecuting else { return }
        executionResult = nil
        executionError = nil
        pendingPlan = nil
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

    private func executionLocalized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ModerationExecution")
    }

    private static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private static let windowPresets: [Int64] = [10_000, 30_000, 60_000]
}
