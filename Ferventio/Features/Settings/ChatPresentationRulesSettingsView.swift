import Foundation
import FerventioDomain
import SwiftUI

struct ChatPresentationRulesSettingsView: View {
    @Binding var rules: [ChatPresentationRule]
    @State private var editingRule: ChatPresentationRule?

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    localized("empty.title"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(localized("empty.message"))
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete(perform: deleteRules)
                    .onMove(perform: moveRules)
                } footer: {
                    Text(localized("rules.footer"))
                }
            }
        }
        .navigationTitle(localized("title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(rules.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingRule = ChatPresentationRule(
                        action: .highlight,
                        target: .message,
                        query: ""
                    )
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text(localized("add")))
                }
                .disabled(rules.count >= ChatPresentationPreferencesStore.maximumRules)
            }
        }
        .sheet(item: $editingRule) { rule in
            ChatPresentationRuleEditor(initialRule: rule) { savedRule in
                upsert(savedRule)
            }
        }
    }

    private func ruleRow(_ rule: ChatPresentationRule) -> some View {
        HStack(spacing: 12) {
            Button {
                editingRule = rule
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: rule.action == .hide ? "eye.slash" : "highlighter")
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.query)
                            .lineLimit(1)
                        Text(ruleSummary(rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: enabledBinding(for: rule.id))
                .labelsHidden()
        }
    }

    private func enabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                rules.first(where: { $0.id == id })?.isEnabled ?? false
            },
            set: { newValue in
                guard let index = rules.firstIndex(where: { $0.id == id }) else {
                    return
                }
                rules[index].isEnabled = newValue
            }
        )
    }

    private func upsert(_ rule: ChatPresentationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else if rules.count < ChatPresentationPreferencesStore.maximumRules {
            rules.append(rule)
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
    }

    private func ruleSummary(_ rule: ChatPresentationRule) -> String {
        let action = localized(rule.action == .hide ? "action.hide" : "action.highlight")
        let target = localized(rule.target == .message ? "target.message" : "target.author")
        let mode = localized(rule.matchMode == .contains ? "match.contains" : "match.regex")
        return "\(action) · \(target) · \(mode)"
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ChatFilters")
    }
}

private struct ChatPresentationRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ChatPresentationRule
    let onSave: (ChatPresentationRule) -> Void

    init(
        initialRule: ChatPresentationRule,
        onSave: @escaping (ChatPresentationRule) -> Void
    ) {
        _rule = State(initialValue: initialRule)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("action.section")) {
                    Picker(localized("action.section"), selection: $rule.action) {
                        Text(localized("action.hide"))
                            .tag(ChatPresentationRuleAction.hide)
                        Text(localized("action.highlight"))
                            .tag(ChatPresentationRuleAction.highlight)
                    }
                    .pickerStyle(.segmented)
                }

                Section(localized("target.section")) {
                    Picker(localized("target.section"), selection: $rule.target) {
                        Text(localized("target.message"))
                            .tag(ChatPresentationRuleTarget.message)
                        Text(localized("target.author"))
                            .tag(ChatPresentationRuleTarget.author)
                    }
                }

                Section {
                    Picker(localized("match.mode"), selection: $rule.matchMode) {
                        Text(localized("match.contains"))
                            .tag(ChatPresentationRuleMatchMode.contains)
                        Text(localized("match.regex"))
                            .tag(ChatPresentationRuleMatchMode.regex)
                    }

                    TextField(localized("query"), text: $rule.query, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle(localized("case_sensitive"), isOn: $rule.caseSensitive)
                } header: {
                    Text(localized("match.section"))
                } footer: {
                    if let validationError {
                        Text(validationMessage(validationError))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(localized("editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("save")) {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
        }
    }

    private var validationError: ChatPresentationRuleValidationError? {
        ChatPresentationRuleEngine.validate(rule)
    }

    private func validationMessage(
        _ error: ChatPresentationRuleValidationError
    ) -> String {
        switch error {
        case .emptyQuery:
            localized("validation.empty")
        case let .queryTooLong(maximumLength):
            String(
                format: localized("validation.too_long"),
                maximumLength
            )
        case .invalidRegularExpression:
            localized("validation.invalid_regex")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "ChatFilters")
    }
}
