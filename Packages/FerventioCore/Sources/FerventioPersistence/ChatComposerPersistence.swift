import Foundation
import GRDB

public struct SentChatMessageRecord: Equatable, Sendable, Identifiable {
    public let id: String
    public let channelID: String
    public let text: String
    public let sentAtMilliseconds: Int64

    public init(
        id: String,
        channelID: String,
        text: String,
        sentAtMilliseconds: Int64
    ) {
        self.id = id
        self.channelID = channelID
        self.text = text
        self.sentAtMilliseconds = sentAtMilliseconds
    }
}

public extension PersistenceStore {
    func saveDraft(
        channelID: String,
        text: String,
        updatedAtMilliseconds: Int64
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO chat_drafts (channel_id, message_text, updated_at_ms)
                VALUES (?, ?, ?)
                ON CONFLICT(channel_id) DO UPDATE SET
                    message_text = excluded.message_text,
                    updated_at_ms = excluded.updated_at_ms
                """,
                arguments: [channelID, text, updatedAtMilliseconds]
            )
        }
    }

    func draft(channelID: String) throws -> String? {
        try databaseQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT message_text FROM chat_drafts WHERE channel_id = ?",
                arguments: [channelID]
            )
        }
    }

    func deleteDraft(channelID: String) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM chat_drafts WHERE channel_id = ?",
                arguments: [channelID]
            )
        }
    }

    func recordSentMessage(
        _ entry: SentChatMessageRecord,
        keepingLatest limit: Int
    ) throws {
        guard limit > 0 else {
            throw Error.invalidLimit
        }
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO chat_sent_history (
                    channel_id,
                    entry_id,
                    sent_at_ms,
                    message_text
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(channel_id, entry_id) DO UPDATE SET
                    sent_at_ms = excluded.sent_at_ms,
                    message_text = excluded.message_text
                """,
                arguments: [
                    entry.channelID,
                    entry.id,
                    entry.sentAtMilliseconds,
                    entry.text,
                ]
            )
            try db.execute(
                sql: """
                DELETE FROM chat_sent_history
                WHERE channel_id = ?
                  AND rowid NOT IN (
                      SELECT rowid
                      FROM chat_sent_history
                      WHERE channel_id = ?
                      ORDER BY sent_at_ms DESC, entry_id DESC
                      LIMIT ?
                  )
                """,
                arguments: [entry.channelID, entry.channelID, limit]
            )
        }
    }

    func sentMessages(channelID: String, limit: Int) throws -> [SentChatMessageRecord] {
        guard limit > 0 else {
            throw Error.invalidLimit
        }
        let rows = try databaseQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT entry_id, channel_id, message_text, sent_at_ms
                FROM chat_sent_history
                WHERE channel_id = ?
                ORDER BY sent_at_ms DESC, entry_id DESC
                LIMIT ?
                """,
                arguments: [channelID, limit]
            )
        }
        return rows.map { row in
            SentChatMessageRecord(
                id: row["entry_id"],
                channelID: row["channel_id"],
                text: row["message_text"],
                sentAtMilliseconds: row["sent_at_ms"]
            )
        }
    }

    func clearSentMessages(channelID: String) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM chat_sent_history WHERE channel_id = ?",
                arguments: [channelID]
            )
        }
    }
}
