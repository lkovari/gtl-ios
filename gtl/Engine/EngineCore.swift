import Foundation

struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
}

enum GeoProjection {
    static let metersPerDegLat = 111_320.0

    static func metersPerDegLng(_ latitudeDeg: Double) -> Double {
        metersPerDegLat * cos(latitudeDeg * .pi / 180)
    }

    static func eastNorth(originLat: Double, originLon: Double, lat: Double, lon: Double) -> (Double, Double) {
        let east = (lon - originLon) * metersPerDegLng(originLat)
        let north = (lat - originLat) * metersPerDegLat
        return (east, north)
    }

    static func latLon(originLat: Double, originLon: Double, east: Double, north: Double) -> (Double, Double) {
        let lat = originLat + north / metersPerDegLat
        let lon = originLon + east / metersPerDegLng(originLat)
        return (lat, lon)
    }

    static func hypot(_ x: Double, _ y: Double) -> Double {
        (x * x + y * y).squareRoot()
    }
}

enum MeasurementSystem: String, CaseIterable, Codable {
    case METRIC
    case IMPERIAL
    case ICAO
}

enum SmoothingStrength: String, Codable {
    case LOW
    case MEDIUM
    case HIGH

    var sliderValue: Float {
        switch self {
        case .LOW: return 0
        case .MEDIUM: return 0.5
        case .HIGH: return 1
        }
    }

    static func processNoiseMultiplier(_ slider: Float) -> Double {
        let t = Double(min(1, max(0, slider)))
        return pow(4.0, 1.0 - 2.0 * t)
    }
}

enum RecordingDensity: String, Codable {
    case SMART
    case EVERY_FIX

    var sliderValue: Float {
        switch self {
        case .SMART: return 0
        case .EVERY_FIX: return 1
        }
    }
}

struct UsageSmoothingDefaults: Equatable {
    var trackSmoothingEnabled: Bool
    var smoothingStrength: SmoothingStrength
    var stationaryLockEnabled: Bool
    var recordingDensity: RecordingDensity
    var optimizationActive: Bool
    var optimizationToleranceMeters: Double
    var gnssOnly: Bool
}

struct FixFilter: Equatable {
    var minDistanceMeters: Float
    var minTimeMillis: Int64
    var minAccuracyMeters: Int
    var minSatellites: Int
}

enum UsageType: String, CaseIterable, Codable {
    case AIRCRAFT
    case WATERCRAFT
    case FOUR_WHEELERS
    case TWO_WHEELERS
    case BICYCLE
    case WALKING_HIKE
    case PEDESTRIAN
    case RUNNER

    static let selectable: [UsageType] = [
        .AIRCRAFT, .WATERCRAFT, .FOUR_WHEELERS, .TWO_WHEELERS, .BICYCLE, .RUNNER
    ]

    func defaultFilter() -> FixFilter {
        let accuracy = isPedestrianMode() ? 45 : 30
        return FixFilter(minDistanceMeters: 2, minTimeMillis: 500, minAccuracyMeters: accuracy, minSatellites: 4)
    }

    func defaultMeasurementSystem() -> MeasurementSystem {
        self == .AIRCRAFT || self == .WATERCRAFT ? .ICAO : .METRIC
    }

    func pauseSpeedMps() -> Float {
        isPedestrianMode() ? 0.25 : 0.4
    }

    func isPedestrianMode() -> Bool {
        switch self {
        case .RUNNER, .BICYCLE, .WALKING_HIKE, .PEDESTRIAN: return true
        default: return false
        }
    }

    func kmlLabel() -> String {
        switch self {
        case .AIRCRAFT: return "Aircraft"
        case .WATERCRAFT: return "Watercraft"
        case .FOUR_WHEELERS: return "Car"
        case .TWO_WHEELERS: return "Motorbike"
        case .BICYCLE: return "Bicycle"
        case .RUNNER, .WALKING_HIKE, .PEDESTRIAN: return "Run/Hike"
        }
    }

    static func kmlLabelOf(_ stored: String?) -> String? {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let usage = UsageType(rawValue: stored) {
            return usage.kmlLabel()
        }
        return stored
    }

    func processNoiseQ() -> Double {
        switch self {
        case .RUNNER, .WALKING_HIKE, .PEDESTRIAN: return 8
        case .BICYCLE: return 6
        case .TWO_WHEELERS: return 2.5
        case .FOUR_WHEELERS, .WATERCRAFT: return 1.5
        case .AIRCRAFT: return 0.8
        }
    }

    func turnBoost() -> Double {
        switch self {
        case .RUNNER, .WALKING_HIKE, .PEDESTRIAN: return 10
        case .BICYCLE: return 8
        case .TWO_WHEELERS: return 5
        case .FOUR_WHEELERS, .WATERCRAFT: return 3
        case .AIRCRAFT: return 2
        }
    }

    func defaultSmoothing() -> UsageSmoothingDefaults {
        switch self {
        case .RUNNER, .WALKING_HIKE, .PEDESTRIAN:
            return UsageSmoothingDefaults(
                trackSmoothingEnabled: false,
                smoothingStrength: .LOW,
                stationaryLockEnabled: true,
                recordingDensity: .EVERY_FIX,
                optimizationActive: false,
                optimizationToleranceMeters: 2,
                gnssOnly: true
            )
        case .BICYCLE:
            return UsageSmoothingDefaults(
                trackSmoothingEnabled: false,
                smoothingStrength: .LOW,
                stationaryLockEnabled: true,
                recordingDensity: .EVERY_FIX,
                optimizationActive: false,
                optimizationToleranceMeters: 3,
                gnssOnly: true
            )
        case .TWO_WHEELERS:
            return UsageSmoothingDefaults(
                trackSmoothingEnabled: true,
                smoothingStrength: .MEDIUM,
                stationaryLockEnabled: true,
                recordingDensity: .SMART,
                optimizationActive: true,
                optimizationToleranceMeters: 6,
                gnssOnly: false
            )
        case .FOUR_WHEELERS, .WATERCRAFT:
            return UsageSmoothingDefaults(
                trackSmoothingEnabled: true,
                smoothingStrength: .MEDIUM,
                stationaryLockEnabled: true,
                recordingDensity: .SMART,
                optimizationActive: true,
                optimizationToleranceMeters: 8,
                gnssOnly: false
            )
        case .AIRCRAFT:
            return UsageSmoothingDefaults(
                trackSmoothingEnabled: true,
                smoothingStrength: .HIGH,
                stationaryLockEnabled: true,
                recordingDensity: .SMART,
                optimizationActive: true,
                optimizationToleranceMeters: 15,
                gnssOnly: false
            )
        }
    }
}

struct TrackFix: Equatable {
    var timestampMillis: Int64
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speedMps: Float
    var bearing: Float
    var accuracyMeters: Float
    var satellitesInFix: Int
}

enum FixAcceptance {
    private static let everyFixMinDistanceMeters = 1.0
    private static let pedestrianEveryFixMinDistanceMeters = 0.5

    static func shouldAccept(
        previous: TrackFix?,
        current: TrackFix,
        filter: FixFilter,
        density: RecordingDensity = .SMART,
        usage: UsageType? = nil
    ) -> Bool {
        shouldAccept(previous: previous, current: current, filter: filter, densityMix: density.sliderValue, usage: usage)
    }

    static func shouldAccept(
        previous: TrackFix?,
        current: TrackFix,
        filter: FixFilter,
        densityMix: Float,
        usage: UsageType? = nil
    ) -> Bool {
        guard current.latitude.isFinite, current.longitude.isFinite else { return false }
        if abs(current.latitude) > 90 || abs(current.longitude) > 180 { return false }
        if let previous, current.timestampMillis <= previous.timestampMillis { return false }
        if current.accuracyMeters > Float(filter.minAccuracyMeters) { return false }
        if current.satellitesInFix >= 0 && current.satellitesInFix < filter.minSatellites { return false }
        if previous == nil { return true }
        guard let previous else { return true }
        let distance = haversineMeters(previous.latitude, previous.longitude, current.latitude, current.longitude)
        let inCurve = SpeedAdaptiveSpacing.isInCurve(previous, current)
        let t = min(1, max(0, densityMix))
        let smartNeeded = SpeedAdaptiveSpacing.spacingMeters(current.speedMps, inCurve: inCurve, usage: usage)
        let everyFixMin = everyFixMinDistanceMeters(usage)
        if t <= 0.001 {
            return distance >= Double(smartNeeded)
        }
        if t >= 0.999 {
            if distance < everyFixMin { return false }
            let elapsed = current.timestampMillis - previous.timestampMillis
            return elapsed >= filter.minTimeMillis || inCurve
        }
        let needed = Double(smartNeeded) * Double(1 - t) + everyFixMin * Double(t)
        if distance >= needed { return true }
        if distance >= everyFixMin {
            let elapsed = current.timestampMillis - previous.timestampMillis
            return elapsed >= filter.minTimeMillis || inCurve
        }
        return false
    }

    static func hasUsableAccuracy(_ hasAccuracy: Bool, _ accuracyMeters: Float) -> Bool {
        hasAccuracy && accuracyMeters.isFinite && accuracyMeters > 0
    }

    static let liveMaxAgeSeconds: TimeInterval = 10
    static let locateMaxAgeSeconds: TimeInterval = 300
    static let loggingMaxAgeSeconds: TimeInterval = 6 * 60 * 60

    static func keepFix(
        logging: Bool,
        ageSeconds: TimeInterval,
        locating: Bool,
        fixMillis: Int64,
        startedAtMillis: Int64?,
        lastAcceptMillis: Int64?
    ) -> Bool {
        if logging {
            if ageSeconds > loggingMaxAgeSeconds { return false }
            if let lastAcceptMillis, fixMillis <= lastAcceptMillis { return false }
            if lastAcceptMillis == nil, let startedAtMillis, fixMillis + 2_000 < startedAtMillis {
                return false
            }
            return true
        }
        if locating && ageSeconds <= locateMaxAgeSeconds { return true }
        return ageSeconds <= liveMaxAgeSeconds
    }

    static func everyFixMinDistanceMeters(_ usage: UsageType?) -> Double {
        if let usage, usage.isPedestrianMode() {
            return pedestrianEveryFixMinDistanceMeters
        }
        return everyFixMinDistanceMeters
    }

    static func haversineMeters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let aRaw = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let a = min(1, max(0, aRaw))
        let c = 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
        return earthRadius * c
    }
}

enum SpeedAdaptiveSpacing {
    static let curveDegrees: Float = 15
    private static let minHeadingDisplacementMeters = 0.05

    static func spacingMeters(_ speedMps: Float, inCurve: Bool) -> Float {
        let kmh = speedMps * 3.6
        let base: Float
        switch kmh {
        case ...0: base = 2
        case ...5: base = 4
        case ...10: base = 10
        case ...25: base = 20
        case ...50: base = 36
        case ...75: base = 48
        case ...100: base = 70
        case ...150: base = 98
        case ...200: base = 124
        case ...250: base = 152
        case ...300: base = 194
        case ...400: base = 250
        case ...500: base = 348
        case ...750: base = 243
        case ...1000: base = 556
        case ...1500: base = 695
        default: base = 834
        }
        return inCurve ? max(1, base / 2) : base
    }

    static func spacingMeters(_ speedMps: Float, inCurve: Bool, usage: UsageType?) -> Float {
        let spaced = spacingMeters(speedMps, inCurve: inCurve)
        guard let usage, usage.isPedestrianMode() else { return spaced }
        return max(1, spaced / 2)
    }

    static func headingDegrees(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Float? {
        let en = GeoProjection.eastNorth(originLat: fromLat, originLon: fromLon, lat: toLat, lon: toLon)
        if GeoProjection.hypot(en.0, en.1) < minHeadingDisplacementMeters { return nil }
        let deg = atan2(en.0, en.1) * 180 / .pi
        return Float((deg + 360).truncatingRemainder(dividingBy: 360))
    }

    static func headingChangeIsCurve(_ previousHeading: Float, _ currentHeading: Float) -> Bool {
        let raw = abs(currentHeading - previousHeading)
        let diff = min(raw, 360 - raw)
        return diff > curveDegrees
    }

    static func isInCurve(_ previousBearing: Float, _ currentBearing: Float) -> Bool {
        if previousBearing == 0 || currentBearing == 0 { return false }
        return headingChangeIsCurve(previousBearing, currentBearing)
    }

    static func isInCurve(_ previous: TrackFix, _ current: TrackFix) -> Bool {
        if isInCurve(previous.bearing, current.bearing) { return true }
        if previous.bearing != 0 && current.bearing != 0 { return false }
        guard let displacement = headingDegrees(
            fromLat: previous.latitude,
            fromLon: previous.longitude,
            toLat: current.latitude,
            toLon: current.longitude
        ) else { return false }
        if previous.bearing != 0 { return headingChangeIsCurve(previous.bearing, displacement) }
        if current.bearing != 0 { return headingChangeIsCurve(displacement, current.bearing) }
        return false
    }

    static func isInCurve(_ first: TrackFix, _ second: TrackFix, _ third: TrackFix) -> Bool {
        if isInCurve(second, third) { return true }
        guard let firstLeg = headingDegrees(
            fromLat: first.latitude, fromLon: first.longitude, toLat: second.latitude, toLon: second.longitude
        ), let secondLeg = headingDegrees(
            fromLat: second.latitude, fromLon: second.longitude, toLat: third.latitude, toLon: third.longitude
        ) else { return false }
        return headingChangeIsCurve(firstLeg, secondLeg)
    }
}

enum GpsAltitude {
    static let minPlausibleMeters = -430.0
    static let maxPlausibleMeters = 20_000.0

    static func isPlausible(_ meters: Double) -> Bool {
        meters.isFinite && meters >= minPlausibleMeters && meters <= maxPlausibleMeters
    }

    static func pick(gnssMsl: Double?, fusedMsl: Double?, gnssEllipsoid: Double?, fusedEllipsoid: Double?) -> Double? {
        for value in [gnssMsl, fusedMsl, gnssEllipsoid, fusedEllipsoid] {
            if let value, isPlausible(value) { return value }
        }
        return nil
    }
}

enum BaroAltitude {
    static let standardAtmosphereHpa: Float = 1013.25
    static let minQnhHpa: Float = 900
    static let maxQnhHpa: Float = 1100
    static let minOffsetHpa: Float = -10
    static let maxOffsetHpa: Float = 10
    static let maxGpsDeltaMeters = 1500.0
    static let maxAltitudeJitterMeters = 15.0
    static let minPlausiblePressureHpa: Float = 300
    static let maxPlausiblePressureHpa: Float = 1100
    private static let isaScale = 44330.0
    private static let isaExponent = 5.255

    static func clampQnh(_ hpa: Float) -> Float { min(maxQnhHpa, max(minQnhHpa, hpa)) }

    static func clampOffset(_ hpa: Float) -> Float {
        guard hpa.isFinite else { return 0 }
        return min(maxOffsetHpa, max(minOffsetHpa, hpa))
    }

    static func isPlausiblePressureHpa(_ hpa: Float) -> Bool {
        hpa.isFinite && hpa >= minPlausiblePressureHpa && hpa <= maxPlausiblePressureHpa
    }

    static func expectedStationHpa(gpsMeters: Double, qnhHpa: Float) -> Float? {
        let qnh = clampQnh(qnhHpa)
        guard gpsMeters.isFinite, qnh > 0 else { return nil }
        let ratio = 1.0 - gpsMeters / isaScale
        guard ratio > 0 else { return nil }
        return qnh * Float(pow(ratio, isaExponent))
    }

    static func offsetHpa(pressureHpa: Float, gpsMeters: Double, qnhHpa: Float) -> Float {
        guard isPlausiblePressureHpa(pressureHpa), let expected = expectedStationHpa(gpsMeters: gpsMeters, qnhHpa: qnhHpa) else {
            return 0
        }
        return clampOffset(pressureHpa - expected)
    }

    static func autoCalibrateEligible(
        pressureHpa: Float?,
        gpsAltitudeMeters: Double?,
        alreadyCalibratedThisSession: Bool,
        enabled: Bool,
        previousGpsAltitudeMeters: Double?
    ) -> Bool {
        guard enabled, !alreadyCalibratedThisSession else { return false }
        guard let pressureHpa, isPlausiblePressureHpa(pressureHpa),
              let gpsAltitudeMeters, let previousGpsAltitudeMeters,
              GpsAltitude.isPlausible(gpsAltitudeMeters) else { return false }
        return abs(gpsAltitudeMeters - previousGpsAltitudeMeters) <= maxAltitudeJitterMeters
    }

    static func metersFromPressureHpa(
        _ pressureHpa: Float,
        seaLevelHpa: Float = standardAtmosphereHpa,
        offsetHpa: Float = 0
    ) -> Double? {
        let qnh = clampQnh(seaLevelHpa)
        let corrected = pressureHpa - clampOffset(offsetHpa)
        guard corrected > 0, qnh > 0 else { return nil }
        return isaScale * (1.0 - pow(Double(corrected / qnh), 1.0 / isaExponent))
    }

    static func displayedMeters(
        pressureHpa: Float?,
        storedBaro: Double?,
        qnhHpa: Float,
        offsetHpa: Float = 0,
        gpsMeters: Double? = nil
    ) -> Double? {
        let fromPressure = pressureHpa.flatMap { metersFromPressureHpa($0, seaLevelHpa: qnhHpa, offsetHpa: offsetHpa) }
        return pickDisplayed(fromPressure: fromPressure, storedBaro: storedBaro, gpsMeters: gpsMeters)
    }

    static func pickDisplayed(fromPressure: Double?, storedBaro: Double?, gpsMeters: Double?) -> Double? {
        guard let candidate = storedBaro ?? fromPressure else { return nil }
        guard let gpsMeters, gpsMeters.isFinite else { return candidate }
        if abs(candidate - gpsMeters) <= maxGpsDeltaMeters { return candidate }
        if let storedBaro, abs(storedBaro - gpsMeters) <= maxGpsDeltaMeters { return storedBaro }
        if let fromPressure, abs(fromPressure - gpsMeters) <= maxGpsDeltaMeters { return fromPressure }
        return nil
    }
}

enum BikeLeanAngle {
    static func fromGravity(ax: Float, ay: Float, az: Float) -> Float {
        Float(atan2(Double(-ax), Double(az)) * 180 / .pi)
    }
}

enum GpsQualityNotice {
    static let poorAfterMillis: Int64 = 20_000

    static func isPoor(_ elapsedSinceLastAcceptMillis: Int64) -> Bool {
        elapsedSinceLastAcceptMillis >= poorAfterMillis
    }
}

final class KalmanTrackFilter {
    private var initialized = false
    private var originLat = 0.0
    private var originLon = 0.0
    private var x = [Double](repeating: 0, count: 4)
    private var p = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
    private var lastTimestampMillis: Int64 = 0
    private var lastOutput: TrackFix?

    private let minDtSeconds = 0.05
    private let maxDtSeconds = 5.0
    private let minSigmaMeters = 2.0
    private let velocityVariance = 25.0
    private let minOutputSpeed = 0.3
    private let stationaryDisplaceMeters = 1.5
    private let positionShrink = 0.05

    func seedFrom(_ fix: TrackFix) {
        guard fix.latitude.isFinite, fix.longitude.isFinite else { return }
        if abs(fix.latitude) > 90 || abs(fix.longitude) > 180 { return }
        originLat = fix.latitude
        originLon = fix.longitude
        initializeAt(fix)
        lastOutput = fix
    }

    func observe(_ fix: TrackFix, usage: UsageType, strength: SmoothingStrength, stationaryLock: Bool) -> TrackFix {
        observe(fix, usage: usage, strength: strength.sliderValue, stationaryLock: stationaryLock)
    }

    func observe(_ fix: TrackFix, usage: UsageType, strength: Float, stationaryLock: Bool) -> TrackFix {
        guard fix.latitude.isFinite, fix.longitude.isFinite else {
            return lastOutput ?? fix
        }
        if !initialized {
            originLat = fix.latitude
            originLon = fix.longitude
            initializeAt(fix)
            return emit(fix, usage: usage, stationaryLock: stationaryLock)
        }
        let dtRaw = Double(fix.timestampMillis - lastTimestampMillis) / 1000
        let dt = min(maxDtSeconds, max(minDtSeconds, dtRaw))
        lastTimestampMillis = fix.timestampMillis
        var q = usage.processNoiseQ() * SmoothingStrength.processNoiseMultiplier(strength)
        if let previous = lastOutput, isTurning(previous, fix) {
            q *= usage.turnBoost()
        }
        predict(dt, q)
        if usage.isPedestrianMode() {
            let extra = q * dt * dt
            p[0][0] += extra
            p[1][1] += extra
        }
        let measured = GeoProjection.eastNorth(originLat: originLat, originLon: originLon, lat: fix.latitude, lon: fix.longitude)
        let innovEast = measured.0 - x[0]
        let innovNorth = measured.1 - x[1]
        let innovation = GeoProjection.hypot(innovEast, innovNorth)
        let jumpThreshold = max(50.0, 8.0 * Double(fix.accuracyMeters))
        if innovation > jumpThreshold {
            initializeAt(fix)
            return emit(fix, usage: usage, stationaryLock: stationaryLock)
        }
        update(measured.0, measured.1, max(Double(fix.accuracyMeters), minSigmaMeters))
        applyStationaryLock(fix, usage: usage, enabled: stationaryLock)
        return emit(fix, usage: usage, stationaryLock: stationaryLock)
    }

    private func initializeAt(_ fix: TrackFix) {
        let en = GeoProjection.eastNorth(originLat: originLat, originLon: originLon, lat: fix.latitude, lon: fix.longitude)
        let velocity = velocityFrom(fix)
        x[0] = en.0
        x[1] = en.1
        x[2] = velocity.0
        x[3] = velocity.1
        let sigma = max(Double(fix.accuracyMeters), minSigmaMeters)
        let variance = sigma * sigma
        p = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        p[0][0] = variance
        p[1][1] = variance
        p[2][2] = velocityVariance
        p[3][3] = velocityVariance
        lastTimestampMillis = fix.timestampMillis
        initialized = true
    }

    private func velocityFrom(_ fix: TrackFix) -> (Double, Double) {
        if fix.speedMps < 0.3 || fix.bearing == 0 { return (0, 0) }
        let rad = Double(fix.bearing) * .pi / 180
        let speed = Double(fix.speedMps)
        return (speed * sin(rad), speed * cos(rad))
    }

    private func predict(_ dt: Double, _ q: Double) {
        let f: [[Double]] = [
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ]
        let dt2 = dt * dt
        let dt3 = dt2 * dt
        let dt4 = dt2 * dt2
        let qMat: [[Double]] = [
            [q * dt4 / 4, 0, q * dt3 / 2, 0],
            [0, q * dt4 / 4, 0, q * dt3 / 2],
            [q * dt3 / 2, 0, q * dt2, 0],
            [0, q * dt3 / 2, 0, q * dt2]
        ]
        let predicted = matVec(f, x)
        for i in 0..<4 { x[i] = predicted[i] }
        p = add(matMul(matMul(f, p), transpose(f)), qMat)
    }

    private func update(_ eastMeas: Double, _ northMeas: Double, _ sigma: Double) {
        let y0 = eastMeas - x[0]
        let y1 = northMeas - x[1]
        let r = sigma * sigma
        let s00 = p[0][0] + r
        let s01 = p[0][1]
        let s10 = p[1][0]
        let s11 = p[1][1] + r
        let det = s00 * s11 - s01 * s10
        if !det.isFinite || abs(det) < 1e-12 { return }
        let inv00 = s11 / det
        let inv01 = -s01 / det
        let inv10 = -s10 / det
        let inv11 = s00 / det
        var k = Array(repeating: [Double](repeating: 0, count: 2), count: 4)
        for i in 0..<4 {
            k[i][0] = p[i][0] * inv00 + p[i][1] * inv10
            k[i][1] = p[i][0] * inv01 + p[i][1] * inv11
        }
        for i in 0..<4 {
            x[i] += k[i][0] * y0 + k[i][1] * y1
        }
        var iMinusKh = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                let kh: Double
                if j == 0 { kh = k[i][0] }
                else if j == 1 { kh = k[i][1] }
                else { kh = 0 }
                iMinusKh[i][j] = (i == j ? 1.0 : 0) - kh
            }
        }
        var krkt = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                krkt[i][j] = (k[i][0] * r * k[j][0]) + (k[i][1] * r * k[j][1])
            }
        }
        p = add(matMul(matMul(iMinusKh, p), transpose(iMinusKh)), krkt)
    }

    private func isTurning(_ previous: TrackFix, _ current: TrackFix) -> Bool {
        if SpeedAdaptiveSpacing.isInCurve(previous, current) { return true }
        guard let fromPos = SpeedAdaptiveSpacing.headingDegrees(
            fromLat: previous.latitude, fromLon: previous.longitude, toLat: current.latitude, toLon: current.longitude
        ) else { return false }
        let stateSpeed = GeoProjection.hypot(x[2], x[3])
        let reference: Float
        if previous.bearing != 0 {
            reference = previous.bearing
        } else if stateSpeed >= minOutputSpeed {
            let deg = atan2(x[2], x[3]) * 180 / .pi
            reference = Float((deg + 360).truncatingRemainder(dividingBy: 360))
        } else {
            reference = fromPos
        }
        return SpeedAdaptiveSpacing.headingChangeIsCurve(reference, fromPos)
    }

    private func applyStationaryLock(_ fix: TrackFix, usage: UsageType, enabled: Bool) {
        guard enabled else { return }
        let pause = usage.pauseSpeedMps()
        let predictedSpeed = GeoProjection.hypot(x[2], x[3])
        let previous = lastOutput
        let displacement: Double
        if let previous {
            let held = GeoProjection.latLon(originLat: originLat, originLon: originLon, east: x[0], north: x[1])
            displacement = FixAcceptance.haversineMeters(previous.latitude, previous.longitude, held.0, held.1)
        } else {
            displacement = 0
        }
        let gpsStopped = fix.speedMps < pause
        let predictedStopped = predictedSpeed < Double(pause) && displacement < stationaryDisplaceMeters
        if !gpsStopped && !predictedStopped { return }
        if let previous {
            let en = GeoProjection.eastNorth(
                originLat: originLat, originLon: originLon, lat: previous.latitude, lon: previous.longitude
            )
            x[0] = en.0
            x[1] = en.1
        }
        x[2] = 0
        x[3] = 0
        p[0][0] *= positionShrink
        p[1][1] *= positionShrink
        p[0][1] = 0
        p[1][0] = 0
        p[0][2] = 0
        p[0][3] = 0
        p[1][2] = 0
        p[1][3] = 0
        p[2][0] = 0
        p[3][0] = 0
        p[2][1] = 0
        p[3][1] = 0
        p[2][2] = velocityVariance * positionShrink
        p[3][3] = velocityVariance * positionShrink
    }

    private func emit(_ fix: TrackFix, usage: UsageType, stationaryLock: Bool) -> TrackFix {
        let ll = GeoProjection.latLon(originLat: originLat, originLon: originLon, east: x[0], north: x[1])
        let stateSpeed = GeoProjection.hypot(x[2], x[3])
        let previous = lastOutput
        let speedOut: Float
        let bearingOut: Float
        if stateSpeed >= minOutputSpeed {
            speedOut = Float(stateSpeed)
            let deg = atan2(x[2], x[3]) * 180 / .pi
            bearingOut = Float((deg + 360).truncatingRemainder(dividingBy: 360))
        } else {
            speedOut = stationaryLock && fix.speedMps < usage.pauseSpeedMps() ? 0 : fix.speedMps
            if fix.bearing != 0 {
                bearingOut = fix.bearing
            } else if let previous {
                bearingOut = previous.bearing
            } else {
                bearingOut = 0
            }
        }
        let out = TrackFix(
            timestampMillis: fix.timestampMillis,
            latitude: ll.0,
            longitude: ll.1,
            altitude: fix.altitude,
            speedMps: speedOut,
            bearing: bearingOut,
            accuracyMeters: fix.accuracyMeters,
            satellitesInFix: fix.satellitesInFix
        )
        lastOutput = out
        return out
    }

    private func matVec(_ a: [[Double]], _ v: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 4)
        for i in 0..<4 {
            var sum = 0.0
            for j in 0..<4 { sum += a[i][j] * v[j] }
            out[i] = sum
        }
        return out
    }

    private func matMul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var out = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                var sum = 0.0
                for k in 0..<4 { sum += a[i][k] * b[k][j] }
                out[i][j] = sum
            }
        }
        return out
    }

    private func transpose(_ a: [[Double]]) -> [[Double]] {
        var out = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 { out[j][i] = a[i][j] }
        }
        return out
    }

    private func add(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var out = Array(repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 { out[i][j] = a[i][j] + b[i][j] }
        }
        return out
    }
}
