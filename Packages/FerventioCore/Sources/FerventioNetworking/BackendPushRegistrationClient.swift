import Foundation
import FerventioDomain

public struct BackendAPNsRegistration: Equatable, Sendable {
    public let deviceToken: String
    public let appVersion: String
    public let channelIDs: [String]
    public let moderatorChannelIDs: [String]
    public let notificationRules: [String]
    public let highlightPhrases: [String]
    public let selectedUserLogins: [String]

    public init(
        deviceToken: String,
        appVersion: String,
        channelIDs: [String],
        moderatorChannelIDs: [String],
        notificationRules: [String],
        highlightPhrases: [String] = [],
        selectedUserLogins: [String] = []
    ) {
        self.deviceToken = deviceToken
        self.appVersion = appVersion
        self.channelIDs = channelIDs
        self.moderatorChannelIDs = moderatorChannelIDs
        self.notificationRules = notificationRules
        self.highlightPhrases = highlightPhrases
        self.selectedUserLogins = selectedUserLogins
    }
}

public enum BackendPushRegistrationError: Swift.Error, Equatable, Sendable {
    case invalidResponse
    case invalidRegistration(String)
    case malformedResponse(String)
    case httpStatus(Int, String)
}

public struct BackendPushRegistrationClient: Sendable {
    private struct RegistrationRequest: Encodable {
        let installationId: String
        let deviceSecret: String
        let provider: String
        let apnsDeviceToken: String
        let appVersion: String
        let platform: String
        let channelIds: [String]
        let moderatorChannelIds: [String]
        let notificationRules: [String]
        let highlightPhrases: [String]
        let selectedUserLogins: [String]
    }

    private struct StatusResponse: Decodable {
        let status: String
    }

    private struct ErrorResponse: Decodable {
        let error: String?
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = URL(string: normalized) ?? baseURL
        self.session = session
    }

    public func registerAPNs(
        _ registration: BackendAPNsRegistration,
        device: DeviceIdentity
    ) async throws {
        var request = makeRequest(
            method: "PUT",
            path: "/v1/push/registrations/\(device.installationID)"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeRegistrationBody(registration, device: device)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendPushRegistrationError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        do {
            let result = try JSONDecoder().decode(StatusResponse.self, from: data)
            guard result.status == "registered" else {
                throw BackendPushRegistrationError.malformedResponse("registration status")
            }
        } catch let error as BackendPushRegistrationError {
            throw error
        } catch {
            throw BackendPushRegistrationError.malformedResponse(String(describing: error))
        }
    }

    public func selfTest(device: DeviceIdentity) async throws {
        var request = makeRequest(
            method: "POST",
            path: "/v1/push/registrations/\(device.installationID)/self-test"
        )
        request.setValue(device.deviceSecret, forHTTPHeaderField: "X-Device-Secret")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendPushRegistrationError.invalidResponse
        }
        guard httpResponse.statusCode == 202 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    public func delete(device: DeviceIdentity) async throws {
        var request = makeRequest(
            method: "DELETE",
            path: "/v1/push/registrations/\(device.installationID)"
        )
        request.setValue(device.deviceSecret, forHTTPHeaderField: "X-Device-Secret")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendPushRegistrationError.invalidResponse
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 404 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    func makeRegistrationBody(
        _ registration: BackendAPNsRegistration,
        device: DeviceIdentity
    ) throws -> Data {
        let token = registration.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let appVersion = registration.appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !device.installationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !device.deviceSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !token.isEmpty,
              !appVersion.isEmpty else {
            throw BackendPushRegistrationError.invalidRegistration("missing APNs registration fields")
        }
        return try JSONEncoder().encode(
            RegistrationRequest(
                installationId: device.installationID,
                deviceSecret: device.deviceSecret,
                provider: "apns",
                apnsDeviceToken: token,
                appVersion: appVersion,
                platform: "ios",
                channelIds: normalized(registration.channelIDs),
                moderatorChannelIds: normalized(registration.moderatorChannelIDs),
                notificationRules: normalized(registration.notificationRules),
                highlightPhrases: normalized(registration.highlightPhrases),
                selectedUserLogins: normalized(registration.selectedUserLogins)
            )
        )
    }

    private func makeRequest(method: String, path: String) -> URLRequest {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpoint = URL(string: "\(baseURL.absoluteString)/\(cleanPath)")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        return request
    }

    private func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else {
                return nil
            }
            return value
        }
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> BackendPushRegistrationError {
        let backendMessage = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .httpStatus(
            statusCode,
            backendMessage?.isEmpty == false ? backendMessage! : (fallback ?? "unknown backend error")
        )
    }
}
