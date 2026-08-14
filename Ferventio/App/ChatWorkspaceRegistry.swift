import Foundation
import Observation

struct ChatWorkspace: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let login: String

    init(id: UUID = UUID(), login: String) {
        self.id = id
        self.login = login
    }
}

struct ChatWorkspaceRegistrySnapshot: Codable, Equatable, Sendable {
    let workspaces: [ChatWorkspace]
    let activeWorkspaceID: UUID?

    static let empty = ChatWorkspaceRegistrySnapshot(
        workspaces: [],
        activeWorkspaceID: nil
    )
}

@MainActor
final class ChatWorkspaceRegistryPersistence {
    private struct Envelope: Codable {
        let version: Int
        let snapshot: ChatWorkspaceRegistrySnapshot
    }

    static let currentVersion = 1
    static let storageKey = "chat_workspaces_v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChatWorkspaceRegistrySnapshot {
        guard let data = defaults.data(forKey: Self.storageKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion else {
            return .empty
        }
        return envelope.snapshot
    }

    func save(_ snapshot: ChatWorkspaceRegistrySnapshot) {
        let envelope = Envelope(
            version: Self.currentVersion,
            snapshot: snapshot
        )
        guard let data = try? JSONEncoder().encode(envelope) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

@MainActor
@Observable
final class ChatWorkspaceRegistryStore {
    enum OpenResult: Equatable {
        case opened(ChatWorkspace)
        case invalidLogin
        case capacityReached
    }

    nonisolated static let maximumWorkspaces = 8

    private(set) var workspaces: [ChatWorkspace]
    private(set) var activeWorkspaceID: UUID?

    @ObservationIgnored private let persistence: ChatWorkspaceRegistryPersistence

    init(persistence: ChatWorkspaceRegistryPersistence = ChatWorkspaceRegistryPersistence()) {
        self.persistence = persistence
        let stored = persistence.load()
        let normalized = Self.normalizedSnapshot(stored)
        workspaces = normalized.workspaces
        activeWorkspaceID = normalized.activeWorkspaceID
        if normalized != stored {
            persistence.save(normalized)
        }
    }

    var activeWorkspace: ChatWorkspace? {
        guard let activeWorkspaceID else {
            return nil
        }
        return workspaces.first { $0.id == activeWorkspaceID }
    }

    @discardableResult
    func open(login rawLogin: String) -> OpenResult {
        guard let login = Self.normalizedLogin(rawLogin) else {
            return .invalidLogin
        }

        if let existing = workspaces.first(where: { $0.login == login }) {
            activeWorkspaceID = existing.id
            persist()
            return .opened(existing)
        }

        guard workspaces.count < Self.maximumWorkspaces else {
            return .capacityReached
        }

        let workspace = ChatWorkspace(login: login)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        persist()
        return .opened(workspace)
    }

    @discardableResult
    func select(id: UUID) -> Bool {
        guard workspaces.contains(where: { $0.id == id }) else {
            return false
        }
        activeWorkspaceID = id
        persist()
        return true
    }

    @discardableResult
    func close(id: UUID) -> ChatWorkspace? {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let removed = workspaces.remove(at: index)
        if activeWorkspaceID == id {
            if workspaces.isEmpty {
                activeWorkspaceID = nil
            } else {
                activeWorkspaceID = workspaces[min(index, workspaces.count - 1)].id
            }
        }
        persist()
        return removed
    }

    @discardableResult
    func move(id: UUID, toIndex requestedIndex: Int) -> Bool {
        guard let sourceIndex = workspaces.firstIndex(where: { $0.id == id }),
              !workspaces.isEmpty else {
            return false
        }
        let targetIndex = min(max(requestedIndex, 0), workspaces.count - 1)
        guard sourceIndex != targetIndex else {
            return true
        }

        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: targetIndex)
        persist()
        return true
    }

    @discardableResult
    func replace(
        logins rawLogins: [String],
        selectedLogin rawSelectedLogin: String?
    ) -> ChatWorkspaceRegistrySnapshot {
        let existingByLogin = Dictionary(
            uniqueKeysWithValues: workspaces.map { ($0.login, $0) }
        )
        var seenLogins = Set<String>()
        var replacement: [ChatWorkspace] = []
        replacement.reserveCapacity(min(rawLogins.count, Self.maximumWorkspaces))

        for rawLogin in rawLogins {
            guard replacement.count < Self.maximumWorkspaces,
                  let login = Self.normalizedLogin(rawLogin),
                  seenLogins.insert(login).inserted else {
                continue
            }
            replacement.append(existingByLogin[login] ?? ChatWorkspace(login: login))
        }

        let selectedLogin = rawSelectedLogin.flatMap(Self.normalizedLogin)
        let selectedID = selectedLogin.flatMap { login in
            replacement.first(where: { $0.login == login })?.id
        } ?? replacement.first?.id

        workspaces = replacement
        activeWorkspaceID = selectedID
        persist()

        return ChatWorkspaceRegistrySnapshot(
            workspaces: workspaces,
            activeWorkspaceID: activeWorkspaceID
        )
    }

    static func normalizedLogin(_ rawLogin: String) -> String? {
        let login = rawLogin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return login.isEmpty ? nil : login
    }

    private func persist() {
        persistence.save(
            ChatWorkspaceRegistrySnapshot(
                workspaces: workspaces,
                activeWorkspaceID: activeWorkspaceID
            )
        )
    }

    private static func normalizedSnapshot(
        _ snapshot: ChatWorkspaceRegistrySnapshot
    ) -> ChatWorkspaceRegistrySnapshot {
        var seenLogins = Set<String>()
        var seenIDs = Set<UUID>()
        var workspaces: [ChatWorkspace] = []

        for workspace in snapshot.workspaces {
            guard workspaces.count < maximumWorkspaces,
                  let login = normalizedLogin(workspace.login),
                  seenLogins.insert(login).inserted,
                  seenIDs.insert(workspace.id).inserted else {
                continue
            }
            workspaces.append(ChatWorkspace(id: workspace.id, login: login))
        }

        let activeWorkspaceID: UUID?
        if let requested = snapshot.activeWorkspaceID,
           workspaces.contains(where: { $0.id == requested }) {
            activeWorkspaceID = requested
        } else {
            activeWorkspaceID = workspaces.first?.id
        }

        return ChatWorkspaceRegistrySnapshot(
            workspaces: workspaces,
            activeWorkspaceID: activeWorkspaceID
        )
    }
}
