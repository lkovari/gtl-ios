import Foundation
import UIKit

struct TripleTapGate {
    private(set) var count = 0
    private var last: Date?
    static let window: TimeInterval = 0.5

    mutating func register(at time: Date) -> Bool {
        if let last, time.timeIntervalSince(last) <= Self.window {
            count += 1
        } else {
            count = 1
        }
        last = time
        if count >= 3 {
            count = 0
            last = nil
            return true
        }
        return false
    }
}

struct GpsEventsGrid {
    var sessionLines: [String]
    var columns: [String]
    var rows: [[String]]
}

enum GpsEventsDump {
    static let cellFontSize: CGFloat = 12
    static let columns = [
        "id", "session_id", "timestamp", "latitude", "longitude", "altitude", "speed", "bearing",
        "accuracy", "satellites_in_fix", "ambient_temperature", "accel_x", "accel_y", "accel_z",
        "lean_angle", "usage_type", "is_placemark", "event_kind", "baro_altitude", "pressure_hpa"
    ]

    static func text(session: TrackSession, events: [GpsEvent]) -> String {
        let stopped = session.stoppedAt.map(String.init) ?? ""
        let header = [
            "id\t\(session.id)",
            "started_at\t\(session.startedAt)",
            "stopped_at\t\(stopped)",
            "usage_type\t\(session.usageType)",
            "measurement_system\t\(session.measurementSystem)",
            "",
            columns.joined(separator: "\t")
        ]
        let rows = events.map(row)
        return (header + rows).joined(separator: "\n")
    }

    static func grid(from text: String) -> GpsEventsGrid {
        let parts = text.components(separatedBy: "\n\n")
        let sessionLines = parts.first?.components(separatedBy: "\n") ?? []
        let tableLines = parts.count > 1 ? parts[1].components(separatedBy: "\n") : []
        let columns = tableLines.first?.components(separatedBy: "\t") ?? []
        let rows = tableLines.dropFirst().map { $0.components(separatedBy: "\t") }
        return GpsEventsGrid(sessionLines: sessionLines, columns: columns, rows: rows)
    }

    static func columnWidths(columns: [String], rows: [[String]]) -> [CGFloat] {
        let cellFont = UIFont.monospacedSystemFont(ofSize: cellFontSize, weight: .regular)
        let headerFont = UIFont.monospacedSystemFont(ofSize: cellFontSize, weight: .semibold)
        return columns.indices.map { index in
            var width = (columns[index] as NSString).size(withAttributes: [.font: headerFont]).width
            for row in rows {
                let value = index < row.count ? row[index] : ""
                width = max(width, (value as NSString).size(withAttributes: [.font: cellFont]).width)
            }
            return ceil(width) + 16
        }
    }

    private static func row(_ event: GpsEvent) -> String {
        let cells = [
            String(event.id),
            String(event.sessionId),
            String(event.timestamp),
            decimal(event.latitude),
            decimal(event.longitude),
            decimal(event.altitude),
            decimal(event.speed.map(Double.init)),
            decimal(Double(event.bearing)),
            decimal(Double(event.accuracy)),
            String(event.satellitesInFix),
            decimal(event.ambientTemperature.map(Double.init)),
            decimal(event.accelX.map(Double.init)),
            decimal(event.accelY.map(Double.init)),
            decimal(event.accelZ.map(Double.init)),
            decimal(event.leanAngle.map(Double.init)),
            event.usageType ?? "",
            event.isPlacemark ? "1" : "0",
            event.eventKind,
            decimal(event.baroAltitude),
            decimal(event.pressureHpa.map(Double.init))
        ]
        return cells.joined(separator: "\t")
    }

    private static func decimal(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}
