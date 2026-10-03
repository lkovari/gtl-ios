import CoreLocation
import CoreMotion
import Foundation
import MapKit
import UIKit

enum TrackerTab: String, CaseIterable {
    case gps
    case route
    case map
    case compass
}

final class OfflineCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

@MainActor
@Observable
final class TrackerModel {
    var settings: GtlSettings
    var logging = false
    var latitude: Double?
    var longitude: Double?
    var accuracy: Float?
    var verticalAccuracy: Float?
    var altitude: Double?
    var ellipsoidalAltitude: Double?
    var lastFixAt: Date?
    var speedMps: Float?
    var bearing: Float?
    var baroAltitude: Double?
    var pressureHpa: Float?
    var leanAngle: Float?
    var headingDegrees: Float?
    var headingAccuracy: Int?
    var declination: Float?
    var travelDegrees: Double?
    var mapHeading: Double = 0
    var mapPitch: Double = FollowCamera.defaultPitch
    var headingUp = true
    var tiltResetToken = 0
    var sessions: [TrackSession] = []
    var trackPreviews: [Int64: TrackPreview] = [:]
    var trackPoints: [TrackVertex] = []
    var speedRuns: [SpeedRun] = []
    var liveTail: SpeedRun?
    var sceneActive = true
    var followToken = 0
    var mapLineToken = 0
    var elevation: [ElevationSample] = []
    var selectedSessionId: Int64?
    var mapCleared = false
    var tab: TrackerTab = .map
    var status = "Idle"
    var startedAt: Int64?
    var stats = TrackStats(
        pointCount: 0, odometerMeters: 0, elapsedMillis: 0, movingMillis: 0, waitingMillis: 0,
        maxSpeedMps: 0, averageSpeedMps: 0, maxAltitude: 0, minAltitude: 0, temperatureRange: nil
    )
    var fixCloud = FixCloudSnapshot.empty
    var downloadedIds: [String] = []
    var downloadFraction: [String: Double] = [:]
    var downloadError: String?
    var catalogSizes: [String: Int64] = [:]
    var searchQuery = ""
    var searchHits: [MapSearchHit] = []
    var searchIndexing = false
    var searchBusy = false
    var offlineFeatures: [MapFeature] = []
    var basemapLoadToken = 0
    private var offlineGeneration = 0
    var target: GeoPoint?
    var focusToken = 0
    var focusZoom = 15
    var locateToken = 0
    private var centerOnNextFix = false
    var mapTapLatitude: Double?
    var mapTapLongitude: Double?
    var mapTapX: CGFloat = 0
    var mapTapY: CGFloat = 0
    var mapTapMenu = false
    var mapTapCoordinate = false
    var mapTapAddress = false
    var mapTapAddressText: String?
    var addressBusy = false
    var addressNotice: String?
    var distanceTarget: GeoPoint?
    var routeCoordinates: [GeoPoint] = []
    var routeMeters: Double?
    var routeNotice: String?
    var layerEpoch = 0
    var zoomTicket = 0
    var zoomStep = 0
    var pendingShare: URL?
    var exportNotice: String?
    var returnToMap = false
    var altimeterAvailable = false
    var poorGps = false
    var recordsWhileLocked = false
    var showErrorLog = false
    var showAlwaysExplanation = false
    var locationAuthorization: CLAuthorizationStatus = .notDetermined
    var preciseLocationRequired = false
    var pendingCellularDownload: PendingMapDownload?
    private var versionTaps: [Date] = []
    private var lastTravelDegrees: Float?
    private var compassMagnetic: Float?
    private var compassShift: Float?
    private var routeTask: Task<Void, Never>?
    private var activeDirections: MKDirections?
    private var geocoder: CLGeocoder?
    private var addressGeneration = 0

    private let store: SettingsStore
    private let database: TrackDatabase?
    private let places: PlaceIndex?
    private let location: LocationSession
    private let motion: MotionSession
    private let downloader: MapDownloader
    private var sessionId: Int64?
    private var lastAccepted: TrackFix?
    private var lastAcceptMillis: Int64?
    private var lastSpeed: Float = 0
    private var previousGpsAltitude: Double?
    private var baroCalibrated = false
    private let filter = KalmanTrackFilter()
    private let cloud = FixCloudBuffer()
    private var samples: [TrackSample] = []
    private var statsFold = TrackStatsFold()
    private var displayTrack = DisplayTrack()
    private var displayDirty = false
    private var accel = (Float(0), Float(0), Float(0))
    private var gravity = (Float(0), Float(0), Float(1))
    private var latestLatitude: Double?
    private var latestLongitude: Double?
    private var latestAccuracy: Float?
    private var latestVerticalAccuracy: Float?
    private var latestAltitude: Double?
    private var latestEllipsoidalAltitude: Double?
    private var latestFixAt: Date?
    private var latestSpeed: Float?
    private var latestBearing: Float?
    private var latestHeadingDegrees: Float?
    private var latestHeadingAccuracy: Int?
    private var latestDeclination: Float?
    private var latestTravelDegrees: Double?
    private var latestLean: Float?
    private var latestBaro: Double?
    private var latestPressure: Float?
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var offlineTask: Task<Void, Never>?
    private var offlineCancel = OfflineCancel()
    private var writeChain: Task<Void, Never>?
    private var tileCache = OfflineTileCache()
    private var mapReader: MapFileReader?
    private var basemapHeld = false
    private var mapHasTiles = false
    private var tilesDirty = false
    private var lastTilePublish = Date.distantPast
    private var indexKey = ""
    private var indexGeneration = 0

    init() {
        let settingsStore = SettingsStore()
        store = settingsStore
        settings = settingsStore.load()
        database = try? TrackDatabase()
        places = try? PlaceIndex()
        location = LocationSession()
        motion = MotionSession()
        downloader = MapDownloader()
        altimeterAvailable = motion.altimeterAvailable
        locationAuthorization = location.authorization
        wire()
        refreshMaps()
        syncBasemap()
        Task { await reloadSessions() }
    }

    var hillshadeAvailable: Bool {
        guard effectiveOffline, let url = try? MapPaths.mapFile(id: settings.selectedMapId) else { return false }
        return OsmHillshading.available(mapFile: url)
    }

    var effectiveOffline: Bool {
        OsmOfflineAvailability.effectiveUseOffline(wantOffline: settings.useOfflineMap, hasDownloadedMap: downloadedIds.contains(settings.selectedMapId))
    }

    var hudMode: MapHudMode {
        MapHudVisibility.mode(logging: logging, selectedSessionId: selectedSessionId, hasFix: latitude != nil)
    }

    var trackVisible: Bool {
        MapTrackVisibility.visible(
            logging: logging,
            showLastTrackOnMap: settings.showLastTrackOnMap,
            selectedSessionId: selectedSessionId,
            mapCleared: mapCleared
        )
    }

    func drawnPoints() -> [GeoPoint] {
        var points: [GeoPoint] = []
        for run in speedRuns {
            if points.isEmpty {
                points.append(contentsOf: run.points)
            } else {
                points.append(contentsOf: run.points.dropFirst())
            }
        }
        if let tail = liveTail {
            if points.isEmpty {
                points.append(contentsOf: tail.points)
            } else {
                points.append(contentsOf: tail.points.dropFirst())
            }
        }
        return points
    }

    func setSceneActive(_ active: Bool) {
        guard sceneActive != active else { return }
        sceneActive = active
        syncBasemap()
        guard active else { return }
        publishLiveFix()
        if logging {
            refreshElevation(force: true)
        }
    }

    private var publishesLiveUI: Bool { !logging || sceneActive }

    private func displayToleranceMeters() -> Double {
        if settings.optimizationActive {
            return settings.optimizationTolerance
        }
        return settings.usageType.defaultSmoothing().optimizationToleranceMeters
    }

    private func rebuildSpeedRuns() {
        displayTrack.rebuild(
            points: trackVisible ? trackPoints : [],
            usage: settings.usageType,
            toleranceMeters: displayToleranceMeters()
        )
        displayDirty = true
        guard publishesLiveUI else { return }
        speedRuns = displayTrack.runs
        displayDirty = false
        refreshLiveTail()
        mapLineToken += 1
    }

    private func noteSample(_ sample: TrackSample) {
        let previous = samples.last
        statsFold.add(sample, previous: previous)
        samples.append(sample)
    }

    private func refreshElevation(force: Bool) {
        guard force || (tab == .route && publishesLiveUI) else { return }
        let baro = latestBaro
        elevation = ElevationSeries.downsample(ElevationSeries.fromPoints(trackPoints.map {
            ElevationPoint(latitude: $0.latitude, longitude: $0.longitude, gpsAltitude: $0.altitude, baroAltitude: baro)
        }))
    }

    private func refreshLiveTail() {
        guard logging, let last = trackPoints.last, let latitude = latestLatitude, let longitude = latestLongitude else {
            liveTail = nil
            return
        }
        guard FixAcceptance.haversineMeters(last.latitude, last.longitude, latitude, longitude) > 3 else {
            liveTail = nil
            return
        }
        liveTail = SpeedRun(
            id: -1,
            bin: SpeedColorScale.bin(speedMps: latestSpeed, usage: settings.usageType),
            points: [last.point, GeoPoint(latitude: latitude, longitude: longitude, altitude: nil)]
        )
    }

    private func publishLiveFix() {
        guard publishesLiveUI else { return }
        latitude = latestLatitude
        longitude = latestLongitude
        accuracy = latestAccuracy
        verticalAccuracy = latestVerticalAccuracy
        altitude = latestAltitude
        ellipsoidalAltitude = latestEllipsoidalAltitude
        lastFixAt = latestFixAt
        speedMps = latestSpeed
        bearing = latestBearing
        headingDegrees = latestHeadingDegrees
        headingAccuracy = latestHeadingAccuracy
        declination = latestDeclination
        travelDegrees = latestTravelDegrees
        leanAngle = latestLean
        baroAltitude = latestBaro
        pressureHpa = latestPressure
        fixCloud = cloud.snapshot()
        if !samples.isEmpty {
            stats = statsFold.stats
        }
        let lineChanged = displayDirty
        if displayDirty {
            speedRuns = displayTrack.runs
            displayDirty = false
        }
        let previousTail = liveTail
        refreshLiveTail()
        if lineChanged || liveTail != previousTail {
            mapLineToken += 1
        }
        if logging {
            followToken += 1
        }
    }

    private func publishHeading() {
        guard publishesLiveUI else { return }
        headingDegrees = latestHeadingDegrees
        headingAccuracy = latestHeadingAccuracy
        declination = latestDeclination
        let previous = travelDegrees
        travelDegrees = latestTravelDegrees
        if logging && travelDegrees != previous {
            followToken += 1
        }
    }

    func acceptDisclaimer() {
        settings.disclaimerAccepted = true
        store.save(settings)
    }

    func setUsage(_ usage: UsageType) {
        settings.usageType = usage
        let smoothing = usage.defaultSmoothing()
        let filter = usage.defaultFilter()
        settings.measurementSystem = usage.defaultMeasurementSystem()
        settings.minDistanceMeters = filter.minDistanceMeters
        settings.minTimeMillis = filter.minTimeMillis
        settings.minAccuracyMeters = filter.minAccuracyMeters
        settings.minSatellites = filter.minSatellites
        settings.trackSmoothingEnabled = smoothing.trackSmoothingEnabled
        settings.smoothingStrengthValue = smoothing.smoothingStrength.sliderValue
        settings.stationaryLockEnabled = smoothing.stationaryLockEnabled
        settings.recordingDensityValue = smoothing.recordingDensity.sliderValue
        settings.optimizationActive = smoothing.optimizationActive
        settings.optimizationTolerance = smoothing.optimizationToleranceMeters
        settings.gnssOnly = smoothing.gnssOnly
        settings.osm.cycleways = OsmRenderOptions.cyclewaysForUsage(usage)
        store.save(settings)
        rebuildSpeedRuns()
        self.filter.seedFrom(lastAccepted ?? TrackFix(
            timestampMillis: 0, latitude: 0, longitude: 0, altitude: 0, speedMps: 0, bearing: 0, accuracyMeters: 1, satellitesInFix: -1
        ))
    }

    func updateSettings(_ mutate: (inout GtlSettings) -> Void) {
        mutate(&settings)
        if settings.showFixCloud { settings.showAccuracyMarker = true }
        settings.qnhHpa = BaroAltitude.clampQnh(settings.qnhHpa)
        settings.baroPressureOffsetHpa = BaroAltitude.clampOffset(settings.baroPressureOffsetHpa)
        settings.optimizationTolerance = DouglasPeucker.clampTolerance(settings.optimizationTolerance)
        store.save(settings)
        UIApplication.shared.isIdleTimerDisabled = logging && (settings.keepScreenOnWhileLogging || !recordsWhileLocked)
        applyOfflineFilter()
        rebuildSpeedRuns()
    }

    func resetMapTilt() {
        mapPitch = FollowCamera.defaultPitch
        headingUp = true
        tiltResetToken += 1
    }

    func startLogging() {
        preciseLocationRequired = false
        switch location.authorization {
        case .notDetermined:
            location.requestWhenInUse()
        case .denied, .restricted:
            locationAuthorization = location.authorization
        case .authorizedWhenInUse:
            showAlwaysExplanation = true
        case .authorizedAlways:
            continueAfterLocationChoice(requestAlways: false)
        @unknown default:
            break
        }
    }

    func allowBackgroundLogging() {
        showAlwaysExplanation = false
        continueAfterLocationChoice(requestAlways: true)
    }

    func logOnlyWhileUsingApp() {
        showAlwaysExplanation = false
        continueAfterLocationChoice(requestAlways: false)
    }

    private func continueAfterLocationChoice(requestAlways: Bool) {
        if requestAlways {
            location.requestAlways()
        }
        guard location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse else {
            return
        }
        Task {
            let precise = await location.ensurePreciseRoute()
            guard precise else {
                preciseLocationRequired = true
                return
            }
            preciseLocationRequired = false
            await beginSession()
        }
    }

    func stopLogging() {
        let now = nowMillis()
        logging = false
        location.stopLogging()
        recordsWhileLocked = false
        motion.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        status = "Idle"
        scheduleIndex()
        guard let sessionId else { return }
        let stop = GpsEvent(
            id: 0, sessionId: sessionId, timestamp: now, latitude: latestLatitude ?? 0, longitude: latestLongitude ?? 0,
            altitude: latestAltitude, speed: 0, bearing: latestBearing ?? 0, accuracy: latestAccuracy ?? 0, satellitesInFix: -1,
            ambientTemperature: nil, accelX: accel.0, accelY: accel.1, accelZ: accel.2, leanAngle: latestLean,
            usageType: settings.usageType.rawValue, isPlacemark: true, eventKind: EventKind.STOP.rawValue,
            baroAltitude: latestBaro, pressureHpa: latestPressure
        )
        Task {
            do {
                if latestLatitude != nil { try await database?.insert(stop) }
                try await database?.stopSession(id: sessionId, at: now)
            } catch {
                ErrorLogStore.record(action: "track.stop", error: error)
                status = "Logging stopped"
            }
            self.sessionId = nil
            await reloadSessions()
        }
    }

    func clearMapTrack() {
        mapCleared = true
        rebuildSpeedRuns()
    }

    func gpsEventsDump(for session: TrackSession) async -> String {
        let events: [GpsEvent]
        if let database {
            events = (try? await database.events(sessionId: session.id)) ?? []
        } else {
            events = []
        }
        return GpsEventsDump.text(session: session, events: events)
    }

    func loadPreview(for session: TrackSession) async {
        guard let database else { return }
        if trackPreviews[session.id] != nil && session.stoppedAt != nil { return }
        guard let preview = try? await database.preview(sessionId: session.id) else { return }
        trackPreviews[session.id] = preview
    }

    func showSession(_ id: Int64) {
        selectedSessionId = id
        mapCleared = false
        tab = .map
        returnToMap = true
        Task {
            await loadSession(id)
            frameTrack(trackPoints.map(\.point))
        }
    }

    func deleteSessions(_ ids: Set<Int64>) {
        Task {
            for id in ids {
                try? await database?.deleteSession(id: id)
            }
            if let selected = selectedSessionId, ids.contains(selected) {
                selectedSessionId = nil
                trackPoints = []
                rebuildSpeedRuns()
            }
            await reloadSessions()
        }
    }

    func share(ids: [Int64], kmz: Bool) {
        Task {
            var tracks: [KmlTrack] = []
            var gpxTracks: [GpxTrack] = []
            for id in ids {
                guard let session = sessions.first(where: { $0.id == id }),
                      let events = try? await database?.events(sessionId: id) else { continue }
                let logs = events.map(Self.logEvent)
                let name = sessionName(session.startedAt)
                let system = MeasurementSystem(rawValue: session.measurementSystem) ?? settings.measurementSystem
                tracks.append(KmlTrackBuilder.build(name: name, events: logs, system: system, qnhHpa: settings.qnhHpa, offsetHpa: settings.baroPressureOffsetHpa))
                let markers = TrackLogExport.markers(logs)
                gpxTracks.append(GpxTrack(
                    name: name,
                    points: TrackLogExport.path(logs).map { GpxTrackPoint(point: $0.point(), timestampMillis: $0.timestampMillis) },
                    waypoints: markers.map { GpxWaypoint(name: $0.kind.kmlPlacemarkName(), point: $0.event.point(), timestampMillis: $0.event.timestampMillis) }
                ))
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = documents.appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = sessionName(nowMillis())
            let url: URL
            if kmz {
                let kml = KmlExporter.export(KmlDocument(name: stamp, trackColorAabbggrr: "ff0000ff", trackWidth: 6, tracks: tracks))
                let packed = KmzExporter.pack(kml: kml, files: [
                    "icons/play.png": MarkerIcon.green,
                    "icons/pause.png": MarkerIcon.amber,
                    "icons/stop.png": MarkerIcon.red
                ])
                url = folder.appendingPathComponent("\(stamp).kmz")
                try? packed.write(to: url)
            } else {
                let gpx = GpxExporter.export(GpxDocument(tracks: gpxTracks))
                url = folder.appendingPathComponent("\(stamp).gpx")
                try? gpx.write(to: url, atomically: true, encoding: .utf8)
            }
            pendingShare = url
            exportNotice = L10n.text(
                "Saved \(url.lastPathComponent) in the Files app: On My iPhone → GPS Track Logger → Exports.",
                "Mentve: \(url.lastPathComponent). A Fájlok appban: A(z) iPhone-omon → GPS Track Logger → Exports."
            )
        }
    }

    func locateMe() {
        centerOnNextFix = true
        switch location.authorization {
        case .notDetermined:
            location.requestWhenInUse()
        case .authorizedAlways, .authorizedWhenInUse:
            location.startWatching()
            if let latitude, let longitude {
                centerOnNextFix = false
                showCurrentPosition(latitude, longitude)
            }
        default:
            centerOnNextFix = false
            locationAuthorization = location.authorization
        }
    }

    func beginMapTap(latitude: Double, longitude: Double, x: CGFloat, y: CGFloat) {
        cancelAddressLookup()
        mapTapLatitude = latitude
        mapTapLongitude = longitude
        mapTapX = x
        mapTapY = y
        mapTapMenu = true
        mapTapCoordinate = false
        routeNotice = nil
    }

    func moveMapTapAnchor(x: CGFloat, y: CGFloat) {
        guard mapTapMenu || mapTapCoordinate || mapTapAddress else { return }
        mapTapX = x
        mapTapY = y
    }

    func chooseTapDistance() {
        guard let latitude = mapTapLatitude, let longitude = mapTapLongitude else { return }
        cancelAddressLookup()
        distanceTarget = GeoPoint(latitude: latitude, longitude: longitude)
        mapTapMenu = false
    }

    func chooseTapCoordinate() {
        guard mapTapLatitude != nil, mapTapLongitude != nil else { return }
        cancelAddressLookup()
        mapTapMenu = false
        mapTapCoordinate = true
    }

    func chooseTapAddress() {
        guard let latitude = mapTapLatitude, let longitude = mapTapLongitude else { return }
        mapTapMenu = false
        mapTapCoordinate = false
        mapTapAddress = true
        mapTapAddressText = nil
        addressNotice = nil
        addressBusy = true
        addressGeneration += 1
        let generation = addressGeneration
        geocoder?.cancelGeocode()
        let coder = CLGeocoder()
        geocoder = coder
        let location = CLLocation(latitude: latitude, longitude: longitude)
        Task { @MainActor in
            let placemarks: [CLPlacemark]
            do {
                placemarks = try await coder.reverseGeocodeLocation(location)
            } catch {
                guard generation == self.addressGeneration else { return }
                self.addressBusy = false
                self.mapTapAddressText = nil
                self.addressNotice = L10n.text("Address unavailable", "A cím nem érhető el")
                return
            }
            guard generation == self.addressGeneration else { return }
            self.addressBusy = false
            let mark = placemarks.first
            if let text = MapAddressLookup.format(
                houseNumber: mark?.subThoroughfare,
                street: mark?.thoroughfare,
                locality: mark?.locality,
                postalCode: mark?.postalCode,
                country: mark?.country,
                hungarian: L10n.hungarian
            ) {
                self.mapTapAddressText = text
                self.addressNotice = nil
            } else {
                self.mapTapAddressText = nil
                self.addressNotice = L10n.text("No address", "Nincs cím")
            }
        }
    }

    func closeMapTap() {
        cancelAddressLookup()
        mapTapMenu = false
        mapTapCoordinate = false
    }

    private func cancelAddressLookup() {
        addressGeneration += 1
        geocoder?.cancelGeocode()
        geocoder = nil
        mapTapAddress = false
        mapTapAddressText = nil
        addressBusy = false
        addressNotice = nil
    }

    func clearDistance() {
        distanceTarget = nil
    }

    func chooseTapRoute(_ transport: RouteTransport) {
        guard let destinationLatitude = mapTapLatitude, let destinationLongitude = mapTapLongitude else { return }
        guard let originLatitude = latitude, let originLongitude = longitude else {
            routeNotice = L10n.text("No GPS", "Nincs GPS")
            return
        }
        cancelAddressLookup()
        mapTapMenu = false
        activeDirections?.cancel()
        routeTask?.cancel()
        routeCoordinates = []
        routeMeters = nil
        routeNotice = nil
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: originLatitude, longitude: originLongitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)))
        switch transport {
        case .walking:
            request.transportType = .walking
        case .cycling:
            request.transportType = .cycling
        case .automobile:
            request.transportType = .automobile
        }
        let directions = MKDirections(request: request)
        activeDirections = directions
        routeTask = Task { @MainActor [weak self] in
            let response: MKDirections.Response
            do {
                response = try await directions.calculate()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.routeNotice = L10n.text("No route", "Nincs útvonal")
                self.activeDirections = nil
                return
            }
            guard let self, !Task.isCancelled else { return }
            guard let route = response.routes.first, route.polyline.pointCount >= 2 else {
                self.routeNotice = L10n.text("No route", "Nincs útvonal")
                self.activeDirections = nil
                return
            }
            let count = route.polyline.pointCount
            var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: count)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
            self.routeCoordinates = coordinates.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude, altitude: nil) }
            self.routeMeters = route.distance
            self.routeNotice = nil
            self.activeDirections = nil
        }
    }

    func clearRoute() {
        activeDirections?.cancel()
        activeDirections = nil
        routeTask?.cancel()
        routeTask = nil
        routeCoordinates = []
        routeMeters = nil
        routeNotice = nil
    }

    private func showCurrentPosition(_ latitude: Double, _ longitude: Double) {
        target = GeoPoint(latitude: latitude, longitude: longitude)
        focusZoom = 16
        focusToken += 1
        locateToken += 1
    }

    func refreshOffline(bounds: LatLonBounds, zoom: Int) {
        guard basemapWanted, let reader = openReader() else { return }
        let header = reader.header
        let minLat = max(bounds.minLatitude, header.bounds.minLatitude)
        let maxLat = min(bounds.maxLatitude, header.bounds.maxLatitude)
        let minLon = max(bounds.minLongitude, header.bounds.minLongitude)
        let maxLon = min(bounds.maxLongitude, header.bounds.maxLongitude)
        guard minLat < maxLat, minLon < maxLon else { return }
        let clipped = LatLonBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
        let travel = latestTravelDegrees ?? travelDegrees
        let padded = Self.clip(Self.queryBounds(clipped, travelDegrees: travel), to: header.bounds)
        guard padded.minLatitude < padded.maxLatitude, padded.minLongitude < padded.maxLongitude else { return }
        let featureLimit = 4800
        let poiLimit = 28
        let requests = reader.visibleTiles(bounds: padded, focus: clipped, zoom: zoom, featureLimit: featureLimit, poiLimit: poiLimit)
        let visibleIds = Set(requests.map(\.id))
        let centerLatitude = (clipped.minLatitude + clipped.maxLatitude) / 2
        let centerLongitude = (clipped.minLongitude + clipped.maxLongitude) / 2
        let pinned = Self.centerTile(requests, latitude: centerLatitude, longitude: centerLongitude)
        let missing = requests.filter {
            tileCache.needsRefresh(id: $0.id, queryZoom: $0.queryZoom, bounds: clipped)
        }
        if missing.isEmpty {
            if tileCache.update(
                visibleIds: visibleIds,
                decoded: [],
                travelDegrees: travel,
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                pinnedIds: pinned
            ) || tilesDirty {
                publishTiles()
            }
            allowIndex()
            return
        }
        let flag = offlineCancel
        offlineTask?.cancel()
        offlineGeneration += 1
        let generation = offlineGeneration
        let pending = missing
        offlineTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            for request in pending {
                guard !Task.isCancelled, generation == self.offlineGeneration, self.basemapWanted else { return }
                let decoded = await Task.detached(priority: .userInitiated) {
                    reader.decode([request], isCancelled: { flag.cancelled })
                }.value
                guard self.basemapWanted, self.mapReader === reader else { return }
                guard !Task.isCancelled, generation == self.offlineGeneration else {
                    if !decoded.isEmpty {
                        self.tileCache.keep(decoded)
                        self.tilesDirty = true
                    }
                    return
                }
                if self.tileCache.update(
                    visibleIds: visibleIds,
                    decoded: decoded,
                    travelDegrees: travel,
                    centerLatitude: centerLatitude,
                    centerLongitude: centerLongitude,
                    pinnedIds: pinned
                ) {
                    self.tilesDirty = true
                }
                if self.tilesDirty, Date().timeIntervalSince(self.lastTilePublish) > 0.4 {
                    self.publishTiles()
                }
            }
            guard generation == self.offlineGeneration, self.basemapWanted else { return }
            if self.tilesDirty { self.publishTiles() }
            self.allowIndex()
        }
    }

    private static func centerTile(_ requests: [MapsforgeTileRequest], latitude: Double, longitude: Double) -> Set<MapsforgeTileId> {
        guard let closest = requests.min(by: {
            hypot($0.latitude - latitude, $0.longitude - longitude) < hypot($1.latitude - latitude, $1.longitude - longitude)
        }) else { return [] }
        return [closest.id]
    }

    func search() {
        searchTask?.cancel()
        let query = searchQuery
        guard MapSearch.accepts(query) else {
            searchHits = []
            searchBusy = false
            return
        }
        searchBusy = true
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            await self.runSearch(query, generation)
        }
    }

    func selectSearchHit(_ hit: MapSearchHit) {
        target = GeoPoint(latitude: hit.latitude, longitude: hit.longitude)
        focusZoom = hit.kind.zoom()
        focusToken += 1
    }

    private func runSearch(_ query: String, _ generation: Int) async {
        guard generation == searchGeneration else { return }
        if effectiveOffline {
            var candidates = MapsforgeReader.searchCandidates(offlineFeatures)
            if let match = MapSearch.ftsMatch(query), let places {
                let indexed = (try? await places.search(match: match, limit: 40)) ?? []
                candidates.append(contentsOf: indexed)
            }
            guard generation == searchGeneration else { return }
            let originLat = latitude ?? target?.latitude ?? 47.5
            let originLon = longitude ?? target?.longitude ?? 19.0
            searchHits = MapSearch.rank(rawQuery: query, candidates: candidates, originLatitude: originLat, originLongitude: originLon)
            searchBusy = false
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let latitude, let longitude {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
            )
        }
        let response = try? await MKLocalSearch(request: request).start()
        guard generation == searchGeneration else { return }
        let originLat = latitude ?? 0
        let originLon = longitude ?? 0
        searchHits = (response?.mapItems ?? []).prefix(8).map { item in
            let coordinate = item.placemark.coordinate
            let distance = latitude == nil ? 0 : FixAcceptance.haversineMeters(originLat, originLon, coordinate.latitude, coordinate.longitude)
            return MapSearchHit(
                name: item.name ?? query,
                kind: .Place,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distanceMeters: distance
            )
        }
        searchBusy = false
    }

    func commitMapLayers() {
        guard basemapWanted else { return }
        layerEpoch += 1
    }

    func bumpZoom(_ step: Int) {
        zoomStep = step
        zoomTicket += 1
    }

    private func applyOfflineFilter() {
        syncBasemap()
        if basemapWanted {
            layerEpoch += 1
        }
    }

    func useMap(_ id: String) {
        releaseBasemap()
        settings.selectedMapId = id
        settings.useOfflineMap = true
        store.save(settings)
        refreshMaps()
        syncBasemap()
    }

    func stopUsingOffline() {
        settings.useOfflineMap = false
        store.save(settings)
        syncBasemap()
    }

    func deleteMap(_ id: String) {
        downloader.cancel(id)
        let deletingSelected = settings.selectedMapId == id
        if let url = try? MapPaths.mapFile(id: id) { try? FileManager.default.removeItem(at: url) }
        refreshMaps()
        let region = OsmCatalog.regions.first { $0.id == id }
        let locale = Locale.current.region?.identifier ?? ""
        let force = OsmOfflineAvailability.forceOnlineAfterDelete(
            deletingSelected: deletingSelected,
            localeMatch: region.map { OsmMapLocale.countryMatches(regionCountryCode: $0.countryCode, localeCountry: locale) } ?? false,
            mapsRemain: !downloadedIds.isEmpty
        )
        if force || deletingSelected {
            settings.useOfflineMap = false
            if deletingSelected { settings.selectedMapId = "" }
            store.save(settings)
        }
        syncBasemap()
    }

    func download(_ region: OsmRegion) {
        Task {
            await prepareDownload(url: region.url, id: region.id, title: region.label, cap: DownloadBudget.maxOsmBytes, restrictURL: false)
        }
    }

    func downloadTuhu() {
        Task {
            await prepareDownload(
                url: OsmCatalog.tuhuURL,
                id: OsmCatalog.tuhuId,
                title: "Turistautak.hu",
                cap: DownloadBudget.maxTuhuDownloadBytes,
                restrictURL: true
            )
        }
    }

    func loadCatalogSizes() async {
        var targets = OsmCatalog.regions.map { ($0.id, $0.url) }
        targets.append((OsmCatalog.tuhuId, OsmCatalog.tuhuURL))
        targets.removeAll { catalogSizes[$0.0] != nil }
        await withTaskGroup(of: (String, Int64?).self) { group in
            for (id, url) in targets {
                group.addTask { (id, await DownloadSize.contentLength(of: url)) }
            }
            for await (id, length) in group {
                if let length { catalogSizes[id] = length }
            }
        }
    }

    func confirmCellularDownload() {
        guard let pending = pendingCellularDownload else { return }
        pendingCellularDownload = nil
        startPrepared(pending)
    }

    func cancelCellularDownload() {
        pendingCellularDownload = nil
    }

    private func prepareDownload(url: URL, id: String, title: String, cap: Int64, restrictURL: Bool) async {
        downloadError = nil
        if restrictURL && !DownloadBudget.tuhuURLAllowed(url) {
            downloadError = L10n.text("Download address is not allowed", "A letöltési cím nem engedélyezett")
            return
        }
        guard let length = await DownloadSize.contentLength(of: url) else {
            downloadError = L10n.text("The download size could not be read.", "A letöltés mérete nem olvasható.")
            return
        }
        let space = MapDownloader.freeSpace()
        if length > cap {
            downloadError = L10n.text("The file is larger than this download allows.", "A fájl nagyobb, mint amit ez a letöltés enged.")
            return
        }
        guard DownloadBudget.canStart(contentLength: length, usableSpace: space, cap: cap) else {
            downloadError = L10n.text("Not enough free space", "Nincs elég szabad hely")
            return
        }
        let pending = PendingMapDownload(id: id, title: title, bytes: length, url: url, cap: cap)
        if await CellularAccess.usesCellular() {
            pendingCellularDownload = pending
            return
        }
        startPrepared(pending)
    }

    private func startPrepared(_ pending: PendingMapDownload) {
        let space = MapDownloader.freeSpace()
        let budget = min(pending.cap, space - DownloadBudget.reserveBytes)
        downloader.start(pending.url, id: pending.id, byteBudget: max(budget, 0))
    }

    func onTabChange() {
        syncBasemap()
        if tab == .route {
            refreshElevation(force: true)
        }
        if logging {
            if tab == .compass || tab == .map { location.startHeading() } else { location.stopHeading() }
            return
        }
        if tab == .compass {
            location.stopWatching()
            location.startHeading()
        } else if tab == .map || tab == .gps {
            location.stopHeading()
            location.startWatching()
        } else {
            location.stopHeading()
            location.stopWatching()
        }
    }

    func tapVersion() {
        let now = Date()
        versionTaps.append(now)
        versionTaps.removeAll { now.timeIntervalSince($0) > 2 }
        if versionTaps.count >= 7 {
            versionTaps.removeAll()
            showErrorLog = true
        }
    }

    private func wire() {
        location.onFix = { [weak self] fix in self?.ingest(fix) }
        location.onHeading = { [weak self] heading in
            guard let self else { return }
            self.latestHeadingDegrees = Float(heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading)
            self.latestDeclination = Float(heading.trueHeading - heading.magneticHeading)
            self.latestHeadingAccuracy = Int(heading.headingAccuracy.rounded())
            self.compassMagnetic = Float(heading.magneticHeading)
            self.compassShift = heading.trueHeading >= 0 ? Float(heading.trueHeading - heading.magneticHeading) : nil
            self.refreshTravelHeading()
            self.publishHeading()
        }
        location.onAuthorization = { [weak self] status in
            guard let self else { return }
            self.locationAuthorization = status
            self.recordsWhileLocked = self.location.recordsWhileLocked
            if self.logging {
                UIApplication.shared.isIdleTimerDisabled = self.settings.keepScreenOnWhileLogging || !self.recordsWhileLocked
            }
            self.status = self.logging ? "Logging" : "Idle"
            self.onTabChange()
        }
        motion.onMotion = { [weak self] data in
            guard let self else { return }
            self.gravity = (Float(data.gravity.x), Float(data.gravity.y), Float(data.gravity.z))
            self.accel = (Float(data.userAcceleration.x), Float(data.userAcceleration.y), Float(data.userAcceleration.z))
            self.latestLean = BikeLeanAngle.fromGravity(ax: self.gravity.0, ay: self.gravity.1, az: self.gravity.2)
            guard self.publishesLiveUI else { return }
            self.leanAngle = self.latestLean
        }
        motion.onPressure = { [weak self] data in
            guard let self else { return }
            let kPa = data.pressure.doubleValue
            self.latestPressure = Float(kPa * 10)
            self.latestBaro = BaroAltitude.displayedMeters(
                pressureHpa: self.latestPressure,
                storedBaro: nil,
                qnhHpa: self.settings.qnhHpa,
                offsetHpa: self.settings.baroPressureOffsetHpa,
                gpsMeters: self.latestAltitude
            )
            guard self.publishesLiveUI else { return }
            self.pressureHpa = self.latestPressure
            self.baroAltitude = self.latestBaro
        }
        downloader.onProgress = { [weak self] id, fraction in self?.downloadFraction[id] = fraction }
        downloader.onFailed = { [weak self] _, message in self?.downloadError = message }
        downloader.onFinished = { [weak self] id, temp in self?.finishDownload(id: id, temp: temp) }
    }

    private func beginSession() async {
        let now = nowMillis()
        do {
            let id = try await database?.startSession(
                at: now,
                usage: settings.usageType.rawValue,
                system: settings.measurementSystem.rawValue
            )
            sessionId = id
            logging = true
            cancelIndex()
            mapCleared = false
            selectedSessionId = nil
            startedAt = now
            lastAccepted = nil
            lastAcceptMillis = nil
            baroCalibrated = false
            samples = []
            statsFold = TrackStatsFold()
            trackPoints = []
            rebuildSpeedRuns()
            headingUp = true
            if mapPitch < 20 { mapPitch = FollowCamera.defaultPitch }
            cloud.clear()
            status = "Logging"
            location.startLogging(activity: activityType(settings.usageType))
            recordsWhileLocked = location.recordsWhileLocked
            if tab == .compass || tab == .map { location.startHeading() }
            motion.startLoggingSensors()
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOnWhileLogging || !recordsWhileLocked
        } catch {
            ErrorLogStore.record(action: "track.insert", error: error)
            status = "Logging stopped"
        }
    }

    private func ingest(_ location: RecordedFix) {
        let age = Date().timeIntervalSince(location.timestamp)
        let fixMillis = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        guard FixAcceptance.keepFix(
            logging: logging,
            ageSeconds: age,
            locating: centerOnNextFix,
            fixMillis: fixMillis,
            startedAtMillis: startedAt,
            lastAcceptMillis: lastAcceptMillis
        ) else { return }
        let hasAccuracy = location.horizontalAccuracy >= 0
        guard FixAcceptance.hasUsableAccuracy(hasAccuracy, Float(location.horizontalAccuracy)) else { return }
        latestLatitude = location.latitude
        latestLongitude = location.longitude
        latestAccuracy = Float(location.horizontalAccuracy)
        latestFixAt = location.timestamp
        if location.verticalAccuracy >= 0 {
            latestVerticalAccuracy = Float(location.verticalAccuracy)
            latestAltitude = GpsAltitude.pick(
                gnssMsl: location.altitude,
                fusedMsl: nil,
                gnssEllipsoid: location.ellipsoidalAltitude,
                fusedEllipsoid: nil
            )
            latestEllipsoidalAltitude = GpsAltitude.isPlausible(location.ellipsoidalAltitude) ? location.ellipsoidalAltitude : nil
        } else {
            latestVerticalAccuracy = nil
            latestEllipsoidalAltitude = nil
        }
        if location.speed >= 0 {
            lastSpeed = Float(location.speed)
            latestSpeed = lastSpeed
        }
        if location.course >= 0 { latestBearing = Float(location.course) }
        refreshTravelHeading()
        cloud.observe(
            FixCloudSample(
                timeMillis: nowMillis(),
                latitude: location.latitude,
                longitude: location.longitude,
                accuracyMeters: Float(location.horizontalAccuracy),
                speedMps: latestSpeed ?? 0
            ),
            pauseSpeedMps: settings.usageType.pauseSpeedMps()
        )
        if centerOnNextFix && publishesLiveUI {
            centerOnNextFix = false
            showCurrentPosition(location.latitude, location.longitude)
        }
        guard logging, let sessionId else {
            status = "Idle"
            publishLiveFix()
            return
        }
        var fix = TrackFix(
            timestampMillis: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            latitude: location.latitude,
            longitude: location.longitude,
            altitude: latestAltitude ?? 0,
            speedMps: latestSpeed ?? lastSpeed,
            bearing: latestBearing ?? 0,
            accuracyMeters: Float(location.horizontalAccuracy),
            satellitesInFix: -1
        )
        if let gpsAltitude = latestAltitude, BaroAltitude.autoCalibrateEligible(
            pressureHpa: latestPressure,
            gpsAltitudeMeters: gpsAltitude,
            alreadyCalibratedThisSession: baroCalibrated,
            enabled: settings.autoCalibrateBaroEnabled,
            previousGpsAltitudeMeters: previousGpsAltitude
        ), let pressure = latestPressure {
            settings.baroPressureOffsetHpa = BaroAltitude.offsetHpa(pressureHpa: pressure, gpsMeters: gpsAltitude, qnhHpa: settings.qnhHpa)
            baroCalibrated = true
            store.save(settings)
        }
        previousGpsAltitude = latestAltitude
        if settings.trackSmoothingEnabled {
            fix = filter.observe(fix, usage: settings.usageType, strength: settings.smoothingStrengthValue, stationaryLock: settings.stationaryLockEnabled)
        }
        let density = settings.recordingDensityValue
        guard FixAcceptance.shouldAccept(previous: lastAccepted, current: fix, filter: settings.filter, densityMix: density, usage: settings.usageType) else {
            if let last = lastAcceptMillis {
                poorGps = GpsQualityNotice.isPoor(nowMillis() - last)
                if poorGps { status = "GPS quality is too low" }
            } else if nowMillis() - (startedAt ?? nowMillis()) > GpsQualityNotice.poorAfterMillis {
                poorGps = true
                status = "Waiting for GPS"
            }
            publishLiveFix()
            return
        }
        poorGps = false
        status = "Logging"
        let kind: EventKind
        if lastAccepted == nil {
            kind = .START
        } else if fix.speedMps < settings.usageType.pauseSpeedMps() {
            kind = .PAUSE
        } else {
            kind = .MOVE
        }
        lastAccepted = fix
        lastAcceptMillis = fix.timestampMillis
        trackPoints.append(TrackVertex(latitude: fix.latitude, longitude: fix.longitude, altitude: latestAltitude, speedMps: fix.speedMps))
        displayTrack.append(trackPoints[trackPoints.count - 1], usage: settings.usageType, toleranceMeters: displayToleranceMeters())
        displayDirty = true
        noteSample(TrackSample(
            timestampMillis: fix.timestampMillis, latitude: fix.latitude, longitude: fix.longitude,
            altitude: latestAltitude, speedMps: fix.speedMps, bearing: fix.bearing, ambientTemperature: nil, eventKind: kind
        ))
        refreshElevation(force: false)
        let event = GpsEvent(
            id: 0, sessionId: sessionId, timestamp: fix.timestampMillis, latitude: fix.latitude, longitude: fix.longitude,
            altitude: latestAltitude, speed: fix.speedMps, bearing: fix.bearing, accuracy: fix.accuracyMeters, satellitesInFix: -1,
            ambientTemperature: nil, accelX: accel.0, accelY: accel.1, accelZ: accel.2, leanAngle: latestLean,
            usageType: settings.usageType.rawValue, isPlacemark: kind != .MOVE, eventKind: kind.rawValue,
            baroAltitude: latestBaro, pressureHpa: latestPressure
        )
        publishLiveFix()
        let database = database
        let previous = writeChain
        writeChain = Task {
            await previous?.value
            do { try await database?.insert(event) }
            catch { ErrorLogStore.record(action: "track.insert", error: error) }
        }
    }

    private func frameTrack(_ points: [GeoPoint]) {
        guard let bounds = TrackCameraBounds.of(points, extra: nil) else { return }
        let span = max(bounds.maxLatitude - bounds.minLatitude, bounds.maxLongitude - bounds.minLongitude, 0.002)
        target = GeoPoint(
            latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
            longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
        )
        focusZoom = MapFitZoom.clamp(Int(log2(140 / span).rounded()))
        focusToken += 1
    }

    private static func queryBounds(_ bounds: LatLonBounds, travelDegrees: Double?) -> LatLonBounds {
        guard let travelDegrees else { return bounds }
        let rad = travelDegrees * .pi / 180
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.001)
        let latitude = cos(rad) * latSpan * 0.35
        let longitude = sin(rad) * lonSpan * 0.35
        return LatLonBounds(
            minLatitude: bounds.minLatitude + min(latitude, 0),
            minLongitude: bounds.minLongitude + min(longitude, 0),
            maxLatitude: bounds.maxLatitude + max(latitude, 0),
            maxLongitude: bounds.maxLongitude + max(longitude, 0)
        )
    }

    private static func clip(_ bounds: LatLonBounds, to header: LatLonBounds) -> LatLonBounds {
        LatLonBounds(
            minLatitude: max(bounds.minLatitude, header.minLatitude),
            minLongitude: max(bounds.minLongitude, header.minLongitude),
            maxLatitude: min(bounds.maxLatitude, header.maxLatitude),
            maxLongitude: min(bounds.maxLongitude, header.maxLongitude)
        )
    }

    private func finishDownload(id: String, temp: URL) {
        Task {
            do {
                let destination = try MapPaths.mapFile(id: id)
                if id == OsmCatalog.tuhuId {
                    try TuhuPackage.install(zip: temp, destination: destination)
                } else {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: temp, to: destination)
                }
                try? FileManager.default.removeItem(at: temp)
                MapPaths.excludeFromBackup(destination)
                downloadFraction[id] = 1
                refreshMaps()
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    private func refreshMaps() {
        let dir = try? MapPaths.mapsDirectory()
        let files = (try? dir.flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }) ?? []
        downloadedIds = files.filter { $0.pathExtension == "map" && OsmMapFile.isReadable($0) }.map { $0.deletingPathExtension().lastPathComponent }
    }

    private func reloadSessions() async {
        let fresh = (try? await database?.sessions()) ?? []
        let unchanged = Set(fresh.filter { sessions.contains($0) }.map(\.id))
        trackPreviews = trackPreviews.filter { unchanged.contains($0.key) }
        sessions = fresh
    }

    private func loadSession(_ id: Int64) async {
        let events = (try? await database?.events(sessionId: id)) ?? []
        trackPoints = events.map {
            TrackVertex(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude, speedMps: $0.speed)
        }
        elevation = ElevationSeries.downsample(ElevationSeries.fromPoints(events.map {
            ElevationPoint(latitude: $0.latitude, longitude: $0.longitude, gpsAltitude: $0.altitude, baroAltitude: $0.baroAltitude)
        }))
        if let session = sessions.first(where: { $0.id == id }), let usage = UsageType(rawValue: session.usageType) {
            settings.usageType = usage
        }
        rebuildSpeedRuns()
    }

    private func refreshTravelHeading() {
        guard let aim = TravelHeading.resolve(
            courseDegrees: latestBearing,
            speedMps: latestSpeed,
            magneticHeading: compassMagnetic,
            declinationDegrees: compassShift,
            compassAccuracy: latestHeadingAccuracy ?? -1,
            lastGoodDegrees: lastTravelDegrees
        ) else { return }
        latestTravelDegrees = Double(aim.degrees)
        if !aim.dimmed { lastTravelDegrees = aim.degrees }
    }

    private var basemapWanted: Bool {
        effectiveOffline && tab == .map && sceneActive
    }

    private func syncBasemap() {
        if basemapWanted {
            let opened = !basemapHeld
            if opened {
                basemapHeld = true
                basemapLoadToken += 1
            }
            if opened || indexTask == nil {
                scheduleIndex()
            }
        } else {
            releaseBasemap()
        }
    }

    private func releaseBasemap() {
        basemapHeld = false
        offlineCancel.cancelled = true
        offlineCancel = OfflineCancel()
        offlineTask?.cancel()
        offlineTask = nil
        offlineGeneration += 1
        cancelIndex()
        mapHasTiles = false
        tilesDirty = false
        tileCache.removeAll()
        mapReader?.close()
        mapReader = nil
        guard !offlineFeatures.isEmpty else { return }
        offlineFeatures = []
        layerEpoch += 1
    }

    private func publishTiles() {
        tilesDirty = false
        lastTilePublish = Date()
        offlineFeatures = tileCache.features()
        layerEpoch += 1
    }

    private func allowIndex() {
        guard basemapWanted else { return }
        mapHasTiles = true
        scheduleIndex()
    }

    private func openReader() -> MapFileReader? {
        guard let url = try? MapPaths.mapFile(id: settings.selectedMapId) else { return nil }
        if let mapReader, mapReader.url == url { return mapReader }
        mapReader?.close()
        let opened = MapFileReader.open(url)
        mapReader = opened
        return opened
    }

    private func cancelIndex() {
        indexGeneration += 1
        indexTask?.cancel()
        indexTask = nil
        indexKey = ""
        searchIndexing = false
    }

    private func scheduleIndex() {
        guard mapHasTiles else { return }
        guard PlaceIndexPolicy.shouldStart(logging: logging, mapVisible: basemapWanted) else { return }
        guard let url = try? MapPaths.mapFile(id: settings.selectedMapId), OsmMapFile.isReadable(url) else {
            searchIndexing = false
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = Int64((((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970) ?? 0) * 1000)
        let key = "\(url.path)#\(bytes)#\(modified)"
        if indexTask != nil, indexKey == key { return }
        indexTask?.cancel()
        indexGeneration += 1
        let generation = indexGeneration
        indexKey = key
        let places = places
        indexTask = Task.detached(priority: .background) { [places] in
            guard let reader = MapFileReader.open(url) else {
                await MainActor.run {
                    guard generation == self.indexGeneration else { return }
                    self.searchIndexing = false
                    self.indexTask = nil
                    self.indexKey = ""
                }
                return
            }
            defer { reader.close() }
            if await places?.isReady(path: url.path, bytes: bytes, modified: modified) == true {
                await MainActor.run {
                    guard generation == self.indexGeneration else { return }
                    self.searchIndexing = false
                    self.indexTask = nil
                    if MapSearch.accepts(self.searchQuery) { self.search() }
                }
                return
            }
            guard let places else { return }
            await MainActor.run {
                guard generation == self.indexGeneration else { return }
                self.searchIndexing = true
            }
            let scan = reader.placeScan(limit: MapSearch.maxIndexedPlaces)
            var failed = false
            do {
                try await places.beginReplace()
                while !Task.isCancelled {
                    let batch = scan.nextBatch(400) { Task.isCancelled }
                    if batch.isEmpty { break }
                    try await places.insertBatch(batch)
                }
                if Task.isCancelled {
                    try await places.abort()
                } else {
                    try await places.finish(path: url.path, bytes: bytes, modified: modified)
                }
            } catch {
                failed = true
                try? await places.abort()
            }
            await MainActor.run {
                guard generation == self.indexGeneration else { return }
                self.searchIndexing = false
                self.indexTask = nil
                self.indexKey = ""
                if !failed, !Task.isCancelled, MapSearch.accepts(self.searchQuery) { self.search() }
            }
        }
    }

    private func activityType(_ usage: UsageType) -> CLActivityType {
        switch usage {
        case .AIRCRAFT: return .airborne
        case .WATERCRAFT: return .otherNavigation
        case .FOUR_WHEELERS, .TWO_WHEELERS: return .automotiveNavigation
        case .BICYCLE, .RUNNER, .WALKING_HIKE, .PEDESTRIAN: return .fitness
        }
    }

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func sessionName(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "GTL \(formatter.string(from: date))"
    }

    private static func logEvent(_ event: GpsEvent) -> TrackLogEvent {
        TrackLogEvent(
            timestampMillis: event.timestamp,
            latitude: event.latitude,
            longitude: event.longitude,
            altitude: event.altitude,
            speedMps: event.speed,
            kind: EventKind(rawValue: event.eventKind) ?? .MOVE,
            tempCelsius: event.ambientTemperature,
            leanAngle: event.leanAngle,
            usageType: event.usageType,
            baroAltitude: event.baroAltitude,
            pressureHpa: event.pressureHpa
        )
    }
}

enum MarkerIcon {
    static let green = png(red: 46, green: 160, blue: 67)
    static let amber = png(red: 232, green: 168, blue: 56)
    static let red = png(red: 193, green: 59, blue: 46)

    private static func png(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        var data = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00
        ])
        let ihdrCRC = crc([0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00])
        data.append(contentsOf: ihdrCRC.bigEndianBytes)
        let raw: [UInt8] = [0x00, red, green, blue]
        let compressed = zlibStore(raw)
        var idat = Data([0x00, 0x00, 0x00, UInt8(compressed.count), 0x49, 0x44, 0x41, 0x54])
        idat.append(compressed)
        let idatCRC = crc([UInt8](idat.dropFirst(4)))
        data.append(idat)
        data.append(contentsOf: idatCRC.bigEndianBytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        return data
    }

    private static func zlibStore(_ bytes: [UInt8]) -> Data {
        var data = Data([0x78, 0x01, 0x01])
        let len = UInt16(bytes.count)
        data.append(UInt8(len & 0xff))
        data.append(UInt8(len >> 8))
        let nlen = ~len
        data.append(UInt8(nlen & 0xff))
        data.append(UInt8(nlen >> 8))
        data.append(contentsOf: bytes)
        data.append(contentsOf: adler32(bytes).bigEndianBytes)
        return data
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func crc(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
            }
        }
        return crc ^ 0xffffffff
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8(truncatingIfNeeded: self >> 24),
            UInt8(truncatingIfNeeded: self >> 16),
            UInt8(truncatingIfNeeded: self >> 8),
            UInt8(truncatingIfNeeded: self)
        ]
    }
}
