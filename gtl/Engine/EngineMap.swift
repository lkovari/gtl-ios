import Foundation

enum DouglasPeucker {
    static let minToleranceMeters = 1.0
    static let maxToleranceMeters = 20.0
    static let defaultToleranceMeters = 19.5

    static func clampTolerance(_ value: Double) -> Double {
        let clamped = min(maxToleranceMeters, max(minToleranceMeters, value))
        return clamped.rounded()
    }

    static func simplify(_ points: [GeoPoint], toleranceMeters: Double) -> [GeoPoint] {
        guard points.count >= 3 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplifyRange(points, 0, points.count - 1, toleranceMeters, &keep)
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    private static func simplifyRange(_ points: [GeoPoint], _ first: Int, _ last: Int, _ toleranceMeters: Double, _ keep: inout [Bool]) {
        var maxDistance = 0.0
        var farthest = first
        let start = points[first]
        let end = points[last]
        if first + 1 < last {
            for index in (first + 1)..<last {
                let distance = perpendicularDistanceMeters(start, end, points[index])
                if distance > maxDistance {
                    maxDistance = distance
                    farthest = index
                }
            }
        }
        if maxDistance > toleranceMeters && farthest != first {
            keep[farthest] = true
            simplifyRange(points, first, farthest, toleranceMeters, &keep)
            simplifyRange(points, farthest, last, toleranceMeters, &keep)
        }
    }

    private static func perpendicularDistanceMeters(_ start: GeoPoint, _ end: GeoPoint, _ point: GeoPoint) -> Double {
        let endXY = GeoProjection.eastNorth(originLat: start.latitude, originLon: start.longitude, lat: end.latitude, lon: end.longitude)
        let pointXY = GeoProjection.eastNorth(originLat: start.latitude, originLon: start.longitude, lat: point.latitude, lon: point.longitude)
        let dx = endXY.0
        let dy = endXY.1
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return GeoProjection.hypot(pointXY.0, pointXY.1) }
        let t = (pointXY.0 * dx + pointXY.1 * dy) / lengthSquared
        return GeoProjection.hypot(pointXY.0 - t * dx, pointXY.1 - t * dy)
    }
}

enum MapHudMode {
    case hidden
    case compact
    case full
}

enum MapHudVisibility {
    static func mode(logging: Bool, selectedSessionId: Int64?, hasFix _: Bool) -> MapHudMode {
        if selectedSessionId != nil && !logging { return .hidden }
        if logging { return .full }
        return .compact
    }
}

enum MapCameraMode {
    case fitTrack
    case followLive
    case free

    static func of(logging: Bool, keepWholeTrack: Bool, viewingSaved: Bool) -> MapCameraMode {
        if keepWholeTrack || viewingSaved { return .fitTrack }
        if logging { return .followLive }
        return .free
    }

    static func finishedTrackOnMap(logging: Bool, pointCount: Int) -> Bool {
        !logging && pointCount >= 2
    }
}

enum MapTrackVisibility {
    static func visible(logging: Bool, showLastTrackOnMap: Bool, selectedSessionId: Int64?, mapCleared: Bool = false) -> Bool {
        if logging { return true }
        if mapCleared { return false }
        return showLastTrackOnMap || selectedSessionId != nil
    }
}

struct CompassDisplay: Equatable {
    var degrees: Float
    var trueNorth: Bool
    var missingFix: Bool
}

enum CompassHeading {
    static func wrapDegrees(_ degrees: Float) -> Float {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    static func display(magneticDegrees: Float, wantTrue: Bool, declinationDegrees: Float?) -> CompassDisplay {
        let magnetic = wrapDegrees(magneticDegrees)
        if !wantTrue { return CompassDisplay(degrees: magnetic, trueNorth: false, missingFix: false) }
        guard let declinationDegrees, declinationDegrees.isFinite else {
            return CompassDisplay(degrees: magnetic, trueNorth: false, missingFix: true)
        }
        return CompassDisplay(degrees: wrapDegrees(magnetic + declinationDegrees), trueNorth: true, missingFix: false)
    }

    static func needsFigureEight(_ headingAccuracyDegrees: Int) -> Bool {
        headingAccuracyDegrees < 0 || headingAccuracyDegrees > 25
    }
}

enum TargetPointer: Equatable {
    case ring
    case aim(relativeDegrees: Float, dimmed: Bool)

    static func initialBearingDegrees(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double? {
        guard coordsFinite(fromLatitude, fromLongitude, toLatitude, toLongitude) else { return nil }
        let lat1 = fromLatitude * .pi / 180
        let lat2 = toLatitude * .pi / 180
        let dLon = (toLongitude - fromLongitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func resolve(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double,
        distanceMeters: Double,
        accuracyMeters: Float?,
        courseDegrees: Float?,
        speedMps: Float?,
        magneticHeading: Float?,
        declinationDegrees: Float?,
        compassAccuracy: Int
    ) -> TargetPointer? {
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
        guard coordsFinite(fromLatitude, fromLongitude, toLatitude, toLongitude) else { return nil }
        let accuracy = accuracyMeters.flatMap { $0.isFinite && $0 >= 0 ? Double($0) : nil } ?? 0
        if distanceMeters <= max(accuracy, 20) { return .ring }
        guard let travel = travelHeading(courseDegrees, speedMps, magneticHeading, declinationDegrees, compassAccuracy) else {
            return nil
        }
        guard let target = initialBearingDegrees(
            fromLatitude: fromLatitude, fromLongitude: fromLongitude, toLatitude: toLatitude, toLongitude: toLongitude
        ) else { return nil }
        return .aim(
            relativeDegrees: CompassHeading.wrapDegrees(Float(target) - travel.degrees),
            dimmed: travel.dimmed
        )
    }

    private static func travelHeading(
        _ courseDegrees: Float?,
        _ speedMps: Float?,
        _ magneticHeading: Float?,
        _ declinationDegrees: Float?,
        _ compassAccuracy: Int
    ) -> (degrees: Float, dimmed: Bool)? {
        if let course = courseDegrees, course.isFinite, let speed = speedMps, speed.isFinite, speed >= 1 {
            return (CompassHeading.wrapDegrees(course), false)
        }
        guard let magnetic = magneticHeading, magnetic.isFinite else { return nil }
        let shift = declinationDegrees.flatMap { $0.isFinite ? $0 : nil }
        let degrees = shift == nil ? CompassHeading.wrapDegrees(magnetic) : CompassHeading.wrapDegrees(magnetic + (shift ?? 0))
        let dimmed = shift == nil || CompassHeading.needsFigureEight(compassAccuracy)
        return (degrees, dimmed)
    }

    private static func coordsFinite(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Bool {
        a.isFinite && b.isFinite && c.isFinite && d.isFinite
    }
}

struct ElevationPoint {
    var latitude: Double
    var longitude: Double
    var gpsAltitude: Double?
    var baroAltitude: Double?
}

struct ElevationSample: Equatable {
    var distanceMeters: Double
    var gpsAltitude: Double?
    var baroAltitude: Double?
}

struct ElevationPlotScale: Equatable {
    var plotMin: Double
    var plotMax: Double
    var span: Double { max(1, plotMax - plotMin) }
    func yFraction(_ altitude: Double) -> Double { (altitude - plotMin) / span }
}

enum ElevationSeries {
    static let defaultMaxPoints = 200
    static let minPlotSpanMeters = 50.0

    static func fromPoints(_ points: [ElevationPoint]) -> [ElevationSample] {
        guard let first = points.first else { return [] }
        var distance = 0.0
        var samples = [ElevationSample(distanceMeters: 0, gpsAltitude: first.gpsAltitude, baroAltitude: first.baroAltitude)]
        if points.count > 1 {
            for index in 1..<points.count {
                distance += FixAcceptance.haversineMeters(
                    points[index - 1].latitude, points[index - 1].longitude, points[index].latitude, points[index].longitude
                )
                samples.append(ElevationSample(distanceMeters: distance, gpsAltitude: points[index].gpsAltitude, baroAltitude: points[index].baroAltitude))
            }
        }
        return samples
    }

    static func downsample(_ samples: [ElevationSample], maxPoints: Int = defaultMaxPoints) -> [ElevationSample] {
        if samples.count <= maxPoints || maxPoints < 2 { return samples }
        let lastIndex = samples.count - 1
        let stride = Double(lastIndex) / Double(maxPoints - 1)
        var out: [ElevationSample] = []
        for index in 0..<maxPoints {
            let source = min(lastIndex, Int(Double(index) * stride))
            out.append(samples[source])
        }
        out[out.count - 1] = samples[samples.count - 1]
        return out
    }

    static func hasBaroLine(_ samples: [ElevationSample]) -> Bool {
        samples.filter { $0.baroAltitude != nil }.count >= 2
    }

    static func plotScale(_ samples: [ElevationSample], minSpanMeters: Double = minPlotSpanMeters) -> ElevationPlotScale {
        let gps = samples.compactMap(\.gpsAltitude)
        var minAlt = gps.min()
        var maxAlt = gps.max()
        if hasBaroLine(samples) {
            let baros = samples.compactMap(\.baroAltitude)
            if let low = baros.min() { minAlt = minAlt == nil ? low : min(minAlt ?? low, low) }
            if let high = baros.max() { maxAlt = maxAlt == nil ? high : max(maxAlt ?? high, high) }
        }
        guard let minAlt, let maxAlt else {
            return ElevationPlotScale(plotMin: 0, plotMax: minSpanMeters)
        }
        let raw = max(1, maxAlt - minAlt)
        let span = max(raw, minSpanMeters)
        let extra = span - raw
        return ElevationPlotScale(plotMin: minAlt - extra / 2, plotMax: maxAlt + extra / 2)
    }
}

enum OfflineMapUse {
    static func isInUse(useOffline: Bool, selectedPath: String, candidatePath: String) -> Bool {
        useOffline && !selectedPath.isEmpty && !candidatePath.isEmpty && selectedPath == candidatePath
    }
}

enum OsmOfflineAvailability {
    static func canEnable(_ hasDownloadedMap: Bool) -> Bool { hasDownloadedMap }

    static func effectiveUseOffline(wantOffline: Bool, hasDownloadedMap: Bool) -> Bool {
        wantOffline && hasDownloadedMap
    }

    static func forceOnlineAfterDelete(deletingSelected: Bool, localeMatch: Bool, mapsRemain: Bool) -> Bool {
        deletingSelected || localeMatch || !mapsRemain
    }
}

enum OsmMapLocale {
    static func countryMatches(regionCountryCode: String, localeCountry: String) -> Bool {
        let region = regionCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let locale = localeCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !region.isEmpty && !locale.isEmpty && region == locale
    }

    static func switchToOnlineMapsOnDelete(regionCountryCode: String, localeCountry: String, deletingSelectedMap: Bool) -> Bool {
        deletingSelectedMap || countryMatches(regionCountryCode: regionCountryCode, localeCountry: localeCountry)
    }
}

enum OsmMapFile {
    static let magic = "mapsforge binary OSM"
    static let minReadableBytes: Int64 = 1024

    static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let length = Int64(values?.fileSize ?? 0)
        if length < minReadableBytes { return false }
        let header = handle.readData(ofLength: 36)
        guard header.count == 36 else { return false }
        let magicBytes = header.prefix(magic.utf8.count)
        guard String(data: magicBytes, encoding: .ascii) == magic else { return false }
        var declared: UInt64 = 0
        for byte in header[28..<36] {
            declared = (declared << 8) | UInt64(byte)
        }
        return Int64(declared) == length && Int64(declared) >= minReadableBytes
    }
}

enum OsmHillshading {
    static func available(mapFile: URL) -> Bool {
        guard OsmMapFile.isReadable(mapFile) else { return false }
        let dir = mapFile.deletingLastPathComponent()
        return hasElevationFiles(dir) || hasElevationFiles(dir.appendingPathComponent("hills"))
    }

    static func isElevationFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".hgt") || lower.hasSuffix(".hf2") || lower.hasSuffix(".hgt.zip")
    }

    private static func hasElevationFiles(_ dir: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        return items.contains { isElevationFileName($0.lastPathComponent) }
    }
}

struct OsmRenderOptions: Equatable {
    var buildings: Bool
    var poi: Bool
    var transit: Bool
    var cycleways: Bool
    var parks: Bool
    var hillshading: Bool

    static let catBuildings = "buildings"
    static let catPoi = "poi"
    static let catTransit = "transit"
    static let catCycleways = "cycleways"
    static let catParks = "parks"
    static let catHillshading = "hillshading"

    func categoryIds() -> Set<String> {
        var ids: Set<String> = []
        if buildings { ids.insert(Self.catBuildings) }
        if poi { ids.insert(Self.catPoi) }
        if transit { ids.insert(Self.catTransit) }
        if cycleways { ids.insert(Self.catCycleways) }
        if parks { ids.insert(Self.catParks) }
        if hillshading { ids.insert(Self.catHillshading) }
        return ids
    }

    func forMap(hillshadingAvailable: Bool) -> OsmRenderOptions {
        hillshadingAvailable ? self : OsmRenderOptions(
            buildings: buildings, poi: poi, transit: transit, cycleways: cycleways, parks: parks, hillshading: false
        )
    }

    static func cyclewaysForUsage(_ usage: UsageType) -> Bool { usage == .BICYCLE }

    static func defaults(usage: UsageType) -> OsmRenderOptions {
        OsmRenderOptions(
            buildings: true, poi: false, transit: false,
            cycleways: cyclewaysForUsage(usage), parks: true, hillshading: false
        )
    }
}

struct TuhuRenderOptions: Equatable {
    var blazes: Bool
    var paths: Bool
    var contours: Bool
    var contoursMinor: Bool
    var hikePoi: Bool
    var parks: Bool
    var urbanPoi: Bool
    var hillshading: Bool

    static let catBlazes = "blazes"
    static let catPaths = "paths"
    static let catContours = "contours"
    static let catContoursMinor = "contours_minor"
    static let catHikePoi = "hike_poi"
    static let catParks = "parks"
    static let catUrbanPoi = "urban_poi"
    static let catHillshading = "hillshading"

    func categoryIds() -> Set<String> {
        var ids: Set<String> = []
        if blazes { ids.insert(Self.catBlazes) }
        if paths { ids.insert(Self.catPaths) }
        if contours { ids.insert(Self.catContours) }
        if contoursMinor { ids.insert(Self.catContoursMinor) }
        if hikePoi { ids.insert(Self.catHikePoi) }
        if parks { ids.insert(Self.catParks) }
        if urbanPoi { ids.insert(Self.catUrbanPoi) }
        if hillshading { ids.insert(Self.catHillshading) }
        return ids
    }

    func forMap(hillshadingAvailable: Bool) -> TuhuRenderOptions {
        var copy = self
        if !hillshadingAvailable { copy.hillshading = false }
        return copy
    }

    static func defaults() -> TuhuRenderOptions {
        TuhuRenderOptions(
            blazes: true, paths: true, contours: true, contoursMinor: false,
            hikePoi: true, parks: false, urbanPoi: false, hillshading: false
        )
    }
}

enum OsmRenderCategories {
    static func enabled(baseCategories: Set<String>, overlayCategories: [String: Set<String>], enabledOverlayIds: Set<String>) -> Set<String> {
        var result = baseCategories
        for id in enabledOverlayIds {
            if let cats = overlayCategories[id] {
                result.formUnion(cats)
            } else {
                result.insert(id)
            }
        }
        return result
    }
}

enum OsmRenderThemePath {
    static let themeFile = "mapsforge/gtl.xml"
    static func assetOpenPath(relativePathPrefix: String = "", themeFile: String = themeFile) -> String {
        relativePathPrefix + themeFile
    }
}

enum OsmMapViewRedraw {
    static func shouldRedrawLayers(width: Int, height: Int, oldWidth: Int, oldHeight: Int) -> Bool {
        if width <= 0 || height <= 0 { return false }
        return oldWidth == 0 || oldHeight == 0 || oldWidth != width || oldHeight != height
    }

    static func shouldRequestTiles(width: Int, height: Int) -> Bool {
        width > 0 && height > 0
    }

    static func mustPostAncestorInvalidate(calledOnMainThread: Bool) -> Bool {
        !calledOnMainThread
    }
}

struct LatLonBounds: Equatable {
    var minLatitude: Double
    var minLongitude: Double
    var maxLatitude: Double
    var maxLongitude: Double
    var isDegenerate: Bool { minLatitude == maxLatitude && minLongitude == maxLongitude }
}

enum TrackCameraBounds {
    static func of(_ points: [GeoPoint], extra: GeoPoint?) -> LatLonBounds? {
        if points.isEmpty && extra == nil { return nil }
        var minLat = Double.infinity
        var minLon = Double.infinity
        var maxLat = -Double.infinity
        var maxLon = -Double.infinity
        for point in points {
            minLat = min(minLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLat = max(maxLat, point.latitude)
            maxLon = max(maxLon, point.longitude)
        }
        if let extra {
            minLat = min(minLat, extra.latitude)
            minLon = min(minLon, extra.longitude)
            maxLat = max(maxLat, extra.latitude)
            maxLon = max(maxLon, extra.longitude)
        }
        return LatLonBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
    }
}

enum TrackEndpoints {
    static func start(_ points: [GeoPoint]) -> GeoPoint? { points.first }
    static func end(_ points: [GeoPoint], logging: Bool) -> GeoPoint? {
        if logging || points.count < 2 { return nil }
        return points.last
    }
}

enum TrackLine {
    static func withLiveEnd(_ points: [GeoPoint], logging: Bool, latitude: Double?, longitude: Double?) -> [GeoPoint] {
        guard logging, let latitude, let longitude else { return points }
        let here = GeoPoint(latitude: latitude, longitude: longitude, altitude: nil)
        guard let last = points.last else { return [here] }
        guard FixAcceptance.haversineMeters(last.latitude, last.longitude, latitude, longitude) > 3 else { return points }
        var copy = points
        copy.append(here)
        return copy
    }
}

enum MapFitZoom {
    static let minZoom = 3
    static let maxZoom = 20
    static func canFit(widthPx: Int?, heightPx: Int?) -> Bool {
        guard let widthPx, let heightPx else { return false }
        return widthPx > 0 && heightPx > 0
    }
    static func clamp(_ zoom: Int) -> Int { min(maxZoom, max(minZoom, zoom)) }
}

struct OsmMapCenter: Equatable {
    var latitude: Double
    var longitude: Double
}

enum OsmMapCamera {
    static let gpsZoom = 14

    static func contains(_ bounds: LatLonBounds, _ latitude: Double, _ longitude: Double) -> Bool {
        latitude >= bounds.minLatitude && latitude <= bounds.maxLatitude &&
            longitude >= bounds.minLongitude && longitude <= bounds.maxLongitude
    }

    static func initialCenter(
        mapBounds: LatLonBounds,
        mapStartLatitude: Double,
        mapStartLongitude: Double,
        locationLatitude: Double?,
        locationLongitude: Double?
    ) -> OsmMapCenter {
        if let locationLatitude, let locationLongitude, contains(mapBounds, locationLatitude, locationLongitude) {
            return OsmMapCenter(latitude: locationLatitude, longitude: locationLongitude)
        }
        return OsmMapCenter(latitude: mapStartLatitude, longitude: mapStartLongitude)
    }

    static func initialZoom(gpsInsideMap: Bool, mapStartZoom: Int) -> Int {
        MapFitZoom.clamp(gpsInsideMap ? gpsZoom : mapStartZoom)
    }

    static func followCenter(
        mapBounds: LatLonBounds,
        preferTrack: Bool,
        trackLatitude: Double?,
        trackLongitude: Double?,
        locationLatitude: Double?,
        locationLongitude: Double?
    ) -> OsmMapCenter? {
        let latitude: Double
        let longitude: Double
        if preferTrack, let trackLatitude, let trackLongitude {
            latitude = trackLatitude
            longitude = trackLongitude
        } else if let locationLatitude, let locationLongitude {
            latitude = locationLatitude
            longitude = locationLongitude
        } else if let trackLatitude, let trackLongitude {
            latitude = trackLatitude
            longitude = trackLongitude
        } else {
            return nil
        }
        guard contains(mapBounds, latitude, longitude) else { return nil }
        return OsmMapCenter(latitude: latitude, longitude: longitude)
    }

    static func locateCenter(latitude: Double?, longitude: Double?) -> OsmMapCenter? {
        guard let latitude, let longitude else { return nil }
        return OsmMapCenter(latitude: latitude, longitude: longitude)
    }
}

enum MapAddressLookup {
    static func supported() -> Bool { false }
    static func lookup(latitude: Double, longitude: Double) -> String? { nil }
}

enum TapReadout {
    static func formatCoordinate(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    static func formatLatitude(_ latitude: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude)
    }

    static func formatLongitude(_ longitude: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), longitude)
    }

    static func formatStraightLine(_ meters: Double, _ system: MeasurementSystem, prefix: String) -> String {
        let converted: Double
        let unit: String
        switch system {
        case .METRIC:
            converted = meters / 1000
            unit = "km"
        case .IMPERIAL:
            converted = meters / 1609.344
            unit = "mi"
        case .ICAO:
            converted = meters / 1852
            unit = "NM"
        }
        let number = converted < 10
            ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), converted)
            : String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), converted)
        return prefix + number + unit
    }
}

enum RouteTabSpeeds {
    static func instantMps(logging: Bool, liveSpeedMps: Float?) -> Float? {
        logging ? liveSpeedMps : 0
    }

    static func averageMps(logging: Bool, sessionAverageMps: Float) -> Float {
        logging ? sessionAverageMps : 0
    }
}

enum MapDisplayUsage {
    static func followsSettings(logging: Bool, selectedSessionId: Int64?) -> Bool {
        logging || selectedSessionId != nil
    }

    static func of(logging: Bool, followSettings: Bool, settingsUsage: UsageType, sessionUsageName: String?) -> UsageType {
        if logging || followSettings { return settingsUsage }
        guard let sessionUsageName, !sessionUsageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return settingsUsage
        }
        return UsageType(rawValue: sessionUsageName) ?? settingsUsage
    }

    static func simplify(
        usage: UsageType,
        logging: Bool,
        followSettings: Bool,
        settingsActive: Bool,
        settingsTolerance: Double
    ) -> (Bool, Double) {
        if logging || followSettings {
            return (settingsActive, DouglasPeucker.clampTolerance(settingsTolerance))
        }
        let defaults = usage.defaultSmoothing()
        return (defaults.optimizationActive, defaults.optimizationToleranceMeters)
    }
}

struct FixCloudSample {
    var timeMillis: Int64
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Float
    var speedMps: Float
}

struct FixCloudStats: Equatable {
    var sampleCount: Int
    var centroidLatitude: Double?
    var centroidLongitude: Double?
    var rmsMeters: Double?
    var cep50Meters: Double?
    var cep95Meters: Double?
    var reportedAccuracyMedianMeters: Double?
    var active: Bool

    static let empty = FixCloudStats(
        sampleCount: 0, centroidLatitude: nil, centroidLongitude: nil, rmsMeters: nil,
        cep50Meters: nil, cep95Meters: nil, reportedAccuracyMedianMeters: nil, active: true
    )
}

struct FixCloudSnapshot {
    var samples: [FixCloudSample]
    var stats: FixCloudStats
    static let empty = FixCloudSnapshot(samples: [], stats: .empty)
}

final class FixCloudBuffer {
    private var samples: [FixCloudSample] = []
    private var paused = false
    private var consecutiveStationary = 0
    static let maxSamples = 120
    static let maxAgeMillis: Int64 = 120_000
    static let minSeparationMeters = 0.15
    static let cepMinSamples = 8
    static let stationaryResumeFixes = 3

    func observe(_ sample: FixCloudSample, pauseSpeedMps: Float) {
        guard sample.latitude.isFinite, sample.longitude.isFinite else { return }
        if sample.speedMps >= pauseSpeedMps {
            paused = true
            consecutiveStationary = 0
            return
        }
        if paused {
            consecutiveStationary += 1
            if consecutiveStationary < Self.stationaryResumeFixes { return }
            samples.removeAll()
            paused = false
            consecutiveStationary = 0
        }
        if let last = samples.last {
            let distance = FixAcceptance.haversineMeters(last.latitude, last.longitude, sample.latitude, sample.longitude)
            if distance < Self.minSeparationMeters { return }
        }
        samples.append(sample)
        trim(sample.timeMillis)
    }

    func clear() {
        samples.removeAll()
        paused = false
        consecutiveStationary = 0
    }

    func snapshot() -> FixCloudSnapshot {
        FixCloudSnapshot(samples: samples, stats: Self.computeStats(samples, active: !paused))
    }

    private func trim(_ nowMillis: Int64) {
        while samples.count > Self.maxSamples { samples.removeFirst() }
        while let first = samples.first, nowMillis - first.timeMillis > Self.maxAgeMillis {
            samples.removeFirst()
        }
    }

    static func computeStats(_ samples: [FixCloudSample], active: Bool) -> FixCloudStats {
        guard !samples.isEmpty else {
            var empty = FixCloudStats.empty
            empty.active = active
            return empty
        }
        let centroidLat = samples.map(\.latitude).reduce(0, +) / Double(samples.count)
        let centroidLon = samples.map(\.longitude).reduce(0, +) / Double(samples.count)
        let distances = samples.map { sample in
            let en = GeoProjection.eastNorth(originLat: centroidLat, originLon: centroidLon, lat: sample.latitude, lon: sample.longitude)
            return GeoProjection.hypot(en.0, en.1)
        }
        let meanSq = distances.map { $0 * $0 }.reduce(0, +) / Double(distances.count)
        let rms = meanSq.squareRoot()
        let sorted = distances.sorted()
        let cep50 = percentile(sorted, 50)
        let cep95 = samples.count >= cepMinSamples ? percentile(sorted, 95) : nil
        let accuracies = samples.map(\.accuracyMeters).filter { $0 > 0 }.sorted()
        let reported = accuracies.isEmpty ? nil : percentile(accuracies.map { Double($0) }, 50)
        return FixCloudStats(
            sampleCount: samples.count,
            centroidLatitude: centroidLat,
            centroidLongitude: centroidLon,
            rmsMeters: rms,
            cep50Meters: cep50,
            cep95Meters: cep95,
            reportedAccuracyMedianMeters: reported,
            active: active
        )
    }

    private static func percentile(_ sorted: [Double], _ percent: Int) -> Double {
        if sorted.isEmpty { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let index = ((sorted.count - 1) * percent) / 100
        return sorted[index]
    }
}

enum MapPlaceKind: String, Codable {
    case City, Town, Village, Hamlet, Suburb, Peak, Statue, Monument, Landmark, House, Building, Street, Place

    func zoom() -> Int {
        let level: Int
        switch self {
        case .City: level = 11
        case .Town: level = 12
        case .Village, .Hamlet: level = 14
        case .Suburb, .Peak: level = 15
        case .Street, .Landmark, .Monument: level = 16
        case .House, .Building, .Statue, .Place: level = 17
        }
        return MapFitZoom.clamp(level)
    }
}

struct MapPlaceRecord {
    var displayName: String
    var foldedAliases: [String]
    var kind: MapPlaceKind
}

struct MapSearchCandidate {
    var name: String
    var nameFold: String
    var kind: MapPlaceKind
    var latitude: Double
    var longitude: Double
}

struct MapSearchHit: Equatable {
    var name: String
    var kind: MapPlaceKind
    var latitude: Double
    var longitude: Double
    var distanceMeters: Double
}

struct IndexProgress {
    var done: Bool
    var truncated: Bool
    var nextAttemptAtMillis: Int64
}

enum IndexResumeAction {
    case ready
    case resume
    case backoff
    case truncated
}

enum IndexResume {
    static func action(_ progress: IndexProgress?, nowMillis: Int64) -> IndexResumeAction {
        guard let progress else { return .resume }
        if progress.done { return .ready }
        if progress.truncated { return .truncated }
        if progress.nextAttemptAtMillis > nowMillis { return .backoff }
        return .resume
    }
}

enum MapSearch {
    static let minQueryChars = 3
    static let resultLimit = 5
    static let maxIndexedPlaces = 250_000
    private static let cellDegrees = 0.00015
    private static let nameKeys = ["name", "name:hu", "name:en", "alt_name", "loc_name", "official_name"]
    private static let roads: Set<String> = [
        "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
        "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
        "residential", "living_street", "service", "pedestrian", "road"
    ]

    static func mapKey(path: String, length: Int64, lastModified: Int64) -> String {
        "\(path)|\(length)|\(lastModified)"
    }

    static func accepts(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).count >= minQueryChars
    }

    static func fold(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var chars: [Character] = []
        for ch in trimmed {
            let folded = foldChar(ch)
            if folded.isLetter || folded.isNumber || folded.isWhitespace { chars.append(folded) }
        }
        return String(chars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func sqlToken(_ raw: String) -> String? {
        guard accepts(raw) else { return nil }
        let tokens = fold(raw).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let best = tokens.max(by: { $0.count < $1.count }) else { return nil }
        let clean = best.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
        return clean.isEmpty ? nil : clean
    }

    static func ftsMatch(_ raw: String) -> String? {
        guard accepts(raw) else { return nil }
        let tokens = fold(raw).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    static func cell(_ value: Double) -> Int { Int((value / cellDegrees).rounded()) }

    static func record(tags: [String: String]) -> MapPlaceRecord? {
        guard let kind = kindOf(tags) else { return nil }
        var folded: [String] = []
        var seen = Set<String>()
        for key in nameKeys {
            guard let raw = tags[key] else { continue }
            for variant in nameVariants(raw) {
                let alias = fold(variant)
                if alias.count >= 2 && seen.insert(alias).inserted { folded.append(alias) }
            }
        }
        let street = tags["addr:street"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let number = tags["addr:housenumber"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !street.isEmpty && !number.isEmpty {
            let alias = fold("\(street) \(number)")
            if alias.count >= 2 && seen.insert(alias).inserted { folded.append(alias) }
        }
        guard !folded.isEmpty, let display = displayName(tags, street, number), fold(display).count >= 2 else {
            return nil
        }
        return MapPlaceRecord(displayName: display, foldedAliases: folded, kind: kind)
    }

    static func rank(rawQuery: String, candidates: [MapSearchCandidate], originLatitude: Double, originLongitude: Double) -> [MapSearchHit] {
        guard accepts(rawQuery) else { return [] }
        let query = fold(rawQuery)
        var best: [String: (MapSearchCandidate, Int, Double)] = [:]
        for candidate in candidates {
            guard let tier = tier(query, candidate.nameFold) else { continue }
            let distance = FixAcceptance.haversineMeters(originLatitude, originLongitude, candidate.latitude, candidate.longitude)
            let key = "\(candidate.kind.rawValue)|\(candidate.name)|\(cell(candidate.latitude))|\(cell(candidate.longitude))"
            let scored = (candidate, tier, distance)
            if let previous = best[key] {
                if tier < previous.1 || (tier == previous.1 && distance < previous.2) {
                    best[key] = scored
                }
            } else {
                best[key] = scored
            }
        }
        return best.values
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
                return lhs.0.name < rhs.0.name
            }
            .prefix(resultLimit)
            .map { item in
                MapSearchHit(name: item.0.name, kind: item.0.kind, latitude: item.0.latitude, longitude: item.0.longitude, distanceMeters: item.2)
            }
    }

    private static func tier(_ query: String, _ name: String) -> Int? {
        if name == query { return 0 }
        let queryTokens = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let nameTokens = name.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if !queryTokens.isEmpty && tokensInOrder(queryTokens, nameTokens) { return 1 }
        if name.hasPrefix(query) { return 2 }
        if !queryTokens.isEmpty && queryTokens.allSatisfy({ name.contains($0) }) { return 3 }
        return nil
    }

    private static func tokensInOrder(_ query: [String], _ name: [String]) -> Bool {
        var start = 0
        for token in query {
            var found = -1
            if start < name.count {
                for index in start..<name.count where name[index].hasPrefix(token) {
                    found = index
                    break
                }
            }
            if found < 0 { return false }
            start = found + 1
        }
        return true
    }

    private static func kindOf(_ tags: [String: String]) -> MapPlaceKind? {
        if let place = tags["place"], !place.isEmpty {
            switch place {
            case "city": return .City
            case "town": return .Town
            case "village": return .Village
            case "hamlet", "isolated_dwelling": return .Hamlet
            case "suburb", "neighbourhood", "quarter", "borough", "locality", "allotments": return .Suburb
            default: return .Hamlet
            }
        }
        if isStatue(tags) { return .Statue }
        switch tags["historic"] {
        case "memorial", "monument": return .Monument
        case "castle", "ruins", "archaeological_site", "city_gate", "fort", "manor": return .Landmark
        default: break
        }
        switch tags["tourism"] {
        case "attraction", "viewpoint", "museum", "alpine_hut", "wilderness_hut", "camp_site", "information", "gallery":
            return .Landmark
        default: break
        }
        if tags["amenity"] == "place_of_worship" { return .Landmark }
        if tags["leisure"] == "park" || tags["leisure"] == "nature_reserve" || tags["boundary"] == "national_park" {
            return .Landmark
        }
        switch tags["natural"] {
        case "peak", "volcano", "saddle", "cave_entrance": return .Peak
        default: break
        }
        if tags["mountain_pass"] == "yes" { return .Peak }
        if let highway = tags["highway"], roads.contains(highway) { return .Street }
        let named = nameKeys.contains { key in
            let value = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
        let addressed = !(tags["addr:street"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !(tags["addr:housenumber"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tags["building"] != nil && named { return .Building }
        if addressed { return .House }
        if named || tags["highway"] != nil { return .Place }
        return nil
    }

    private static func isStatue(_ tags: [String: String]) -> Bool {
        tags["artwork_type"] == "statue" || tags["memorial"] == "statue" || tags["historic"] == "statue" || tags["tourism"] == "artwork"
    }

    private static func displayName(_ tags: [String: String], _ street: String, _ number: String) -> String? {
        if let raw = tags["name"], let base = nameVariants(raw).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return base.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for key in ["name:hu", "name:en", "official_name", "loc_name", "alt_name"] {
            if let value = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
               let name = nameVariants(value).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if !street.isEmpty && !number.isEmpty { return "\(street) \(number)" }
        return nil
    }

    private static func nameVariants(_ raw: String) -> [String] {
        if !raw.contains("\r") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        let parts = raw.split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
        var names: [String] = []
        let base = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { names.append(base) }
        if parts.count > 1 {
            for part in parts.dropFirst() {
                let bits = part.split(separator: "\u{0008}", omittingEmptySubsequences: false).map(String.init)
                if bits.count >= 2 {
                    let name = bits[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }
        return names
    }

    private static func foldChar(_ ch: Character) -> Character {
        switch ch {
        case "á", "à", "ä", "â", "ã", "å": return "a"
        case "é", "è", "ë", "ê": return "e"
        case "í", "ì", "ï", "î": return "i"
        case "ó", "ò", "ö", "ő", "ô", "õ": return "o"
        case "ú", "ù", "ü", "ű", "û": return "u"
        case "ý", "ÿ": return "y"
        case "ñ": return "n"
        case "ç": return "c"
        default: return ch
        }
    }
}
