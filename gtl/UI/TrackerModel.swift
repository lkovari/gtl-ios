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

@MainActor
@Observable
final class TrackerModel {
    var settings: GtlSettings
    var logging = false
    var latitude: Double?
    var longitude: Double?
    var accuracy: Float?
    var altitude: Double?
    var speedMps: Float?
    var bearing: Float?
    var baroAltitude: Double?
    var pressureHpa: Float?
    var leanAngle: Float?
    var headingDegrees: Float?
    var headingAccuracy: Int?
    var declination: Float?
    var sessions: [TrackSession] = []
    var trackPoints: [GeoPoint] = []
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
    var searchQuery = ""
    var searchHits: [MapSearchHit] = []
    var searchIndexing = false
    var searchBusy = false
    var offlineFeatures: [MapFeature] = []
    private var offlineRaw: [MapFeature] = []
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
    var distanceTarget: GeoPoint?
    var layerEpoch = 0
    var zoomTicket = 0
    var zoomStep = 0
    var pendingShare: URL?
    var altimeterAvailable = false
    var poorGps = false
    var showErrorLog = false
    private var versionTaps: [Date] = []

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
    private var accel = (Float(0), Float(0), Float(0))
    private var gravity = (Float(0), Float(0), Float(1))
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

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
        wire()
        refreshMaps()
        scheduleIndex()
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

    var displayPoints: [GeoPoint] {
        guard trackVisible else { return [] }
        if settings.optimizationActive {
            return DouglasPeucker.simplify(trackPoints, toleranceMeters: DouglasPeucker.clampTolerance(settings.optimizationTolerance))
        }
        return trackPoints
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
        UIApplication.shared.isIdleTimerDisabled = logging && settings.keepScreenOnWhileLogging
        applyOfflineFilter()
    }

    func startLogging() {
        switch location.authorization {
        case .notDetermined:
            location.requestWhenInUse()
            status = "Precise location is required to start logging"
            return
        case .denied, .restricted:
            status = "Turn on GPS"
            return
        case .authorizedWhenInUse:
            location.requestAlways()
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
        guard location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse else {
            status = "Precise location is required to start logging"
            return
        }
        Task { await beginSession() }
    }

    func stopLogging() {
        let now = nowMillis()
        logging = false
        location.stopLogging()
        motion.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        status = "Idle"
        guard let sessionId else { return }
        let stop = GpsEvent(
            id: 0, sessionId: sessionId, timestamp: now, latitude: latitude ?? 0, longitude: longitude ?? 0,
            altitude: altitude, speed: 0, bearing: bearing ?? 0, accuracy: accuracy ?? 0, satellitesInFix: -1,
            ambientTemperature: nil, accelX: accel.0, accelY: accel.1, accelZ: accel.2, leanAngle: leanAngle,
            usageType: settings.usageType.rawValue, isPlacemark: true, eventKind: EventKind.STOP.rawValue,
            baroAltitude: baroAltitude, pressureHpa: pressureHpa
        )
        Task {
            do {
                if latitude != nil { try await database?.insert(stop) }
                try await database?.stopSession(id: sessionId, at: now)
            } catch {
                ErrorLogStore.record(action: "track.stop", error: error)
                status = "Logging stopped"
            }
            self.sessionId = nil
            await reloadSessions()
        }
    }

    func clearMapTrack() { mapCleared = true }

    func showSession(_ id: Int64) {
        selectedSessionId = id
        mapCleared = false
        tab = .map
        Task { await loadSession(id) }
    }

    func deleteSessions(_ ids: Set<Int64>) {
        Task {
            for id in ids {
                try? await database?.deleteSession(id: id)
            }
            if let selected = selectedSessionId, ids.contains(selected) {
                selectedSessionId = nil
                trackPoints = []
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
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gtltracklogs", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = sessionName(nowMillis())
            if kmz {
                let kml = KmlExporter.export(KmlDocument(name: stamp, trackColorAabbggrr: "ff0000ff", trackWidth: 6, tracks: tracks))
                let packed = KmzExporter.pack(kml: kml, files: [
                    "icons/play.png": MarkerIcon.green,
                    "icons/pause.png": MarkerIcon.amber,
                    "icons/stop.png": MarkerIcon.red
                ])
                let url = folder.appendingPathComponent("\(stamp).kmz")
                try? packed.write(to: url)
                pendingShare = url
            } else {
                let gpx = GpxExporter.export(GpxDocument(tracks: gpxTracks))
                let url = folder.appendingPathComponent("\(stamp).gpx")
                try? gpx.write(to: url, atomically: true, encoding: .utf8)
                pendingShare = url
            }
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
            status = "Precise location is required to start logging"
        }
    }

    func beginMapTap(latitude: Double, longitude: Double, x: CGFloat, y: CGFloat) {
        mapTapLatitude = latitude
        mapTapLongitude = longitude
        mapTapX = x
        mapTapY = y
        mapTapMenu = true
        mapTapCoordinate = false
    }

    func moveMapTapAnchor(x: CGFloat, y: CGFloat) {
        guard mapTapMenu || mapTapCoordinate else { return }
        mapTapX = x
        mapTapY = y
    }

    func chooseTapDistance() {
        guard let latitude = mapTapLatitude, let longitude = mapTapLongitude else { return }
        distanceTarget = GeoPoint(latitude: latitude, longitude: longitude)
        mapTapMenu = false
    }

    func chooseTapCoordinate() {
        guard mapTapLatitude != nil, mapTapLongitude != nil else { return }
        mapTapMenu = false
        mapTapCoordinate = true
    }

    func closeMapTap() {
        mapTapMenu = false
        mapTapCoordinate = false
    }

    func clearDistance() {
        distanceTarget = nil
    }

    private func showCurrentPosition(_ latitude: Double, _ longitude: Double) {
        target = GeoPoint(latitude: latitude, longitude: longitude)
        focusZoom = 16
        focusToken += 1
        locateToken += 1
    }

    func refreshOffline(bounds: LatLonBounds, zoom: Int) {
        guard effectiveOffline, let url = try? MapPaths.mapFile(id: settings.selectedMapId), OsmMapFile.isReadable(url),
              let header = MapsforgeReader.header(of: url) else {
            offlineRaw = []
            offlineFeatures = []
            return
        }
        let minLat = max(bounds.minLatitude, header.bounds.minLatitude)
        let maxLat = min(bounds.maxLatitude, header.bounds.maxLatitude)
        let minLon = max(bounds.minLongitude, header.bounds.minLongitude)
        let maxLon = min(bounds.maxLongitude, header.bounds.maxLongitude)
        guard minLat < maxLat, minLon < maxLon else { return }
        let clipped = LatLonBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
        offlineGeneration += 1
        let generation = offlineGeneration
        Task.detached {
            let raw = MapsforgeReader.features(url: url, bounds: clipped, zoom: zoom, limit: 9000)
            await MainActor.run {
                guard self.offlineGeneration == generation else { return }
                self.offlineRaw = raw
                self.applyOfflineFilter()
            }
        }
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
            var candidates = MapsforgeReader.searchCandidates(offlineRaw)
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
        offlineFeatures = offlineRaw
        layerEpoch += 1
    }

    func bumpZoom(_ step: Int) {
        zoomStep = step
        zoomTicket += 1
    }

    private func applyOfflineFilter() {
        offlineFeatures = effectiveOffline ? offlineRaw : []
        layerEpoch += 1
    }

    func useMap(_ id: String) {
        settings.selectedMapId = id
        settings.useOfflineMap = true
        store.save(settings)
        refreshMaps()
        scheduleIndex()
    }

    func stopUsingOffline() {
        settings.useOfflineMap = false
        store.save(settings)
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
    }

    func download(_ region: OsmRegion) { downloader.downloadOsm(region) }
    func downloadTuhu() { downloader.downloadTuhu() }

    func onTabChange() {
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
            self.headingDegrees = Float(heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading)
            self.declination = Float(heading.trueHeading - heading.magneticHeading)
            self.headingAccuracy = Int(heading.headingAccuracy.rounded())
        }
        location.onAuthorization = { [weak self] _ in
            guard let self else { return }
            self.status = self.logging ? "Logging" : "Idle"
            self.onTabChange()
        }
        motion.onMotion = { [weak self] data in
            guard let self else { return }
            self.gravity = (Float(data.gravity.x), Float(data.gravity.y), Float(data.gravity.z))
            self.accel = (Float(data.userAcceleration.x), Float(data.userAcceleration.y), Float(data.userAcceleration.z))
            self.leanAngle = BikeLeanAngle.fromGravity(ax: self.gravity.0, ay: self.gravity.1, az: self.gravity.2)
        }
        motion.onPressure = { [weak self] data in
            guard let self else { return }
            let kPa = data.pressure.doubleValue
            self.pressureHpa = Float(kPa * 10)
            self.baroAltitude = BaroAltitude.displayedMeters(
                pressureHpa: self.pressureHpa,
                storedBaro: nil,
                qnhHpa: self.settings.qnhHpa,
                offsetHpa: self.settings.baroPressureOffsetHpa,
                gpsMeters: self.altitude
            )
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
            mapCleared = false
            selectedSessionId = nil
            startedAt = now
            lastAccepted = nil
            lastAcceptMillis = nil
            baroCalibrated = false
            samples = []
            trackPoints = []
            cloud.clear()
            status = "Logging"
            location.startLogging(activity: activityType(settings.usageType))
            if tab == .compass || tab == .map { location.startHeading() }
            motion.startLoggingSensors()
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOnWhileLogging
        } catch {
            ErrorLogStore.record(action: "track.insert", error: error)
            status = "Logging stopped"
        }
    }

    private func ingest(_ location: RecordedFix) {
        let age = Date().timeIntervalSince(location.timestamp)
        let locating = centerOnNextFix
        guard age <= 10 || (locating && age <= 300) else { return }
        let hasAccuracy = location.horizontalAccuracy >= 0
        guard FixAcceptance.hasUsableAccuracy(hasAccuracy, Float(location.horizontalAccuracy)) else { return }
        latitude = location.latitude
        longitude = location.longitude
        accuracy = Float(location.horizontalAccuracy)
        if location.verticalAccuracy >= 0 {
            altitude = GpsAltitude.pick(
                gnssMsl: location.altitude,
                fusedMsl: nil,
                gnssEllipsoid: location.ellipsoidalAltitude,
                fusedEllipsoid: nil
            )
        }
        if location.speed >= 0 { lastSpeed = Float(location.speed); speedMps = lastSpeed }
        if location.course >= 0 { bearing = Float(location.course) }
        cloud.observe(
            FixCloudSample(
                timeMillis: nowMillis(),
                latitude: location.latitude,
                longitude: location.longitude,
                accuracyMeters: Float(location.horizontalAccuracy),
                speedMps: speedMps ?? 0
            ),
            pauseSpeedMps: settings.usageType.pauseSpeedMps()
        )
        fixCloud = cloud.snapshot()
        if centerOnNextFix {
            centerOnNextFix = false
            showCurrentPosition(location.latitude, location.longitude)
        }
        guard logging, let sessionId else {
            status = "Idle"
            return
        }
        var fix = TrackFix(
            timestampMillis: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            latitude: location.latitude,
            longitude: location.longitude,
            altitude: altitude ?? 0,
            speedMps: speedMps ?? lastSpeed,
            bearing: bearing ?? 0,
            accuracyMeters: Float(location.horizontalAccuracy),
            satellitesInFix: -1
        )
        if let altitude, BaroAltitude.autoCalibrateEligible(
            pressureHpa: pressureHpa,
            gpsAltitudeMeters: altitude,
            alreadyCalibratedThisSession: baroCalibrated,
            enabled: settings.autoCalibrateBaroEnabled,
            previousGpsAltitudeMeters: previousGpsAltitude
        ), let pressureHpa {
            settings.baroPressureOffsetHpa = BaroAltitude.offsetHpa(pressureHpa: pressureHpa, gpsMeters: altitude, qnhHpa: settings.qnhHpa)
            baroCalibrated = true
            store.save(settings)
        }
        previousGpsAltitude = altitude
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
        let point = GeoPoint(latitude: fix.latitude, longitude: fix.longitude, altitude: altitude)
        trackPoints.append(point)
        samples.append(TrackSample(
            timestampMillis: fix.timestampMillis, latitude: fix.latitude, longitude: fix.longitude,
            altitude: altitude, speedMps: fix.speedMps, bearing: fix.bearing, ambientTemperature: nil, eventKind: kind
        ))
        stats = TrackStatsCalculator.compute(samples)
        elevation = ElevationSeries.downsample(ElevationSeries.fromPoints(trackPoints.map {
            ElevationPoint(latitude: $0.latitude, longitude: $0.longitude, gpsAltitude: $0.altitude, baroAltitude: baroAltitude)
        }))
        let event = GpsEvent(
            id: 0, sessionId: sessionId, timestamp: fix.timestampMillis, latitude: fix.latitude, longitude: fix.longitude,
            altitude: altitude, speed: fix.speedMps, bearing: fix.bearing, accuracy: fix.accuracyMeters, satellitesInFix: -1,
            ambientTemperature: nil, accelX: accel.0, accelY: accel.1, accelZ: accel.2, leanAngle: leanAngle,
            usageType: settings.usageType.rawValue, isPlacemark: kind != .MOVE, eventKind: kind.rawValue,
            baroAltitude: baroAltitude, pressureHpa: pressureHpa
        )
        Task {
            do { try await database?.insert(event) }
            catch { ErrorLogStore.record(action: "track.insert", error: error) }
        }
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
        sessions = (try? await database?.sessions()) ?? []
    }

    private func loadSession(_ id: Int64) async {
        let events = (try? await database?.events(sessionId: id)) ?? []
        trackPoints = events.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) }
        elevation = ElevationSeries.downsample(ElevationSeries.fromPoints(events.map {
            ElevationPoint(latitude: $0.latitude, longitude: $0.longitude, gpsAltitude: $0.altitude, baroAltitude: $0.baroAltitude)
        }))
        if let session = sessions.first(where: { $0.id == id }), let usage = UsageType(rawValue: session.usageType) {
            settings.usageType = usage
        }
    }

    private func scheduleIndex() {
        indexTask?.cancel()
        guard effectiveOffline, let url = try? MapPaths.mapFile(id: settings.selectedMapId), OsmMapFile.isReadable(url) else {
            searchIndexing = false
            return
        }
        searchIndexing = true
        let places = places
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = Int64((((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970) ?? 0) * 1000)
        indexTask = Task.detached(priority: .utility) { [places] in
            if await places?.isReady(path: url.path, bytes: bytes, modified: modified) == true {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.searchIndexing = false
                    if MapSearch.accepts(self.searchQuery) { self.search() }
                }
                return
            }
            let rows = MapsforgeReader.namedPlaces(url: url, limit: MapSearch.maxIndexedPlaces) { Task.isCancelled }
            guard !Task.isCancelled else { return }
            try? await places?.replaceAll(path: url.path, bytes: bytes, modified: modified, rows: rows)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.searchIndexing = false
                if MapSearch.accepts(self.searchQuery) { self.search() }
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
        [UInt8(self >> 24), UInt8(self >> 16), UInt8(self >> 8), UInt8(self)]
    }
}
