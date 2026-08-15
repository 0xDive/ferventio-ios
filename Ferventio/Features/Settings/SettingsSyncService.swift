import Foundation
import FerventioDomain
import FerventioNetworking
import FerventioSupport

@MainActor
protocol SettingsSyncing: AnyObject {
    func current() async throws -> BackendSettingsSyncSnapshot?
    func upload(
        payloadJSON: String,
        baseRevision: Int64,
        force: Bool
    ) async throws -> BackendSettingsSyncSnapshot
    func history() async throws -> [BackendSettingsSyncHistoryEntry]
    func restore(revision: Int64) async throws -> BackendSettingsSyncSnapshot
}

enum SettingsSyncServiceError: Swift.Error, Equatable, Sendable {
    case notAuthenticated
}

struct SettingsSyncCredentialSnapshot {
    private enum State {
        case credential(BackendSessionCredential)
        case missing
        case failure(any Swift.Error)
    }

    private let state: State

    init(load: () throws -> StoredAuthentication?) {
        do {
            if let stored = try load() {
                state = .credential(stored.backendCredential)
            } else {
                state = .missing
            }
        } catch {
            state = .failure(error)
        }
    }

    func requireCredential() throws -> BackendSessionCredential {
        switch state {
        case let .credential(credential):
            return credential
        case .missing:
            throw SettingsSyncServiceError.notAuthenticated
        case let .failure(error):
            throw error
        }
    }
}

@MainActor
final class SettingsSyncService: SettingsSyncing {
    private let client: BackendSettingsSyncClient
    private let identityStore: DeviceIdentityStore
    private let credentialSnapshot: SettingsSyncCredentialSnapshot

    init(
        client: BackendSettingsSyncClient,
        identityStore: DeviceIdentityStore,
        authenticationStore: AuthenticationStore
    ) {
        self.client = client
        self.identityStore = identityStore
        credentialSnapshot = SettingsSyncCredentialSnapshot {
            try authenticationStore.load()
        }
    }

    static func live(configuration: AppConfiguration = .live) -> SettingsSyncService {
        let keychain = KeychainStore(service: configuration.keychainService)
        return SettingsSyncService(
            client: BackendSettingsSyncClient(baseURL: configuration.backendURL),
            identityStore: DeviceIdentityStore(store: keychain),
            authenticationStore: AuthenticationStore(store: keychain)
        )
    }

    func current() async throws -> BackendSettingsSyncSnapshot? {
        let context = try authenticatedContext()
        return try await client.current(
            device: context.device,
            credential: context.credential
        )
    }

    func upload(
        payloadJSON: String,
        baseRevision: Int64,
        force: Bool
    ) async throws -> BackendSettingsSyncSnapshot {
        let context = try authenticatedContext()
        return try await client.put(
            payloadJSON: payloadJSON,
            baseRevision: baseRevision,
            force: force,
            device: context.device,
            credential: context.credential
        )
    }

    func history() async throws -> [BackendSettingsSyncHistoryEntry] {
        let context = try authenticatedContext()
        return try await client.history(
            device: context.device,
            credential: context.credential
        )
    }

    func restore(revision: Int64) async throws -> BackendSettingsSyncSnapshot {
        let context = try authenticatedContext()
        return try await client.restore(
            revision: revision,
            device: context.device,
            credential: context.credential
        )
    }

    private func authenticatedContext() throws -> (
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) {
        (
            try identityStore.loadOrCreate(),
            try credentialSnapshot.requireCredential()
        )
    }
}
