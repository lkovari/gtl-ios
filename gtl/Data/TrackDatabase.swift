import Foundation
import SQLite3

struct TrackSession: Identifiable, Equatable {
    var id: Int64
    var startedAt: Int64
    var stoppedAt: Int64?
    var usageType: String
    var measurementSystem: String
}

struct GpsEvent: Identifiable, Equatable {
    var id: Int64
    var sessionId: Int64
    var timestamp: Int64
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var speed: Float?
    var bearing: Float
    var accuracy: Float
    var satellitesInFix: Int
    var ambientTemperature: Float?
    var accelX: Float?
    var accelY: Float?
    var accelZ: Float?
    var leanAngle: Float?
    var usageType: String?
    var isPlacemark: Bool
    var eventKind: String
    var baroAltitude: Double?
    var pressureHpa: Float?
}

actor TrackDatabase {
    private let handle: SqliteHandle
    private var db: OpaquePointer? { handle.raw }

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("gtl.db")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw DatabaseError.open
        }
        self.handle = SqliteHandle(handle)
        try sqliteExec(handle, "PRAGMA journal_mode=WAL;")
        try sqliteExec(handle, "PRAGMA foreign_keys=ON;")
        try sqliteExec(handle, """
        CREATE TABLE IF NOT EXISTS track_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at INTEGER NOT NULL,
          stopped_at INTEGER,
          usage_type TEXT NOT NULL,
          measurement_system TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS gps_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL REFERENCES track_sessions(id) ON DELETE CASCADE,
          timestamp INTEGER NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          altitude REAL,
          speed REAL,
          bearing REAL NOT NULL,
          accuracy REAL NOT NULL,
          satellites_in_fix INTEGER NOT NULL,
          ambient_temperature REAL,
          accel_x REAL,
          accel_y REAL,
          accel_z REAL,
          lean_angle REAL,
          usage_type TEXT,
          is_placemark INTEGER NOT NULL,
          event_kind TEXT NOT NULL,
          baro_altitude REAL,
          pressure_hpa REAL
        );
        CREATE INDEX IF NOT EXISTS idx_events_session ON gps_events(session_id);
        """)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    func startSession(at millis: Int64, usage: String, system: String) throws -> Int64 {
        try run("INSERT INTO track_sessions (started_at, usage_type, measurement_system) VALUES (?, ?, ?);", bindings: [
            .int(millis), .text(usage), .text(system)
        ])
        return sqlite3_last_insert_rowid(db)
    }

    func insert(_ event: GpsEvent) throws {
        try run("""
        INSERT INTO gps_events (
          session_id, timestamp, latitude, longitude, altitude, speed, bearing, accuracy, satellites_in_fix,
          ambient_temperature, accel_x, accel_y, accel_z, lean_angle, usage_type, is_placemark, event_kind,
          baro_altitude, pressure_hpa
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, bindings: [
            .int(event.sessionId), .int(event.timestamp), .double(event.latitude), .double(event.longitude),
            .optionalDouble(event.altitude), .optionalDouble(event.speed.map(Double.init)), .double(Double(event.bearing)),
            .double(Double(event.accuracy)), .int(Int64(event.satellitesInFix)),
            .optionalDouble(event.ambientTemperature.map(Double.init)),
            .optionalDouble(event.accelX.map(Double.init)), .optionalDouble(event.accelY.map(Double.init)),
            .optionalDouble(event.accelZ.map(Double.init)), .optionalDouble(event.leanAngle.map(Double.init)),
            .optionalText(event.usageType), .int(event.isPlacemark ? 1 : 0), .text(event.eventKind),
            .optionalDouble(event.baroAltitude), .optionalDouble(event.pressureHpa.map(Double.init))
        ])
    }

    func stopSession(id: Int64, at millis: Int64) throws {
        try run("UPDATE track_sessions SET stopped_at = ? WHERE id = ?;", bindings: [.int(millis), .int(id)])
    }

    func sessions() throws -> [TrackSession] {
        try query("SELECT id, started_at, stopped_at, usage_type, measurement_system FROM track_sessions ORDER BY started_at DESC;") { statement in
            TrackSession(
                id: sqlite3_column_int64(statement, 0),
                startedAt: sqlite3_column_int64(statement, 1),
                stoppedAt: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 2),
                usageType: text(statement, 3),
                measurementSystem: text(statement, 4)
            )
        }
    }

    func events(sessionId: Int64) throws -> [GpsEvent] {
        try query("SELECT id, session_id, timestamp, latitude, longitude, altitude, speed, bearing, accuracy, satellites_in_fix, ambient_temperature, accel_x, accel_y, accel_z, lean_angle, usage_type, is_placemark, event_kind, baro_altitude, pressure_hpa FROM gps_events WHERE session_id = ? ORDER BY timestamp ASC;", bindings: [.int(sessionId)]) { statement in
            GpsEvent(
                id: sqlite3_column_int64(statement, 0),
                sessionId: sqlite3_column_int64(statement, 1),
                timestamp: sqlite3_column_int64(statement, 2),
                latitude: sqlite3_column_double(statement, 3),
                longitude: sqlite3_column_double(statement, 4),
                altitude: optionalDouble(statement, 5),
                speed: optionalDouble(statement, 6).map { Float($0) },
                bearing: Float(sqlite3_column_double(statement, 7)),
                accuracy: Float(sqlite3_column_double(statement, 8)),
                satellitesInFix: Int(sqlite3_column_int64(statement, 9)),
                ambientTemperature: optionalDouble(statement, 10).map { Float($0) },
                accelX: optionalDouble(statement, 11).map { Float($0) },
                accelY: optionalDouble(statement, 12).map { Float($0) },
                accelZ: optionalDouble(statement, 13).map { Float($0) },
                leanAngle: optionalDouble(statement, 14).map { Float($0) },
                usageType: sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : text(statement, 15),
                isPlacemark: sqlite3_column_int64(statement, 16) != 0,
                eventKind: text(statement, 17),
                baroAltitude: optionalDouble(statement, 18),
                pressureHpa: optionalDouble(statement, 19).map { Float($0) }
            )
        }
    }

    func deleteSession(id: Int64) throws {
        try run("DELETE FROM track_sessions WHERE id = ?;", bindings: [.int(id)])
    }

    func openSession() throws -> TrackSession? {
        let rows = try query("SELECT id, started_at, stopped_at, usage_type, measurement_system FROM track_sessions WHERE stopped_at IS NULL ORDER BY id DESC LIMIT 1;") { statement in
            TrackSession(
                id: sqlite3_column_int64(statement, 0),
                startedAt: sqlite3_column_int64(statement, 1),
                stoppedAt: nil,
                usageType: text(statement, 3),
                measurementSystem: text(statement, 4)
            )
        }
        return rows.first
    }

    private func exec(_ sql: String) throws {
        try sqliteExec(db, sql)
    }

    private enum Binding {
        case int(Int64)
        case double(Double)
        case text(String)
        case optionalDouble(Double?)
        case optionalText(String?)
    }

    private func run(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.exec }
        defer { sqlite3_finalize(statement) }
        bind(statement, bindings)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.exec }
    }

    private func query<T>(_ sql: String, bindings: [Binding] = [], map: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DatabaseError.exec }
        defer { sqlite3_finalize(statement) }
        bind(statement, bindings)
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(map(statement))
        }
        return rows
    }

    private func bind(_ statement: OpaquePointer?, _ bindings: [Binding]) {
        for (index, binding) in bindings.enumerated() {
            let i = Int32(index + 1)
            switch binding {
            case .int(let value):
                sqlite3_bind_int64(statement, i, value)
            case .double(let value):
                sqlite3_bind_double(statement, i, value)
            case .text(let value):
                sqlite3_bind_text(statement, i, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .optionalDouble(let value):
                if let value { sqlite3_bind_double(statement, i, value) } else { sqlite3_bind_null(statement, i) }
            case .optionalText(let value):
                if let value { sqlite3_bind_text(statement, i, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                else { sqlite3_bind_null(statement, i) }
            }
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
    }
}

enum DatabaseError: Error {
    case open
    case exec
}

private func sqliteExec(_ db: OpaquePointer?, _ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.exec }
}

final class SqliteHandle: @unchecked Sendable {
    let raw: OpaquePointer?
    init(_ raw: OpaquePointer?) { self.raw = raw }
    deinit {
        if let raw { sqlite3_close(raw) }
    }
}

actor PlaceIndex {
    private let handle: SqliteHandle
    private var db: OpaquePointer? { handle.raw }

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("map-search.db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw DatabaseError.open }
        self.handle = SqliteHandle(handle)
        try sqliteExec(handle, "CREATE TABLE IF NOT EXISTS index_state (path TEXT PRIMARY KEY, bytes INTEGER, modified INTEGER, done INTEGER);")
        try sqliteExec(handle, "CREATE VIRTUAL TABLE IF NOT EXISTS places USING fts5(folded, name UNINDEXED, kind UNINDEXED, lat UNINDEXED, lon UNINDEXED);")
    }

    func isReady(path: String, bytes: Int64, modified: Int64) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT done FROM index_state WHERE path = ? AND bytes = ? AND modified = ? AND done = 1 LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(statement, 2, bytes)
        sqlite3_bind_int64(statement, 3, modified)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func replaceAll(path: String, bytes: Int64, modified: Int64, rows: [IndexedPlace]) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try exec("DELETE FROM places;")
            try exec("DELETE FROM index_state;")
            for row in rows.prefix(MapSearch.maxIndexedPlaces) {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT INTO places (folded, name, kind, lat, lon) VALUES (?, ?, ?, ?, ?);", -1, &statement, nil) == SQLITE_OK else {
                    continue
                }
                sqlite3_bind_text(statement, 1, row.folded, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(statement, 2, row.name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(statement, 3, row.kind, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(statement, 4, row.latitude)
                sqlite3_bind_double(statement, 5, row.longitude)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            var state: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO index_state (path, bytes, modified, done) VALUES (?, ?, ?, 1);", -1, &state, nil) == SQLITE_OK, let state {
                sqlite3_bind_text(state, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int64(state, 2, bytes)
                sqlite3_bind_int64(state, 3, modified)
                sqlite3_step(state)
                sqlite3_finalize(state)
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func search(match: String, limit: Int) throws -> [MapSearchCandidate] {
        var statement: OpaquePointer?
        let sql = "SELECT name, kind, lat, lon FROM places WHERE places MATCH ? LIMIT ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, match, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(statement, 2, Int32(limit))
        var rows: [MapSearchCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let kindRaw = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Place"
            rows.append(MapSearchCandidate(
                name: name,
                nameFold: MapSearch.fold(name),
                kind: MapPlaceKind(rawValue: kindRaw) ?? .Place,
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3)
            ))
        }
        return rows
    }

    private func exec(_ sql: String) throws {
        try sqliteExec(db, sql)
    }
}
