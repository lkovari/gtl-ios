import Foundation

enum EventKind: String, Codable {
    case START
    case MOVE
    case PAUSE
    case STOP

    func kmlPlacemarkName() -> String {
        switch self {
        case .START: return "Start"
        case .MOVE: return "Move"
        case .PAUSE: return "Pause"
        case .STOP: return "Stop"
        }
    }

    func kmlDrawOrder() -> Int {
        switch self {
        case .STOP: return 10
        case .START: return 5
        case .PAUSE: return 1
        case .MOVE: return 0
        }
    }
}

enum Units {
    static func formatSpeed(_ metersPerSecond: Float, _ system: MeasurementSystem) -> String {
        switch system {
        case .METRIC:
            return String(format: "%.1f km/h", locale: posix, metersPerSecond * 3.6)
        case .IMPERIAL:
            return String(format: "%.1f mph", locale: posix, metersPerSecond * 2.2369363)
        case .ICAO:
            return String(format: "%.1f kt", locale: posix, metersPerSecond * 1.9438445)
        }
    }

    static func formatDistance(_ meters: Double, _ system: MeasurementSystem) -> String {
        switch system {
        case .METRIC:
            if meters >= 1000 {
                return String(format: "%.2f km", locale: posix, meters / 1000)
            }
            return String(format: "%.0f m", locale: posix, meters)
        case .IMPERIAL:
            let miles = meters / 1609.344
            if miles >= 0.1 {
                return String(format: "%.2f mi", locale: posix, miles)
            }
            return String(format: "%.0f ft", locale: posix, meters * 3.28084)
        case .ICAO:
            return String(format: "%.2f NM", locale: posix, meters / 1852)
        }
    }

    static func formatAltitude(_ meters: Double, _ system: MeasurementSystem) -> String {
        switch system {
        case .METRIC:
            return String(format: "%.0f m", locale: posix, meters)
        case .IMPERIAL, .ICAO:
            return String(format: "%.0f ft", locale: posix, meters * 3.28084)
        }
    }

    static func formatDuration(_ millis: Int64) -> String {
        let totalSeconds = max(0, millis / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func formatBalloonDuration(_ millis: Int64) -> String {
        let totalSeconds = max(0, millis / 1000)
        if totalSeconds <= 60 { return "\(totalSeconds) s" }
        if totalSeconds < 3600 { return "\(totalSeconds / 60) min" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", locale: posix, hours, minutes, seconds)
    }

    static func formatTemperature(_ celsius: Float?) -> String {
        guard let celsius else { return "—" }
        return String(format: "%.1f °C", locale: posix, celsius)
    }

    static func formatTemperature(_ celsius: Float, _ system: MeasurementSystem) -> String {
        switch system {
        case .METRIC, .ICAO:
            return String(format: "%.1f °C", locale: posix, celsius)
        case .IMPERIAL:
            return String(format: "%.1f °F", locale: posix, celsius * 1.8 + 32)
        }
    }

    static func hudSpeedNumber(_ metersPerSecond: Float, _ system: MeasurementSystem) -> String {
        let value: Float
        switch system {
        case .METRIC: value = metersPerSecond * 3.6
        case .IMPERIAL: value = metersPerSecond * 2.2369363
        case .ICAO: value = metersPerSecond * 1.9438445
        }
        return String(format: "%.0f", locale: posix, value)
    }

    static func hudSpeedUnit(_ system: MeasurementSystem) -> String {
        switch system {
        case .METRIC: return "km/h"
        case .IMPERIAL: return "mph"
        case .ICAO: return "kt"
        }
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}

struct TrackSample {
    var timestampMillis: Int64
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var speedMps: Float?
    var bearing: Float
    var ambientTemperature: Float?
    var eventKind: EventKind
}

struct TemperatureRange: Equatable {
    var minCelsius: Float
    var maxCelsius: Float
}

struct TrackStats: Equatable {
    var pointCount: Int
    var odometerMeters: Double
    var elapsedMillis: Int64
    var movingMillis: Int64
    var waitingMillis: Int64
    var maxSpeedMps: Float
    var averageSpeedMps: Float
    var maxAltitude: Double
    var minAltitude: Double
    var temperatureRange: TemperatureRange?
}

enum TrackStatsCalculator {
    private static let movingSpeedMps: Float = 0.5

    static func compute(_ samples: [TrackSample]) -> TrackStats {
        if samples.isEmpty {
            return TrackStats(
                pointCount: 0, odometerMeters: 0, elapsedMillis: 0, movingMillis: 0, waitingMillis: 0,
                maxSpeedMps: 0, averageSpeedMps: 0, maxAltitude: 0, minAltitude: 0, temperatureRange: nil
            )
        }
        var odometer = 0.0
        var moving: Int64 = 0
        var waiting: Int64 = 0
        if samples.count > 1 {
            for index in 1..<samples.count {
                let previous = samples[index - 1]
                let current = samples[index]
                odometer += FixAcceptance.haversineMeters(previous.latitude, previous.longitude, current.latitude, current.longitude)
                let dt = max(0, current.timestampMillis - previous.timestampMillis)
                if let speed = current.speedMps {
                    if speed >= movingSpeedMps { moving += dt } else { waiting += dt }
                }
            }
        }
        let elapsed = max(0, samples[samples.count - 1].timestampMillis - samples[0].timestampMillis)
        let temps = samples.compactMap(\.ambientTemperature)
        let temperatureRange = temps.isEmpty ? nil : TemperatureRange(minCelsius: temps.min() ?? 0, maxCelsius: temps.max() ?? 0)
        let altitudes = samples.compactMap(\.altitude)
        let speeds = samples.compactMap(\.speedMps)
        let movingElapsedSeconds = Double(moving) / 1000
        let average: Float = movingElapsedSeconds > 0 ? Float(odometer / movingElapsedSeconds) : 0
        return TrackStats(
            pointCount: samples.count,
            odometerMeters: odometer,
            elapsedMillis: elapsed,
            movingMillis: moving,
            waitingMillis: waiting,
            maxSpeedMps: speeds.max() ?? 0,
            averageSpeedMps: average,
            maxAltitude: altitudes.max() ?? 0,
            minAltitude: altitudes.min() ?? 0,
            temperatureRange: temperatureRange
        )
    }

    static func cumulativeOdometerMeters(_ points: [GeoPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var distances = [0.0]
        var odometer = 0.0
        if points.count > 1 {
            for index in 1..<points.count {
                odometer += FixAcceptance.haversineMeters(
                    points[index - 1].latitude, points[index - 1].longitude, points[index].latitude, points[index].longitude
                )
                distances.append(odometer)
            }
        }
        return distances
    }
}

struct TrackLogEvent: Equatable {
    var timestampMillis: Int64
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var speedMps: Float?
    var kind: EventKind
    var tempCelsius: Float?
    var leanAngle: Float?
    var usageType: String?
    var baroAltitude: Double?
    var pressureHpa: Float?

    func point() -> GeoPoint { GeoPoint(latitude: latitude, longitude: longitude, altitude: altitude) }

    func replacingKind(_ kind: EventKind) -> TrackLogEvent {
        var copy = self
        copy.kind = kind
        return copy
    }
}

struct TrackLogMarker {
    var kind: EventKind
    var event: TrackLogEvent
}

enum TrackLogExport {
    static let markerOverlapMeters = 1.0

    static func path(_ events: [TrackLogEvent]) -> [TrackLogEvent] {
        guard let last = events.last else { return [] }
        if last.kind == .STOP && events.count > 1 {
            return Array(events.dropLast())
        }
        return events
    }

    static func markers(_ events: [TrackLogEvent]) -> [TrackLogMarker] {
        let route = path(events)
        guard let first = route.first else { return [] }
        let startEvent = first.replacingKind(.START)
        let stopSource = events.last { $0.kind == .STOP }
        let stopEvent: TrackLogEvent?
        if let stopSource, let last = route.last {
            var stop = last
            stop.kind = .STOP
            stop.timestampMillis = stopSource.timestampMillis
            stop.speedMps = stopSource.speedMps
            stop.tempCelsius = stopSource.tempCelsius
            stop.leanAngle = stopSource.leanAngle
            stop.usageType = stopSource.usageType
            stop.baroAltitude = stopSource.baroAltitude
            stop.pressureHpa = stopSource.pressureHpa
            stopEvent = stop
        } else {
            stopEvent = nil
        }
        let pauses = firstOfEachPauseRun(route).filter { pause in
            !near(pause, startEvent) && (stopEvent == nil || !near(pause, stopEvent ?? pause))
        }
        var result = [TrackLogMarker(kind: .START, event: startEvent)]
        result.append(contentsOf: pauses.map { TrackLogMarker(kind: .PAUSE, event: $0) })
        if let stopEvent {
            result.append(TrackLogMarker(kind: .STOP, event: stopEvent))
        }
        return result
    }

    static func samplesForStats(_ events: [TrackLogEvent]) -> [TrackSample] {
        let route = path(events)
        guard !route.isEmpty else { return [] }
        let stop = events.last { $0.kind == .STOP }
        let forStats: [TrackLogEvent]
        if let stop, let last = route.last {
            var extra = last
            extra.timestampMillis = stop.timestampMillis
            extra.kind = .STOP
            extra.speedMps = 0
            forStats = route + [extra]
        } else {
            forStats = route
        }
        return forStats.map { event in
            TrackSample(
                timestampMillis: event.timestampMillis,
                latitude: event.latitude,
                longitude: event.longitude,
                altitude: event.altitude,
                speedMps: event.speedMps,
                bearing: 0,
                ambientTemperature: event.tempCelsius,
                eventKind: event.kind
            )
        }
    }

    private static func firstOfEachPauseRun(_ path: [TrackLogEvent]) -> [TrackLogEvent] {
        var firsts: [TrackLogEvent] = []
        var previousWasPause = false
        for event in path {
            let isPause = event.kind == .PAUSE
            if isPause && !previousWasPause { firsts.append(event) }
            previousWasPause = isPause
        }
        return firsts
    }

    private static func near(_ left: TrackLogEvent, _ right: TrackLogEvent) -> Bool {
        FixAcceptance.haversineMeters(left.latitude, left.longitude, right.latitude, right.longitude) < markerOverlapMeters
    }
}

enum KmlDescriptions {
    static func balloon(
        kind: EventKind,
        timestampMillis: Int64,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        baroAltitude: Double? = nil,
        speedMps: Float?,
        tempCelsius: Float?,
        maxSpeedMps: Float? = nil,
        averageSpeedMps: Float? = nil,
        elapsedMillis: Int64 = 0,
        odometerMeters: Double = 0,
        system: MeasurementSystem = .METRIC
    ) -> String {
        let temp = tempCelsius == nil ? "N/A" : Units.formatTemperature(tempCelsius ?? 0, system)
        let baro = baroAltitude == nil ? "-" : Units.formatAltitude(baroAltitude ?? 0, system)
        let altitudeText = altitude == nil ? "-" : Units.formatAltitude(altitude ?? 0, system)
        var lines = [
            formatTime(timestampMillis),
            "temp=\(temp)",
            "lon=\(formatCoord(longitude))",
            "lat=\(formatCoord(latitude))",
            "Altitude: \(altitudeText)",
            "Baro: \(baro)"
        ]
        switch kind {
        case .PAUSE:
            let speedText = speedMps == nil ? "-" : Units.formatSpeed(speedMps ?? 0, system)
            lines.append("Speed: \(speedText)")
            lines.append("duration=\(Units.formatBalloonDuration(elapsedMillis))")
            lines.append("distance=\(Units.formatDistance(odometerMeters, system))")
        case .STOP:
            lines.append("Avg. Speed: \(Units.formatSpeed(averageSpeedMps ?? 0, system))")
            lines.append("Max speed: \(Units.formatSpeed(maxSpeedMps ?? 0, system))")
            lines.append("duration=\(Units.formatBalloonDuration(elapsedMillis))")
            lines.append("distance=\(Units.formatDistance(odometerMeters, system))")
        case .START, .MOVE:
            break
        }
        return lines.joined(separator: "\n")
    }

    private static func formatTime(_ timestampMillis: Int64) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d:%02d:%02d %02d:%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    private static func formatCoord(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct KmlPlacemark {
    var name: String
    var kind: EventKind
    var point: GeoPoint
    var description: String
    var drawOrder: Int
}

struct KmlVertex {
    var point: GeoPoint
    var timestampMillis: Int64
    var speedMps: Float?
    var odometerMeters: Double
    var baroAltitude: Double?
}

struct KmlTrack {
    var name: String
    var points: [KmlVertex]
    var placemarks: [KmlPlacemark]
}

struct KmlDocument {
    var name: String
    var trackColorAabbggrr: String
    var trackWidth: Int
    var tracks: [KmlTrack]
}

enum KmlTrackBuilder {
    static func build(
        name: String,
        events: [TrackLogEvent],
        system: MeasurementSystem,
        qnhHpa: Float = BaroAltitude.standardAtmosphereHpa,
        offsetHpa: Float = 0
    ) -> KmlTrack {
        let stats = TrackStatsCalculator.compute(TrackLogExport.samplesForStats(events))
        let route = TrackLogExport.path(events)
        let odometers = TrackStatsCalculator.cumulativeOdometerMeters(route.map { $0.point() })
        let points = route.enumerated().map { index, event in
            KmlVertex(
                point: event.point(),
                timestampMillis: event.timestampMillis,
                speedMps: event.speedMps,
                odometerMeters: index < odometers.count ? odometers[index] : 0,
                baroAltitude: baroMeters(event, qnhHpa, offsetHpa)
            )
        }
        let placemarks = TrackLogExport.markers(events).map { marker in
            KmlPlacemark(
                name: marker.kind.kmlPlacemarkName(),
                kind: marker.kind,
                point: marker.event.point(),
                description: KmlDescriptions.balloon(
                    kind: marker.kind,
                    timestampMillis: marker.event.timestampMillis,
                    latitude: marker.event.latitude,
                    longitude: marker.event.longitude,
                    altitude: marker.event.altitude,
                    baroAltitude: baroMeters(marker.event, qnhHpa, offsetHpa),
                    speedMps: marker.event.speedMps,
                    tempCelsius: marker.event.tempCelsius,
                    maxSpeedMps: marker.kind == .STOP ? stats.maxSpeedMps : nil,
                    averageSpeedMps: marker.kind == .STOP ? stats.averageSpeedMps : nil,
                    elapsedMillis: elapsedFor(marker, route),
                    odometerMeters: odometerFor(marker, route, odometers),
                    system: system
                ),
                drawOrder: marker.kind.kmlDrawOrder()
            )
        }
        return KmlTrack(name: name, points: points, placemarks: placemarks)
    }

    private static func baroMeters(_ event: TrackLogEvent, _ qnhHpa: Float, _ offsetHpa: Float) -> Double? {
        BaroAltitude.displayedMeters(
            pressureHpa: event.pressureHpa,
            storedBaro: event.baroAltitude,
            qnhHpa: qnhHpa,
            offsetHpa: offsetHpa,
            gpsMeters: event.altitude
        )
    }

    private static func elapsedFor(_ marker: TrackLogMarker, _ path: [TrackLogEvent]) -> Int64 {
        if marker.kind == .START || path.isEmpty { return 0 }
        return max(0, marker.event.timestampMillis - path[0].timestampMillis)
    }

    private static func odometerFor(_ marker: TrackLogMarker, _ path: [TrackLogEvent], _ odometers: [Double]) -> Double {
        guard !odometers.isEmpty else { return 0 }
        switch marker.kind {
        case .START: return odometers[0]
        case .STOP: return odometers[odometers.count - 1]
        default:
            if let index = path.firstIndex(where: { event in
                event.timestampMillis == marker.event.timestampMillis &&
                    event.latitude == marker.event.latitude &&
                    event.longitude == marker.event.longitude
            }) {
                return odometers[index]
            }
            return odometers[odometers.count - 1]
        }
    }
}

struct GpxWaypoint {
    var name: String
    var point: GeoPoint
    var timestampMillis: Int64
}

struct GpxTrackPoint {
    var point: GeoPoint
    var timestampMillis: Int64
}

struct GpxTrack {
    var name: String
    var points: [GpxTrackPoint]
    var waypoints: [GpxWaypoint]
}

struct GpxDocument {
    var tracks: [GpxTrack]
}

enum GpxExporter {
    static func export(_ document: GpxDocument) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"GTL\" xmlns=\"http://www.topografix.com/GPX/1/1\">"
        ]
        for track in document.tracks {
            for waypoint in track.waypoints {
                lines.append(contentsOf: waypointLines(waypoint))
            }
            lines.append("<trk>")
            lines.append("<name>\(escape(track.name))</name>")
            lines.append("<trkseg>")
            for point in track.points {
                lines.append(contentsOf: trackPointLines(point))
            }
            lines.append("</trkseg>")
            lines.append("</trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func waypointLines(_ waypoint: GpxWaypoint) -> [String] {
        var lines = ["<wpt lat=\"\(waypoint.point.latitude)\" lon=\"\(waypoint.point.longitude)\">"]
        if let altitude = waypoint.point.altitude { lines.append("<ele>\(altitude)</ele>") }
        lines.append("<time>\(utcWhen(waypoint.timestampMillis))</time>")
        lines.append("<name>\(escape(waypoint.name))</name>")
        lines.append("</wpt>")
        return lines
    }

    private static func trackPointLines(_ vertex: GpxTrackPoint) -> [String] {
        var lines = ["<trkpt lat=\"\(vertex.point.latitude)\" lon=\"\(vertex.point.longitude)\">"]
        if let altitude = vertex.point.altitude { lines.append("<ele>\(altitude)</ele>") }
        lines.append("<time>\(utcWhen(vertex.timestampMillis))</time>")
        lines.append("</trkpt>")
        return lines
    }

    static func utcWhen(_ timestampMillis: Int64) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let base = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        let frac = Int(timestampMillis % 1000)
        if frac == 0 { return base + "Z" }
        var digits = String(format: "%03d", frac)
        while digits.hasSuffix("0") { digits.removeLast() }
        return base + "." + digits + "Z"
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum KmlExporter {
    static func export(_ document: KmlDocument) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<kml xmlns=\"http://www.opengis.net/kml/2.2\" xmlns:gx=\"http://www.google.com/kml/ext/2.2\">",
            "<Document>",
            "<name>\(GpxExporter.escape(document.name))</name>"
        ]
        lines.append(contentsOf: styleLines(document.trackColorAabbggrr, document.trackWidth))
        lines.append(schemaLine)
        for track in document.tracks {
            lines.append("<Folder>")
            lines.append("<name>\(GpxExporter.escape(track.name))</name>")
            if !track.points.isEmpty {
                lines.append("<Placemark>")
                lines.append("<name>\(GpxExporter.escape(track.name))</name>")
                lines.append("<styleUrl>#track</styleUrl>")
                lines.append("<LineString>")
                lines.append("<tessellate>1</tessellate>")
                lines.append("<altitudeMode>clampToGround</altitudeMode>")
                lines.append("<coordinates>")
                for vertex in track.points {
                    lines.append("\(vertex.point.longitude),\(vertex.point.latitude),0")
                }
                lines.append("</coordinates>")
                lines.append("</LineString>")
                lines.append("</Placemark>")
                lines.append("<Placemark>")
                lines.append("<name>\(GpxExporter.escape(track.name))</name>")
                lines.append("<styleUrl>#trackData</styleUrl>")
                lines.append("<visibility>0</visibility>")
                lines.append("<gx:Track>")
                lines.append("<altitudeMode>clampToGround</altitudeMode>")
                for vertex in track.points {
                    lines.append("<when>\(GpxExporter.utcWhen(vertex.timestampMillis))</when>")
                }
                for vertex in track.points {
                    lines.append("<gx:coord>\(vertex.point.longitude) \(vertex.point.latitude) 0</gx:coord>")
                }
                lines.append("<ExtendedData>")
                lines.append("<SchemaData schemaUrl=\"#trackPoint\">")
                lines.append("<gx:SimpleArrayData name=\"speed\">")
                for vertex in track.points {
                    if let speed = vertex.speedMps {
                        lines.append("<gx:value>\(speed)</gx:value>")
                    } else {
                        lines.append("<gx:value>-</gx:value>")
                    }
                }
                lines.append("</gx:SimpleArrayData>")
                lines.append("<gx:SimpleArrayData name=\"odometer\">")
                for vertex in track.points {
                    lines.append("<gx:value>\(vertex.odometerMeters)</gx:value>")
                }
                lines.append("</gx:SimpleArrayData>")
                lines.append("<gx:SimpleArrayData name=\"alt\">")
                for vertex in track.points {
                    if let alt = vertex.point.altitude {
                        lines.append("<gx:value>\(alt)</gx:value>")
                    } else {
                        lines.append("<gx:value>-</gx:value>")
                    }
                }
                lines.append("</gx:SimpleArrayData>")
                lines.append("<gx:SimpleArrayData name=\"baro\">")
                for vertex in track.points {
                    if let baro = vertex.baroAltitude {
                        lines.append("<gx:value>\(baro)</gx:value>")
                    } else {
                        lines.append("<gx:value>-</gx:value>")
                    }
                }
                lines.append("</gx:SimpleArrayData>")
                lines.append("</SchemaData>")
                lines.append("</ExtendedData>")
                lines.append("</gx:Track>")
                lines.append("</Placemark>")
            }
            for mark in track.placemarks {
                lines.append("<Placemark>")
                lines.append("<name>\(GpxExporter.escape(mark.name))</name>")
                lines.append("<description><![CDATA[\(htmlDescription(mark.description))]]></description>")
                lines.append("<styleUrl>#\(styleId(mark.kind))</styleUrl>")
                if mark.drawOrder > 0 {
                    lines.append("<gx:drawOrder>\(mark.drawOrder)</gx:drawOrder>")
                }
                lines.append("<Point>")
                lines.append("<altitudeMode>clampToGround</altitudeMode>")
                lines.append("<coordinates>\(mark.point.longitude),\(mark.point.latitude),0</coordinates>")
                lines.append("</Point>")
                lines.append("</Placemark>")
            }
            lines.append("</Folder>")
        }
        lines.append("</Document>")
        lines.append("</kml>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func styleLines(_ color: String, _ width: Int) -> [String] {
        [
            "<Style id=\"track\"><LineStyle><color>\(color)</color><width>\(width)</width></LineStyle></Style>",
            "<Style id=\"trackData\"><LineStyle><color>00000000</color><width>0</width></LineStyle></Style>",
            iconStyle("start", "icons/play.png"),
            iconStyle("pause", "icons/pause.png"),
            iconStyle("stop", "icons/stop.png"),
            "<Style id=\"move\"><LabelStyle><scale>0</scale></LabelStyle></Style>"
        ]
    }

    private static let schemaLine = "<Schema id=\"trackPoint\"><gx:SimpleArrayField name=\"speed\" type=\"float\"><displayName>Speed (m/s)</displayName></gx:SimpleArrayField><gx:SimpleArrayField name=\"odometer\" type=\"float\"><displayName>Distance (m)</displayName></gx:SimpleArrayField><gx:SimpleArrayField name=\"alt\" type=\"float\"><displayName>GPS altitude (m)</displayName></gx:SimpleArrayField><gx:SimpleArrayField name=\"baro\" type=\"float\"><displayName>Baro (m)</displayName></gx:SimpleArrayField></Schema>"

    private static func iconStyle(_ id: String, _ href: String) -> String {
        "<Style id=\"\(id)\"><IconStyle><scale>0.8</scale><Icon><href>\(href)</href></Icon><hotSpot x=\"0.5\" y=\"0.5\" xunits=\"fraction\" yunits=\"fraction\"/></IconStyle><LabelStyle><scale>0</scale></LabelStyle><BalloonStyle><text><![CDATA[$[description]]]></text></BalloonStyle></Style>"
    }

    private static func styleId(_ kind: EventKind) -> String {
        switch kind {
        case .START: return "start"
        case .PAUSE: return "pause"
        case .STOP: return "stop"
        case .MOVE: return "move"
        }
    }

    private static func htmlDescription(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br/>")
            .replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
    }
}

enum KmzExporter {
    static func pack(kml: String, files: [String: Data]) -> Data {
        var archive = Data()
        var entries: [(name: String, offset: UInt32, size: UInt32)] = []
        func append(_ name: String, _ payload: Data) {
            let offset = UInt32(archive.count)
            var local = Data()
            local.append(uint32: 0x04034b50)
            local.append(uint16: 20)
            local.append(uint16: 0)
            local.append(uint16: 0)
            local.append(uint16: 0)
            local.append(uint16: 0)
            local.append(uint32: 0)
            local.append(uint32: UInt32(payload.count))
            local.append(uint32: UInt32(payload.count))
            let nameData = Data(name.utf8)
            local.append(uint16: UInt16(nameData.count))
            local.append(uint16: 0)
            local.append(nameData)
            local.append(payload)
            archive.append(local)
            entries.append((name, offset, UInt32(payload.count)))
        }
        append("doc.kml", Data(kml.utf8))
        for (name, bytes) in files {
            append(name, bytes)
        }
        let centralStart = UInt32(archive.count)
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            archive.append(uint32: 0x02014b50)
            archive.append(uint16: 20)
            archive.append(uint16: 20)
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint32: 0)
            archive.append(uint32: entry.size)
            archive.append(uint32: entry.size)
            archive.append(uint16: UInt16(nameData.count))
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint16: 0)
            archive.append(uint32: 0)
            archive.append(uint32: entry.offset)
            archive.append(nameData)
        }
        let centralSize = UInt32(archive.count) - centralStart
        archive.append(uint32: 0x06054b50)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint32: centralSize)
        archive.append(uint32: centralStart)
        archive.append(uint16: 0)
        return archive
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 2))
    }

    mutating func append(uint32 value: UInt32) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 4))
    }
}
