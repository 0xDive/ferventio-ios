import Foundation

public struct DeviceIdentity: Codable, Equatable, Sendable {
    public let installationID: String
    public let deviceSecret: String

    public init(installationID: String, deviceSecret: String) {
        self.installationID = installationID
        self.deviceSecret = deviceSecret
    }
}

public struct BackendAuthorizationStart: Equatable, Sendable {
    public let authorizationURL: URL
    public let state: String
    public let expiresAtEpochMilliseconds: Int64

    public init(authorizationURL: URL, state: String, expiresAtEpochMilliseconds: Int64) {
        self.authorizationURL = authorizationURL
        self.state = state
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
    }
}

public struct BackendSessionCredential: Codable, Equatable, Sendable {
    public let serverURL: String
    public let token: String
    public let expiresAtEpochMilliseconds: Int64

    public init(serverURL: String, token: String, expiresAtEpochMilliseconds: Int64) {
        self.serverURL = serverURL
        self.token = token
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
    }
}

public struct TwitchSession: Codable, Equatable, Sendable {
    public let clientID: String
    public let userID: String
    public let login: String
    public let scopes: Set<String>
    public let expiresInSeconds: Int64

    public init(
        clientID: String,
        userID: String,
        login: String,
        scopes: Set<String>,
        expiresInSeconds: Int64
    ) {
        self.clientID = clientID
        self.userID = userID
        self.login = login
        self.scopes = scopes
        self.expiresInSeconds = expiresInSeconds
    }
}

public struct TwitchAccessLease: Codable, Equatable, Sendable {
    public let accessToken: String
    public let leaseExpiresAtEpochMilliseconds: Int64
    public let twitchExpiresAtEpochMilliseconds: Int64
    public let twitchValidatedAtEpochMilliseconds: Int64
    public let backendSessionExpiresAtEpochMilliseconds: Int64
    public let session: TwitchSession

    public init(
        accessToken: String,
        leaseExpiresAtEpochMilliseconds: Int64,
        twitchExpiresAtEpochMilliseconds: Int64,
        twitchValidatedAtEpochMilliseconds: Int64,
        backendSessionExpiresAtEpochMilliseconds: Int64,
        session: TwitchSession
    ) {
        self.accessToken = accessToken
        self.leaseExpiresAtEpochMilliseconds = leaseExpiresAtEpochMilliseconds
        self.twitchExpiresAtEpochMilliseconds = twitchExpiresAtEpochMilliseconds
        self.twitchValidatedAtEpochMilliseconds = twitchValidatedAtEpochMilliseconds
        self.backendSessionExpiresAtEpochMilliseconds = backendSessionExpiresAtEpochMilliseconds
        self.session = session
    }
}

public struct AuthenticationGrant: Codable, Equatable, Sendable {
    public let backendCredential: BackendSessionCredential
    public let accessLease: TwitchAccessLease

    public init(backendCredential: BackendSessionCredential, accessLease: TwitchAccessLease) {
        self.backendCredential = backendCredential
        self.accessLease = accessLease
    }
}

public struct StoredAuthentication: Codable, Equatable, Sendable {
    public let backendCredential: BackendSessionCredential
    public let accessLease: TwitchAccessLease?

    public init(backendCredential: BackendSessionCredential, accessLease: TwitchAccessLease?) {
        self.backendCredential = backendCredential
        self.accessLease = accessLease
    }
}
