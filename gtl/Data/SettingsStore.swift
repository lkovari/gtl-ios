import Foundation

struct GtlSettings: Equatable {
    var disclaimerAccepted: Bool
    var usageType: UsageType
    var measurementSystem: MeasurementSystem
    var minDistanceMeters: Float
    var minTimeMillis: Int64
    var minAccuracyMeters: Int
    var minSatellites: Int
    var useOfflineMap: Bool
    var selectedMapId: String
    var optimizationTolerance: Double
    var optimizationActive: Bool
    var showLastTrackOnMap: Bool
    var keepWholeTrackOnScreen: Bool
    var speedLegendAlwaysOpen: Bool
    var showAccuracyMarker: Bool
    var showFixCloud: Bool
    var keepScreenOnWhileLogging: Bool
    var trackSmoothingEnabled: Bool
    var smoothingStrengthValue: Float
    var stationaryLockEnabled: Bool
    var recordingDensityValue: Float
    var gnssOnly: Bool
    var compassTrueNorth: Bool
    var qnhHpa: Float
    var baroPressureOffsetHpa: Float
    var autoCalibrateBaroEnabled: Bool
    var mapLayer: MapLayer
    var osm: OsmRenderOptions
    var tuhu: TuhuRenderOptions

    static func placeholder(usage: UsageType = .TWO_WHEELERS) -> GtlSettings {
        let smoothing = usage.defaultSmoothing()
        let filter = usage.defaultFilter()
        return GtlSettings(
            disclaimerAccepted: false,
            usageType: usage,
            measurementSystem: usage.defaultMeasurementSystem(),
            minDistanceMeters: filter.minDistanceMeters,
            minTimeMillis: filter.minTimeMillis,
            minAccuracyMeters: filter.minAccuracyMeters,
            minSatellites: filter.minSatellites,
            useOfflineMap: false,
            selectedMapId: "",
            optimizationTolerance: smoothing.optimizationToleranceMeters,
            optimizationActive: smoothing.optimizationActive,
            showLastTrackOnMap: true,
            keepWholeTrackOnScreen: false,
            speedLegendAlwaysOpen: true,
            showAccuracyMarker: true,
            showFixCloud: false,
            keepScreenOnWhileLogging: false,
            trackSmoothingEnabled: smoothing.trackSmoothingEnabled,
            smoothingStrengthValue: smoothing.smoothingStrength.sliderValue,
            stationaryLockEnabled: smoothing.stationaryLockEnabled,
            recordingDensityValue: smoothing.recordingDensity.sliderValue,
            gnssOnly: smoothing.gnssOnly,
            compassTrueNorth: false,
            qnhHpa: BaroAltitude.standardAtmosphereHpa,
            baroPressureOffsetHpa: 0,
            autoCalibrateBaroEnabled: true,
            mapLayer: .standard,
            osm: OsmRenderOptions.defaults(usage: usage),
            tuhu: TuhuRenderOptions.defaults()
        )
    }

    var filter: FixFilter {
        FixFilter(
            minDistanceMeters: minDistanceMeters,
            minTimeMillis: minTimeMillis,
            minAccuracyMeters: minAccuracyMeters,
            minSatellites: minSatellites
        )
    }
}

enum MapLayer: String, CaseIterable, Codable {
    case standard
    case satellite
    case hybrid
}

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GtlSettings {
        var settings = GtlSettings.placeholder()
        if defaults.object(forKey: "disclaimer") != nil {
            settings.disclaimerAccepted = defaults.bool(forKey: "disclaimer")
        }
        if let raw = defaults.string(forKey: "usage"), let usage = UsageType(rawValue: raw) {
            settings.usageType = usage
        }
        if let raw = defaults.string(forKey: "units"), let system = MeasurementSystem(rawValue: raw) {
            settings.measurementSystem = system
        }
        if defaults.object(forKey: "min_distance") != nil { settings.minDistanceMeters = defaults.float(forKey: "min_distance") }
        if defaults.object(forKey: "min_time") != nil { settings.minTimeMillis = Int64(defaults.integer(forKey: "min_time")) }
        if defaults.object(forKey: "min_accuracy") != nil { settings.minAccuracyMeters = defaults.integer(forKey: "min_accuracy") }
        if defaults.object(forKey: "min_sats") != nil { settings.minSatellites = defaults.integer(forKey: "min_sats") }
        if defaults.object(forKey: "offline") != nil { settings.useOfflineMap = defaults.bool(forKey: "offline") }
        settings.selectedMapId = defaults.string(forKey: "selected_map") ?? ""
        if defaults.object(forKey: "opt_tol") != nil { settings.optimizationTolerance = defaults.double(forKey: "opt_tol") }
        if defaults.object(forKey: "opt_on") != nil { settings.optimizationActive = defaults.bool(forKey: "opt_on") }
        if defaults.object(forKey: "show_last") != nil { settings.showLastTrackOnMap = defaults.bool(forKey: "show_last") }
        if defaults.object(forKey: "keep_whole") != nil { settings.keepWholeTrackOnScreen = defaults.bool(forKey: "keep_whole") }
        settings.speedLegendAlwaysOpen = bool("speed_legend_open", settings.speedLegendAlwaysOpen)
        if defaults.object(forKey: "show_acc") != nil { settings.showAccuracyMarker = defaults.bool(forKey: "show_acc") }
        if defaults.object(forKey: "show_cloud") != nil { settings.showFixCloud = defaults.bool(forKey: "show_cloud") }
        if defaults.object(forKey: "keep_screen") != nil { settings.keepScreenOnWhileLogging = defaults.bool(forKey: "keep_screen") }
        if defaults.object(forKey: "smooth") != nil { settings.trackSmoothingEnabled = defaults.bool(forKey: "smooth") }
        if defaults.object(forKey: "smooth_v") != nil { settings.smoothingStrengthValue = defaults.float(forKey: "smooth_v") }
        if defaults.object(forKey: "stationary") != nil { settings.stationaryLockEnabled = defaults.bool(forKey: "stationary") }
        if defaults.object(forKey: "density") != nil { settings.recordingDensityValue = defaults.float(forKey: "density") }
        if defaults.object(forKey: "gnss_only") != nil { settings.gnssOnly = defaults.bool(forKey: "gnss_only") }
        if defaults.object(forKey: "true_north") != nil { settings.compassTrueNorth = defaults.bool(forKey: "true_north") }
        if defaults.object(forKey: "qnh") != nil { settings.qnhHpa = defaults.float(forKey: "qnh") }
        if defaults.object(forKey: "baro_off") != nil { settings.baroPressureOffsetHpa = defaults.float(forKey: "baro_off") }
        if defaults.object(forKey: "baro_auto") != nil { settings.autoCalibrateBaroEnabled = defaults.bool(forKey: "baro_auto") }
        if let raw = defaults.string(forKey: "map_layer"), let layer = MapLayer(rawValue: raw) { settings.mapLayer = layer }
        settings.osm.buildings = bool("osm_buildings", settings.osm.buildings)
        settings.osm.poi = bool("osm_poi", settings.osm.poi)
        settings.osm.transit = bool("osm_transit", settings.osm.transit)
        settings.osm.cycleways = bool("osm_cycle", settings.osm.cycleways)
        settings.osm.parks = bool("osm_parks", settings.osm.parks)
        settings.osm.hillshading = bool("osm_hills", settings.osm.hillshading)
        settings.tuhu.blazes = bool("tuhu_blazes", settings.tuhu.blazes)
        settings.tuhu.paths = bool("tuhu_paths", settings.tuhu.paths)
        settings.tuhu.contours = bool("tuhu_contours", settings.tuhu.contours)
        settings.tuhu.contoursMinor = bool("tuhu_contours_minor", settings.tuhu.contoursMinor)
        settings.tuhu.hikePoi = bool("tuhu_hike", settings.tuhu.hikePoi)
        settings.tuhu.parks = bool("tuhu_parks", settings.tuhu.parks)
        settings.tuhu.urbanPoi = bool("tuhu_urban", settings.tuhu.urbanPoi)
        settings.tuhu.hillshading = bool("tuhu_hills", settings.tuhu.hillshading)
        return settings
    }

    func save(_ settings: GtlSettings) {
        defaults.set(settings.disclaimerAccepted, forKey: "disclaimer")
        defaults.set(settings.usageType.rawValue, forKey: "usage")
        defaults.set(settings.measurementSystem.rawValue, forKey: "units")
        defaults.set(settings.minDistanceMeters, forKey: "min_distance")
        defaults.set(Int(settings.minTimeMillis), forKey: "min_time")
        defaults.set(settings.minAccuracyMeters, forKey: "min_accuracy")
        defaults.set(settings.minSatellites, forKey: "min_sats")
        defaults.set(settings.useOfflineMap, forKey: "offline")
        defaults.set(settings.selectedMapId, forKey: "selected_map")
        defaults.set(settings.optimizationTolerance, forKey: "opt_tol")
        defaults.set(settings.optimizationActive, forKey: "opt_on")
        defaults.set(settings.showLastTrackOnMap, forKey: "show_last")
        defaults.set(settings.keepWholeTrackOnScreen, forKey: "keep_whole")
        defaults.set(settings.speedLegendAlwaysOpen, forKey: "speed_legend_open")
        defaults.set(settings.showAccuracyMarker, forKey: "show_acc")
        defaults.set(settings.showFixCloud, forKey: "show_cloud")
        defaults.set(settings.keepScreenOnWhileLogging, forKey: "keep_screen")
        defaults.set(settings.trackSmoothingEnabled, forKey: "smooth")
        defaults.set(settings.smoothingStrengthValue, forKey: "smooth_v")
        defaults.set(settings.stationaryLockEnabled, forKey: "stationary")
        defaults.set(settings.recordingDensityValue, forKey: "density")
        defaults.set(settings.gnssOnly, forKey: "gnss_only")
        defaults.set(settings.compassTrueNorth, forKey: "true_north")
        defaults.set(settings.qnhHpa, forKey: "qnh")
        defaults.set(settings.baroPressureOffsetHpa, forKey: "baro_off")
        defaults.set(settings.autoCalibrateBaroEnabled, forKey: "baro_auto")
        defaults.set(settings.mapLayer.rawValue, forKey: "map_layer")
        defaults.set(settings.osm.buildings, forKey: "osm_buildings")
        defaults.set(settings.osm.poi, forKey: "osm_poi")
        defaults.set(settings.osm.transit, forKey: "osm_transit")
        defaults.set(settings.osm.cycleways, forKey: "osm_cycle")
        defaults.set(settings.osm.parks, forKey: "osm_parks")
        defaults.set(settings.osm.hillshading, forKey: "osm_hills")
        defaults.set(settings.tuhu.blazes, forKey: "tuhu_blazes")
        defaults.set(settings.tuhu.paths, forKey: "tuhu_paths")
        defaults.set(settings.tuhu.contours, forKey: "tuhu_contours")
        defaults.set(settings.tuhu.contoursMinor, forKey: "tuhu_contours_minor")
        defaults.set(settings.tuhu.hikePoi, forKey: "tuhu_hike")
        defaults.set(settings.tuhu.parks, forKey: "tuhu_parks")
        defaults.set(settings.tuhu.urbanPoi, forKey: "tuhu_urban")
        defaults.set(settings.tuhu.hillshading, forKey: "tuhu_hills")
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}
