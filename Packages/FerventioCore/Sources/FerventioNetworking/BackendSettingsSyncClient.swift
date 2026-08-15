import Foundation
import FerventioDomain

public struct BackendSettingsSyncSnapshot: Equatable, Sendable {
    public let revision: Int64
    public let updatedAt: String
    public let updatedByInstallationID: String
    public let appVersion: String?
    public let contentHash: String
    public let payloadJSON: String

    public init(
        revision: Int64,
        updatedAt: String,
        updatedByInstallationID: String,
        appVersion: String?,
        contentHash: String,
        payloadJSON: String
    ) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.updatedByInstallationID = updatedByInstallationID
        self.appVersion = appVersion
        self.contentHash = contentHash
        self.payloadJSON = payloadJSON
    }
}

public struct BackendSettingsSyncHistoryEntry: Equatable, Sendable {
    public let revision: Int64
    public let updatedAt: String
    public let updatedByInstallationID: String
    public let appVersion: String?
    public let contentHash: String

    public init(
        revision: Int64,
        updatedAt: String,
        updatedByInstallationID: String,
        appVersion: String?,
        contentHash: String
    ) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.updatedByInstallationID = updatedByInstallationID
        self.appVersion = appVersion
        self.contentHash = contentHash
    }
}

public enum BackendSettingsSyncError: Swift.Error, Equatable, Sendable {
    case invalidResponse
    case invalidPayload
    case malformedResponse(String)
    case httpStatus(Int, String)
    case conflict(BackendSettingsSyncSnapshot)
}

public struct BackendSettingsSyncClient: Sendable {
    private struct SnapshotWire: Decodable {
        let revision: Int64
        let updatedAt: String
        let updatedByInstallationId: String
        let appVersion: String?
        let contentHash: String
        let payload: JSONValue
    }

    private struct HistoryEntryWire: Decodable {
        let revision: Int64
        let updatedAt: String
        let updatedByInstallationId: String
        let appVersion: String?
        let contentHash: String
    }

    private struct HistoryWire: Decodable {
        let data: [HistoryEntryWire]
    }

    private struct PutRequestWire: Encodable {
        let baseRevision: Int64
        let force: Bool
        let payload: JSONValue
    }

    private struct ConflictWire: Decodable {
        let snapshot: SnapshotWire
    }

    private struct BackendErrorWire: Decodable {
        let error: String?
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = URL(string: normalized) ?? baseURL
        self.session = session
    }

    public func current(
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) async throws -> BackendSettingsSyncSnapshot? {
        var request = makeRequest(method: "GET", path: "/v1/sync/settings")
        applyAuthenticatedHeaders(to: &request, device: device, credential: credential)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendSettingsSyncError.invalidResponse
        }
        if httpResponse.statusCode == 204 {
            return nil
        }
        guard httpResponse.statusCode == 200 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        return try decodeSnapshot(data)
    }

    public func put(
        payloadJSON: String,
        baseRevision: Int64,
        force: Bool,
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) async throws -> BackendSettingsSyncSnapshot {
        var request = makeRequest(method: "PUT", path: "/v1/sync/settings")
        applyAuthenticatedHeaders(to: &request, device: device, credential: credential)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makePutRequestBody(
            payloadJSON: payloadJSON,
            baseRevision: baseRevision,
            force: force
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendSettingsSyncError.invalidResponse
        }
        if httpResponse.statusCode == 409 {
            do {
                let conflict = try JSONDecoder().decode(ConflictWire.self, from: data)
                throw BackendSettingsSyncError.conflict(try makeSnapshot(conflict.snapshot))
            } catch let error as BackendSettingsSyncError {
                throw error
            } catch {
                throw BackendSettingsSyncError.malformedResponse(String(describing: error))
            }
        }
        guard httpResponse.statusCode == 200 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        return try decodeSnapshot(data)
    }

    public func history(
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) async throws -> [BackendSettingsSyncHistoryEntry] {
        var request = makeRequest(method: "GET", path: "/v1/sync/settings/history")
        applyAuthenticatedHeaders(to: &request, device: device, credential: credential)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendSettingsSyncError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(HistoryWire.self, from: data).data.map { entry in
                BackendSettingsSyncHistoryEntry(
                    revision: entry.revision,
                    updatedAt: entry.updatedAt,
                    updatedByInstallationID: entry.updatedByInstallationId,
                    appVersion: entry.appVersion,
                    contentHash: entry.contentHash
                )
            }
        } catch {
            throw BackendSettingsSyncError.malformedResponse(String(describing: error))
        }
    }

    public func restore(
        revision: Int64,
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) async throws -> BackendSettingsSyncSnapshot {
        guard revision > 0 else {
            throw BackendSettingsSyncError.invalidPayload
        }
        var request = makeRequest(
            method: "POST",
            path: "/v1/sync/settings/restore/\(revision)"
        )
        applyAuthenticatedHeaders(to: &request, device: device, credential: credential)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendSettingsSyncError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw makeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        return try decodeSnapshot(data)
    }

    func makePutRequestBody(
        payloadJSON: String,
        baseRevision: Int64,
        force: Bool
    ) throws -> Data {
        let payload = try decodePayload(payloadJSON)
        return try JSONEncoder().encode(
            PutRequestWire(
                baseRevision: baseRevision,
                force: force,
                payload: payload
            )
        )
    }

    private func decodeSnapshot(_ data: Data) throws -> BackendSettingsSyncSnapshot {
        do {
            let wire = try JSONDecoder().decode(SnapshotWire.self, from: data)
            return try makeSnapshot(wire)
        } catch let error as BackendSettingsSyncError {
            throw error
        } catch {
            throw BackendSettingsSyncError.malformedResponse(String(describing: error))
        }
    }

    private func makeSnapshot(_ wire: SnapshotWire) throws -> BackendSettingsSyncSnapshot {
        guard wire.revision > 0,
              !wire.updatedByInstallationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wire.contentHash.count == 64 else {
            throw BackendSettingsSyncError.malformedResponse("settings snapshot metadata")
        }
        let payloadData = try JSONEncoder().encode(wire.payload)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw BackendSettingsSyncError.malformedResponse("settings snapshot payload")
        }
        return BackendSettingsSyncSnapshot(
            revision: wire.revision,
            updatedAt: wire.updatedAt,
            updatedByInstallationID: wire.updatedByInstallationId,
            appVersion: wire.appVersion,
            contentHash: wire.contentHash,
            payloadJSON: payloadJSON
        )
    }

    private func decodePayload(_ raw: String) throws -> JSONValue {
        guard let data = raw.data(using: .utf8), !data.isEmpty else {
            throw BackendSettingsSyncError.invalidPayload
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw BackendSettingsSyncError.invalidPayload
        }
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

    private func applyAuthenticatedHeaders(
        to request: inout URLRequest,
        device: DeviceIdentity,
        credential: BackendSessionCredential
    ) {
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue(device.installationID, forHTTPHeaderField: "X-Installation-ID")
        request.setValue(device.deviceSecret, forHTTPHeaderField: "X-Device-Secret")
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> BackendSettingsSyncError {
        let backendMessage = (try? JSONDecoder().decode(BackendErrorWire.self, from: data).error)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data.prefix(300), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .httpStatus(
            statusCode,
            backendMessage?.isEmpty == false ? backendMessage! : (fallback ?? "unknown backend error")
        )
    }
}

private enum JSONValue: Codable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
