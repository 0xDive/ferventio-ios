import Foundation
import FerventioDomain

public struct AuthenticationStore: Sendable {
    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(Int)
        case invalidPayload
    }

    private struct Envelope: Codable, Sendable {
        let version: Int
        let authentication: StoredAuthentication
    }

    private let store: any SecureKeyValueStoring

    public init(store: any SecureKeyValueStoring) {
        self.store = store
    }

    public func load() throws -> StoredAuthentication? {
        guard let raw = try store.string(forKey: Keys.authentication) else {
            return nil
        }
        guard let data = raw.data(using: .utf8) else {
            throw Error.invalidPayload
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw Error.invalidPayload
        }
        guard envelope.version == 1 else {
            throw Error.unsupportedVersion(envelope.version)
        }
        try validate(envelope.authentication)
        return envelope.authentication
    }

    public func save(_ authentication: StoredAuthentication) throws {
        try validate(authentication)
        let envelope = Envelope(version: 1, authentication: authentication)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw Error.invalidPayload
        }
        try store.set(raw, forKey: Keys.authentication)
    }

    public func save(_ grant: AuthenticationGrant) throws {
        try save(
            StoredAuthentication(
                backendCredential: grant.backendCredential,
                accessLease: grant.accessLease
            )
        )
    }

    public func clear() throws {
        try store.removeValue(forKey: Keys.authentication)
    }

    private func validate(_ authentication: StoredAuthentication) throws {
        let credential = authentication.backendCredential
        guard !credential.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credential.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              credential.expiresAtEpochMilliseconds > 0 else {
            throw Error.invalidPayload
        }

        guard let lease = authentication.accessLease else {
            return
        }
        guard !lease.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lease.leaseExpiresAtEpochMilliseconds > 0,
              lease.twitchExpiresAtEpochMilliseconds > 0,
              lease.leaseExpiresAtEpochMilliseconds <= lease.twitchExpiresAtEpochMilliseconds,
              lease.twitchValidatedAtEpochMilliseconds > 0,
              lease.twitchValidatedAtEpochMilliseconds <= lease.twitchExpiresAtEpochMilliseconds,
              lease.backendSessionExpiresAtEpochMilliseconds == credential.expiresAtEpochMilliseconds,
              !lease.session.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lease.session.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lease.session.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lease.session.scopes.count <= 128,
              !lease.session.scopes.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              lease.session.expiresInSeconds >= 0 else {
            throw Error.invalidPayload
        }
    }

    private enum Keys {
        static let authentication = "auth.session.v1"
    }
}
