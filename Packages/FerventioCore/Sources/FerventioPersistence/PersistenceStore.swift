import Foundation
import FerventioDomain
import GRDB

public actor PersistenceStore {
    public enum Error: Swift.Error, Equatable {
        case invalidLimit
        case invalidRetentionBoundary
    }

    public static let payloadFormatVersion = 1

    private let databaseQueue: DatabaseQueue
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.label = "FerventioPersistence"
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        databaseQueue = try DatabaseQueue(path: path, configuration: configuration)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        try Self.makeMigrator().migrate(databaseQueue)
    }

    public static func inMemory() throws -> PersistenceStore {
        try PersistenceStore(path: ":memory:")
    }

    public func save(_ message: ChatMessage) throws {
        let payload = try encoder.encode(message)
        try databaseQueue.write { db in
            try Self.upsert(message: message, payload: payload, db: db)
        }
    }

    public func save(_ messages: [ChatMessage]) throws {
        guard !messages.isEmpty else {
            return
        }
        let encoded = try messages.map { message in
            (message, try encoder.encode(message))
        }
        try databaseQueue.write { db in
            for (message, payload) in encoded {
                try Self.upsert(message: message, payload: payload, db: db)
            }
        }
    }

    public func recentMessages(
        channelID: String,
        limit: Int,
        beforeTimestampMilliseconds: Int64? = nil
    ) throws -> [ChatMessage] {
        guard limit > 0 else {
            throw Error.invalidLimit
        }
        let rows: [Row] = try databaseQueue.read { db in
            if let beforeTimestampMilliseconds {
                return try Row.fetchAll(
                    db,
                    sql: """
                    SELECT payload
                    FROM chat_messages
                    WHERE channel_id = ? AND timestamp_ms < ?
                    ORDER BY timestamp_ms DESC, message_id DESC
                    LIMIT ?
                    """,
                    arguments: [channelID, beforeTimestampMilliseconds, limit]
                )
            }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT payload
                FROM chat_messages
                WHERE channel_id = ?
                ORDER BY timestamp_ms DESC, message_id DESC
                LIMIT ?
                """,
                arguments: [channelID, limit]
            )
        }

        return try rows.reversed().map { row in
            let payload: Data = row["payload"]
            return try decoder.decode(ChatMessage.self, from: payload)
        }
    }

    @discardableResult
    public func prune(olderThanTimestampMilliseconds boundary: Int64) throws -> Int {
        guard boundary >= 0 else {
            throw Error.invalidRetentionBoundary
        }
        return try databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM chat_messages WHERE timestamp_ms < ?",
                arguments: [boundary]
            )
            return db.changesCount
        }
    }

    @discardableResult
    public func trim(channelID: String, keepingLatest limit: Int) throws -> Int {
        guard limit >= 0 else {
            throw Error.invalidLimit
        }
        return try databaseQueue.write { db in
            if limit == 0 {
                try db.execute(
                    sql: "DELETE FROM chat_messages WHERE channel_id = ?",
                    arguments: [channelID]
                )
            } else {
                try db.execute(
                    sql: """
                    DELETE FROM chat_messages
                    WHERE channel_id = ?
                      AND rowid NOT IN (
                          SELECT rowid
                          FROM chat_messages
                          WHERE channel_id = ?
                          ORDER BY timestamp_ms DESC, message_id DESC
                          LIMIT ?
                      )
                    """,
                    arguments: [channelID, channelID, limit]
                )
            }
            return db.changesCount
        }
    }

    public func count(channelID: String? = nil) throws -> Int {
        try databaseQueue.read { db in
            if let channelID {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM chat_messages WHERE channel_id = ?",
                    arguments: [channelID]
                ) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_messages") ?? 0
        }
    }

    public func clear() throws {
        try databaseQueue.write { db in
            try db.execute(sql: "DELETE FROM chat_messages")
        }
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("chat-history-v1") { db in
            try db.execute(
                sql: """
                CREATE TABLE chat_messages (
                    channel_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    timestamp_ms INTEGER NOT NULL,
                    author_login TEXT NOT NULL,
                    message_text TEXT NOT NULL,
                    payload_format INTEGER NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (channel_id, message_id)
                )
                """
            )
            try db.execute(
                sql: """
                CREATE INDEX chat_messages_channel_timestamp
                ON chat_messages(channel_id, timestamp_ms DESC, message_id DESC)
                """
            )
            try db.execute(
                sql: """
                CREATE INDEX chat_messages_timestamp
                ON chat_messages(timestamp_ms)
                """
            )
        }
        return migrator
    }

    private static func upsert(
        message: ChatMessage,
        payload: Data,
        db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO chat_messages (
                channel_id,
                message_id,
                timestamp_ms,
                author_login,
                message_text,
                payload_format,
                payload
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(channel_id, message_id) DO UPDATE SET
                timestamp_ms = excluded.timestamp_ms,
                author_login = excluded.author_login,
                message_text = excluded.message_text,
                payload_format = excluded.payload_format,
                payload = excluded.payload
            """,
            arguments: [
                message.channelID,
                message.id,
                message.timestampMilliseconds,
                message.author.login,
                message.text,
                payloadFormatVersion,
                payload,
            ]
        )
    }
}
