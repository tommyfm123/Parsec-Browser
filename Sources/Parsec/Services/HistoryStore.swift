import Foundation
import SQLite3

struct HistoryEntry: Hashable {
    let url: URL
    let title: String
    let visitCount: Int
    let lastVisited: Date
}

final class HistoryStore {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS visits (
            profile TEXT NOT NULL,
            url TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            visit_count INTEGER NOT NULL DEFAULT 1,
            last_visit REAL NOT NULL,
            PRIMARY KEY (profile, url)
        );
        CREATE INDEX IF NOT EXISTS visits_rank ON visits (profile, visit_count DESC, last_visit DESC);
        """
    private static let recordVisitSQL = """
        INSERT INTO visits (profile, url, title, visit_count, last_visit) VALUES (?1, ?2, ?3, 1, ?4)
        ON CONFLICT (profile, url) DO UPDATE SET
            visit_count = visit_count + 1,
            last_visit = excluded.last_visit,
            title = CASE WHEN excluded.title = '' THEN title ELSE excluded.title END;
        """
    private static let searchSQL = """
        SELECT url, title, visit_count, last_visit FROM visits
        WHERE profile = ?1 AND (url LIKE ?2 ESCAPE '\\' OR title LIKE ?2 ESCAPE '\\')
        ORDER BY visit_count DESC, last_visit DESC
        LIMIT ?3;
        """
    private static let allVisitsSQL = """
        SELECT url, title, visit_count, last_visit FROM visits
        WHERE profile = ?1
        ORDER BY last_visit DESC;
        """
    private static let deleteProfileSQL = "DELETE FROM visits WHERE profile = ?1;"

    private var database: OpaquePointer?

    init(fileURL: URL = StorageConstants.applicationSupportURL.appending(path: StorageConstants.historyFileName)) {
        guard sqlite3_open(fileURL.path, &database) == SQLITE_OK else { return }
        sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(database, Self.createTableSQL, nil, nil, nil)
    }

    deinit {
        sqlite3_close(database)
    }

    func recordVisit(profileID: UUID, url: URL, title: String) {
        execute(Self.recordVisitSQL) { statement in
            self.bind(profileID.uuidString, at: 1, in: statement)
            self.bind(url.absoluteString, at: 2, in: statement)
            self.bind(title, at: 3, in: statement)
            sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        }
    }

    func search(_ query: String, profileID: UUID, limit: Int = LifecycleConstants.historyResultLimit) -> [HistoryEntry] {
        let pattern = "%" + escapeLikePattern(query) + "%"
        var entries: [HistoryEntry] = []
        execute(Self.searchSQL, bindings: { statement in
            self.bind(profileID.uuidString, at: 1, in: statement)
            self.bind(pattern, at: 2, in: statement)
            sqlite3_bind_int(statement, 3, Int32(limit))
        }, onRow: { statement in
            guard let url = URL(string: self.columnText(statement, 0)) else { return }
            entries.append(HistoryEntry(url: url, title: self.columnText(statement, 1), visitCount: Int(sqlite3_column_int(statement, 2)), lastVisited: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))))
        })
        return entries
    }

    func allVisits(profileID: UUID) -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        execute(Self.allVisitsSQL, bindings: { statement in
            self.bind(profileID.uuidString, at: 1, in: statement)
        }, onRow: { statement in
            guard let url = URL(string: self.columnText(statement, 0)) else { return }
            entries.append(HistoryEntry(url: url, title: self.columnText(statement, 1), visitCount: Int(sqlite3_column_int(statement, 2)), lastVisited: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))))
        })
        return entries
    }

    func clear(profileID: UUID) {
        execute(Self.deleteProfileSQL) { statement in
            self.bind(profileID.uuidString, at: 1, in: statement)
        }
    }

    private func execute(_ sql: String, bindings: (OpaquePointer?) -> Void, onRow: ((OpaquePointer?) -> Void)? = nil) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            onRow?(statement)
        }
    }

    private func bind(_ text: String, at index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, text, -1, Self.sqliteTransient)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private func escapeLikePattern(_ query: String) -> String {
        query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
