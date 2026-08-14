import FerventioSupport
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= SettingsBackupFormat.maximumFileBytes,
              let rawValue = String(data: data, encoding: .utf8) else {
            throw SettingsBackupError.invalidJSON
        }
        self.rawValue = rawValue
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(rawValue.utf8))
    }
}

enum SettingsBackupFileIO {
    static func readUTF8(from url: URL) throws -> String {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(SettingsBackupFormat.maximumFileBytes, 64 * 1_024))
        while data.count <= SettingsBackupFormat.maximumFileBytes {
            let remaining = SettingsBackupFormat.maximumFileBytes + 1 - data.count
            guard remaining > 0 else {
                break
            }
            let chunk = try handle.read(upToCount: min(remaining, 64 * 1_024)) ?? Data()
            guard !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }

        guard data.count <= SettingsBackupFormat.maximumFileBytes else {
            throw SettingsBackupError.fileTooLarge
        }
        guard let rawValue = String(data: data, encoding: .utf8) else {
            throw SettingsBackupError.invalidJSON
        }
        return rawValue
    }
}
