import XCTest
@testable import gtl

final class GpsEventsDumpTests: XCTestCase {
    func testDumpListsSessionThenTabSeparatedPoints() {
        let session = TrackSession(
            id: 7,
            startedAt: 1_000,
            stoppedAt: 2_500,
            usageType: "BICYCLE",
            measurementSystem: "METRIC"
        )
        let event = GpsEvent(
            id: 3,
            sessionId: 7,
            timestamp: 1_000,
            latitude: 47.5,
            longitude: 19.25,
            altitude: 120.5,
            speed: 4.5,
            bearing: 90,
            accuracy: 5,
            satellitesInFix: 8,
            ambientTemperature: nil,
            accelX: 0.1,
            accelY: nil,
            accelZ: 1,
            leanAngle: 12,
            usageType: "BICYCLE",
            isPlacemark: false,
            eventKind: "MOVE",
            baroAltitude: nil,
            pressureHpa: 1013.25
        )
        let text = GpsEventsDump.text(session: session, events: [event])
        XCTAssertEqual(
            text,
            """
            id\t7
            started_at\t1000
            stopped_at\t2500
            usage_type\tBICYCLE
            measurement_system\tMETRIC

            id\tsession_id\ttimestamp\tlatitude\tlongitude\taltitude\tspeed\tbearing\taccuracy\tsatellites_in_fix\tambient_temperature\taccel_x\taccel_y\taccel_z\tlean_angle\tusage_type\tis_placemark\tevent_kind\tbaro_altitude\tpressure_hpa
            3\t7\t1000\t47.5\t19.25\t120.5\t4.5\t90\t5\t8\t\t0.1\t\t1\t12\tBICYCLE\t0\tMOVE\t\t1013.25
            """
        )
    }

    func testDumpLeavesStoppedAtEmptyWhenSessionIsOpen() {
        let session = TrackSession(
            id: 1,
            startedAt: 10,
            stoppedAt: nil,
            usageType: "RUNNER",
            measurementSystem: "METRIC"
        )
        let text = GpsEventsDump.text(session: session, events: [])
        XCTAssertTrue(text.contains("stopped_at\t\n"))
        XCTAssertTrue(text.contains("id\tsession_id\ttimestamp\t"))
        XCTAssertFalse(text.hasSuffix("\n\n"))
    }

    func testGridKeepsSessionApartFromColumns() {
        let session = TrackSession(
            id: 7,
            startedAt: 1_000,
            stoppedAt: 2_500,
            usageType: "BICYCLE",
            measurementSystem: "METRIC"
        )
        let event = GpsEvent(
            id: 3,
            sessionId: 7,
            timestamp: 1_000,
            latitude: 47.5,
            longitude: 19.25,
            altitude: nil,
            speed: nil,
            bearing: 0,
            accuracy: 5,
            satellitesInFix: 8,
            ambientTemperature: nil,
            accelX: nil,
            accelY: nil,
            accelZ: nil,
            leanAngle: nil,
            usageType: nil,
            isPlacemark: false,
            eventKind: "MOVE",
            baroAltitude: nil,
            pressureHpa: nil
        )
        let grid = GpsEventsDump.grid(from: GpsEventsDump.text(session: session, events: [event]))
        XCTAssertEqual(grid.sessionLines.first, "id\t7")
        XCTAssertEqual(grid.columns, GpsEventsDump.columns)
        XCTAssertEqual(grid.rows.count, 1)
        XCTAssertEqual(grid.rows[0][3], "47.5")
        XCTAssertEqual(grid.rows[0][5], "")
        let widths = GpsEventsDump.columnWidths(columns: grid.columns, rows: grid.rows)
        XCTAssertEqual(widths.count, grid.columns.count)
        XCTAssertGreaterThan(widths[3], widths[0])
    }
}
