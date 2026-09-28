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
    var altitude: Double?
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
    var trackPoints: [TrackVertex] = []
    var speedRuns: [SpeedRun] = []
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
    private var accel = (Float(0), Float(0), Float(0))
    private var gravity = (Float(0), Float(0), Float(1))
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var offlineTask: Task<Void, Never>?
    private var offlineCancel = OfflineCancel()
    private var writeChain: Task<Void, Never>?
    private var loadedBounds: LatLonBounds?
    private var loadedZoom = -1

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
        displayVertices.map(\.point)
    }

    var liveTail: SpeedRun? {
        guard logging, let last = trackPoints.last, let latitude, let longitude else { return nil }
        guard FixAcceptance.haversineMeters(last.latitude, last.longitude, latitude, longitude) > 3 else { return nil }
        return SpeedRun(
            bin: SpeedColorScale.bin(speedMps: speedMps, usage: settings.usageType),
            points: [last.point, GeoPoint(latitude: latitude, longitude: longitude, altitude: nil)]
        )
    }

    private var displayVertices: [TrackVertex] {
        guard trackVisible else { return [] }
        return TrackLine.withLiveEnd(
            simplifiedTrack(),
            logging: logging,
            latitude: latitude,
            longitude: longitude,
            speedMps: speedMps
        )
    }

    private func simplifiedTrack() -> [TrackVertex] {
        guard trackVisible else { return [] }
        if settings.optimizationActive {
            return DouglasPeucker.simplify(trackPoints, toleranceMeters: DouglasPeucker.clampTolerance(settings.optimizationTolerance))
        }
        return trackPoints
    }

    private func rebuildSpeedRuns() {
        speedRuns = SpeedColorScale.runs(points: simplifiedTrack(), usage: settings.usageType)
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
        if let loadedBounds, zoom == loadedZoom, Self.viewInside(loadedBounds, clipped) { return }
        offlineCancel.cancelled = true
        let flag = OfflineCancel()
        offlineCancel = flag
        offlineTask?.cancel()
        offlineGeneration += 1
        let generation = offlineGeneration
        let wide = Self.expand(clipped, fraction: zoom <= 11 ? 0.05 : 0.3)
        let featureLimit = zoom <= 11 ? 2400 : 6000
        let poiLimit = zoom <= 11 ? 6 : 28
        offlineTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, generation == self.offlineGeneration else { return }
            let raw = await Task.detached(priority: .userInitiated) {
                MapsforgeReader.features(
                    url: url,
                    bounds: wide,
                    zoom: zoom,
                    limit: featureLimit,
                    poiLimit: poiLimit,
                    isCancelled: { flag.cancelled }
                )
            }.value
            guard !Task.isCancelled, generation == self.offlineGeneration else { return }
            self.offlineRaw = raw
            self.loadedBounds = wide
            self.loadedZoom = zoom
            self.applyOfflineFilter()
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
        loadedBounds = nil
        loadedZoom = -1
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
            self.compassMagnetic = Float(heading.magneticHeading)
            self.compassShift = heading.trueHeading >= 0 ? Float(heading.trueHeading - heading.magneticHeading) : nil
            self.refreshTravelHeading()
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
        refreshTravelHeading()
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
        trackPoints.append(TrackVertex(latitude: fix.latitude, longitude: fix.longitude, altitude: altitude, speedMps: fix.speedMps))
        rebuildSpeedRuns()
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

    private static func expand(_ bounds: LatLonBounds, fraction: Double) -> LatLonBounds {
        let lat = (bounds.maxLatitude - bounds.minLatitude) * fraction
        let lon = (bounds.maxLongitude - bounds.minLongitude) * fraction
        return LatLonBounds(
            minLatitude: bounds.minLatitude - lat,
            minLongitude: bounds.minLongitude - lon,
            maxLatitude: bounds.maxLatitude + lat,
            maxLongitude: bounds.maxLongitude + lon
        )
    }

    private static func viewInside(_ loaded: LatLonBounds, _ view: LatLonBounds) -> Bool {
        let latMargin = max(0.002, (loaded.maxLatitude - loaded.minLatitude) * 0.12)
        let lonMargin = max(0.002, (loaded.maxLongitude - loaded.minLongitude) * 0.12)
        return view.minLatitude >= loaded.minLatitude + latMargin
            && view.maxLatitude <= loaded.maxLatitude - latMargin
            && view.minLongitude >= loaded.minLongitude + lonMargin
            && view.maxLongitude <= loaded.maxLongitude - lonMargin
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
        sessions = (try? await database?.sessions()) ?? []
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
            courseDegrees: bearing,
            speedMps: speedMps,
            magneticHeading: compassMagnetic,
            declinationDegrees: compassShift,
            compassAccuracy: headingAccuracy ?? -1,
            lastGoodDegrees: lastTravelDegrees
        ) else { return }
        travelDegrees = Double(aim.degrees)
        if !aim.dimmed { lastTravelDegrees = aim.degrees }
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
        [
            UInt8(truncatingIfNeeded: self >> 24),
            UInt8(truncatingIfNeeded: self >> 16),
            UInt8(truncatingIfNeeded: self >> 8),
            UInt8(truncatingIfNeeded: self)
        ]
    }
}
