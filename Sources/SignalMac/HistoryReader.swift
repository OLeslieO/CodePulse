import Foundation
import CSQLite
import SignalCore

public struct HistoryEntry: Identifiable {
    public let id: String
    public let title: String
    public let project: String
    public let status: String
    public let tokens: Int64
    public let updatedAt: Date
}

public enum HistoryReader {
    public static func read(home: String, limit: Int = 30) throws -> [HistoryEntry] {
        let state = URL(fileURLWithPath: home).appendingPathComponent("state_5.sqlite")
        let history = URL(fileURLWithPath: home).appendingPathComponent("thread_history_1.sqlite")
        func connect(_ path: String) throws -> OpaquePointer {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
                if let db { sqlite3_close(db) }
                throw SignalError.io("无法读取 Codex 历史数据库；请确认路径和版本")
            }
            sqlite3_busy_timeout(db, 200)
            return db
        }
        let db = try connect(state.path); defer { sqlite3_close(db) }
        let turns = try? connect(history.path); defer { if let turns { sqlite3_close(turns) } }
        var columns = Set<String>()
        var schema: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &schema, nil) == SQLITE_OK {
            while sqlite3_step(schema) == SQLITE_ROW {
                if let name = sqlite3_column_text(schema, 1) { columns.insert(String(cString: name)) }
            }
        }
        sqlite3_finalize(schema)
        let titleColumn = columns.contains("name") ? "COALESCE(NULLIF(name,''),title)" : "title"
        let sourceFilter = columns.contains("source") ? " AND (source IS NULL OR lower(source) NOT LIKE '%subagent%')" : ""
        var stmt: OpaquePointer?
        let sql = "SELECT id, substr(\(titleColumn),1,400), cwd, tokens_used, updated_at FROM threads WHERE archived=0\(sourceFilter) ORDER BY updated_at DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SignalError.io("Codex 数据库结构不兼容，历史读取已停止")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(max(1, min(limit, 100))))
        func string(_ stmt: OpaquePointer?, _ index: Int32) -> String {
            guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
            return String(cString: ptr)
        }
        var result: [HistoryEntry] = []
        var step = sqlite3_step(stmt)
        while step == SQLITE_ROW {
            let id = string(stmt, 0)
            var state = "历史记录 · 当前状态未知"
            if let turns {
                var ts: OpaquePointer?
                if sqlite3_prepare_v2(turns, "SELECT status FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1", -1, &ts, nil) == SQLITE_OK {
                    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(ts, 1, id, -1, transient)
                    if sqlite3_step(ts) == SQLITE_ROW {
                        switch string(ts, 0) {
                        case "completed": state = "最近记录：已完成"
                        case "failed": state = "最近记录：失败"
                        case "interrupted": state = "最近记录：已中断"
                        case "inProgress": state = "记录为进行中 · 实时状态未确认"
                        default: break
                        }
                    }
                }
                sqlite3_finalize(ts)
            }
            let title = String(string(stmt, 1).split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(160))
            result.append(HistoryEntry(id: id, title: title.isEmpty ? id : title, project: string(stmt, 2), status: state,
                tokens: sqlite3_column_int64(stmt, 3), updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 4)))))
            step = sqlite3_step(stmt)
        }
        guard step == SQLITE_DONE else { throw SignalError.io("Codex 历史暂时忙碌或读取失败，稍后重试") }
        return result
    }
}
