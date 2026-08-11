import Foundation
import FerventioDomain

public struct BackendClient: Sendable {
    public typealias DeviceCredentials = DeviceIdentity

    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case invalidAuthorizationURL
        case invalidTimestamp(String)
        case expiredServerDeadline
        case inconsistentSessionExpiry
        case malformedResponse(String)
        case httpStatus(Int, String)
    }

    private struct MobileAuthStartRequest: Encodable {
        let installationId: String
        let deviceSecret: String
        let appCallbackUri: String
    }

    private struct MobileAuthStartResponse: Decodable {
        let authorizationUrl: String
        let state: String
        let serverTime: String
        let expiresAt: String
    }

    private struct MobileAuthCompleteRequest: Encodable {
        let installationId: String
        let deviceSecret: String
        let code: String
        let state: String
    }

    private struct MobileAuthCompleteResponse: Decodable {
        let sessionToken: String
        let sessionExpiresAt: String
        let lease: TokenLeaseResponse
    }

    private struct TokenLeaseResponse: Decodable {
        let accessToken: String
        let serverTime: String
        let clientId: String
        let userId: String
        let login: String
        let scopes: [String]
        let leaseExpiresAt: String
        let twitchExpiresAt: String
        let twitchValidatedAt: String?
        let sessionExpiresAt: String
    }

    private struct BackendErrorResponse: Decodable {
        let error: String?
    }

    public let serverURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.serverURL = URL(string: normalized) ?? baseURL
        self.session = session
    }

    public func startAuthorization(
        device: DeviceIdentity,
        appCallbackURL: URL,
        now: Date = Date()
    ) async throws -> BackendAuthorizationStart {
        var request = makeRequest(method: "POST", path: "/v1/auth/mobile/start")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MobileAuthStartRequest(
                installationId: device.installationID,
                deviceSecret: device.deviceSecret,
                appCallbackUri: appCallbackURL.absoluteString
            )
        )

        let response: MobileAuthStartResponse = try await perform(request)
        guard let authorizationURL = URL(string: response.authorizationUrl),
              isSafeAuthorizationURL(authorizationURL) else {
            throw Error.invalidAuthorizationURL
        }
        let expiresAt = try serverRelativeDeadline(
            serverTime: response.serverTime,
            expiresAt: response.expiresAt,
            now: now
        )
        guard !response.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.malformedResponse("state")
        }
        return BackendAuthorizationStart(
            authorizationURL: authorizationURL,
            state: response.state,
            expiresAtEpochMilliseconds: expiresAt
        )
    }

    public func completeAuthorization(
        device: DeviceIdentity,
        code: String,
        state: String,
        now: Date = Date()
    ) async throws -> AuthenticationGrant {
        var request = makeRequest(method: "POST", path: "/v1/auth/mobile/complete")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MobileAuthCompleteRequest(
                installationId: device.installationID,
                deviceSecret: device.deviceSecret,
                code: code,
                state: state
            )
        )

        let response: MobileAuthCompleteResponse = try await perform(request)
        let declaredSessionExpiry = try parseTimestamp(response.sessionExpiresAt)
        let leaseSessionExpiry = try parseTimestamp(response.lease.sessionExpiresAt)
        guard declaredSessionExpiry == leaseSessionExpiry else {
            throw Error.inconsistentSessionExpiry
        }

        let lease = try makeLease(from: response.lease, now: now)
        let credential = BackendSessionCredential(
            serverURL: serverURL.absoluteString,
            token: response.sessionToken,
            expiresAtEpochMilliseconds: lease.backendSessionExpiresAtEpochMilliseconds
        )
        guard !credential.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.malformedResponse("sessionToken")
        }
        return AuthenticationGrant(backendCredential: credential, accessLease: lease)
    }

    public func leaseAccessToken(
        device: DeviceIdentity,
        credential: BackendSessionCredential,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async throws -> TwitchAccessLease {
        var request = makeRequest(
            method: "POST",
            path: "/v1/auth/token",
            queryItems: forceRefresh ? [URLQueryItem(name: "force_refresh", value: "true")] : []
        )
        applyAuthenticatedHeaders(to: &request, device: device, sessionToken: credential.token)
        let response: TokenLeaseResponse = try await perform(request)
        return try makeLease(from: response, now: now)
    }

    public func logout(device: DeviceIdentity, credential: BackendSessionCredential) async throws {
        var request = makeRequest(method: "DELETE", path: "/v1/auth/session")
        applyAuthenticatedHeaders(to: &request, device: device, sessionToken: credential.token)
        try await performNoContent(request, acceptedStatusCodes: [204, 401])
    }

    public func revokeDevice(device: DeviceIdentity, credential: BackendSessionCredential) async throws {
        var request = makeRequest(method: "DELETE", path: "/v1/auth/device")
        applyAuthenticatedHeaders(to: &request, device: device, sessionToken: credential.token)
        try await performNoContent(request, acceptedStatusCodes: [204])
    }

    public func revokeAllSessions(device: DeviceIdentity, credential: BackendSessionCredential) async throws {
        var request = makeRequest(method: "DELETE", path: "/v1/auth/sessions")
        applyAuthenticatedHeaders(to: &request, device: device, sessionToken: credential.token)
        try await performNoContent(request, acceptedStatusCodes: [204])
    }

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpoint = URL(string: "\(serverURL.absoluteString)/\(cleanPath)")!
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    private func applyAuthenticatedHeaders(
        to request: inout URLRequest,
        device: DeviceIdentity,
        sessionToken: String
    ) {
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(device.installationID, forHTTPHeaderField: "X-Installation-ID")
        request.setValue(device.deviceSecret, forHTTPHeaderField: "X-Device-Secret")
    }

    private func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Error.malformedResponse(String(describing: error))
        }
    }

    private func performNoContent(_ request: URLRequest, acceptedStatusCodes: Set<Int>) async throws {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> Error {
        let backendMessage = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data).error)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .httpStatus(statusCode, backendMessage?.isEmpty == false ? backendMessage! : (fallback ?? "unknown backend error"))
    }

    private func makeLease(from response: TokenLeaseResponse, now: Date) throws -> TwitchAccessLease {
        let nowMilliseconds = epochMilliseconds(now)
        let leaseExpiresAt = try serverRelativeDeadline(
            serverTime: response.serverTime,
            expiresAt: response.leaseExpiresAt,
            now: now
        )
        let twitchExpiresAt = try serverRelativeDeadline(
            serverTime: response.serverTime,
            expiresAt: response.twitchExpiresAt,
            now: now
        )
        let backendSessionExpiresAt = try serverRelativeDeadline(
            serverTime: response.serverTime,
            expiresAt: response.sessionExpiresAt,
            now: now
        )
        let twitchValidatedAt: Int64
        if let rawValidatedAt = response.twitchValidatedAt {
            let mapped = try serverRelativeTimestamp(
                serverTime: response.serverTime,
                timestamp: rawValidatedAt,
                now: now
            )
            twitchValidatedAt = min(max(mapped, 1), nowMilliseconds)
        } else {
            twitchValidatedAt = max(nowMilliseconds - 55 * 60 * 1_000, 1)
        }

        guard leaseExpiresAt <= twitchExpiresAt else {
            throw Error.malformedResponse("leaseExpiresAt")
        }
        let accessToken = response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = response.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = response.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = response.login.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopes = Set(response.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !accessToken.isEmpty,
              !clientID.isEmpty,
              !userID.isEmpty,
              !login.isEmpty,
              !scopes.contains("") else {
            throw Error.malformedResponse("lease")
        }

        let remainingSeconds = max((twitchExpiresAt - nowMilliseconds) / 1_000, 0)
        return TwitchAccessLease(
            accessToken: accessToken,
            leaseExpiresAtEpochMilliseconds: leaseExpiresAt,
            twitchExpiresAtEpochMilliseconds: twitchExpiresAt,
            twitchValidatedAtEpochMilliseconds: twitchValidatedAt,
            backendSessionExpiresAtEpochMilliseconds: backendSessionExpiresAt,
            session: TwitchSession(
                clientID: clientID,
                userID: userID,
                login: login,
                scopes: scopes,
                expiresInSeconds: remainingSeconds
            )
        )
    }

    private func serverRelativeDeadline(serverTime: String, expiresAt: String, now: Date) throws -> Int64 {
        let server = try parseTimestamp(serverTime)
        let expiry = try parseTimestamp(expiresAt)
        let remaining = expiry.timeIntervalSince(server)
        guard remaining > 0 else {
            throw Error.expiredServerDeadline
        }
        return epochMilliseconds(now.addingTimeInterval(remaining))
    }

    private func serverRelativeTimestamp(serverTime: String, timestamp: String, now: Date) throws -> Int64 {
        let server = try parseTimestamp(serverTime)
        let timestamp = try parseTimestamp(timestamp)
        return epochMilliseconds(now.addingTimeInterval(timestamp.timeIntervalSince(server)))
    }

    private func parseTimestamp(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }
        throw Error.invalidTimestamp(value)
    }

    private func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private func isSafeAuthorizationURL(_ target: URL) -> Bool {
        guard target.scheme?.lowercased() == serverURL.scheme?.lowercased(),
              target.host?.lowercased() == serverURL.host?.lowercased(),
              effectivePort(target) == effectivePort(serverURL),
              target.user == nil,
              target.password == nil,
              target.fragment == nil else {
            return false
        }
        return true
    }

    private func effectivePort(_ url: URL) -> Int {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return -1
        }
    }
}
