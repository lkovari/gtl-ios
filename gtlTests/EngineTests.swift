import CoreLocation
import XCTest
@testable import gtl

final class EngineTests: XCTestCase {
    func testDouglasPeuckerKeepsEndsAndDropsColinear() {
        let points = [
            GeoPoint(latitude: 47, longitude: 19),
            GeoPoint(latitude: 47.00001, longitude: 19.00001),
            GeoPoint(latitude: 47.01, longitude: 19.01)
        ]
        let simplified = DouglasPeucker.simplify(points, toleranceMeters: 50)
        XCTAssertEqual(simplified.count, 2)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
    }

    func testDouglasPeuckerKeepsCorner() {
        let points = [
            GeoPoint(latitude: 47, longitude: 19),
            GeoPoint(latitude: 47.02, longitude: 19),
            GeoPoint(latitude: 47.02, longitude: 19.03)
        ]
        XCTAssertEqual(DouglasPeucker.simplify(points, toleranceMeters: 20).count, 3)
    }

    func testToleranceClamp() {
        XCTAssertEqual(DouglasPeucker.clampTolerance(19.5), 20)
        XCTAssertEqual(DouglasPeucker.clampTolerance(0), 1)
        XCTAssertEqual(DouglasPeucker.clampTolerance(100), 20)
        XCTAssertEqual(DouglasPeucker.clampTolerance(19.4), 19)
    }

    func testSpacingBands() {
        XCTAssertEqual(SpeedAdaptiveSpacing.spacingMeters(0, inCurve: false), 2)
        XCTAssertEqual(SpeedAdaptiveSpacing.spacingMeters(10 / 3.6, inCurve: false), 10)
        XCTAssertEqual(SpeedAdaptiveSpacing.spacingMeters(10 / 3.6, inCurve: true), 5)
        XCTAssertEqual(SpeedAdaptiveSpacing.spacingMeters(2, inCurve: false, usage: .RUNNER), 5)
    }

    func testFixAcceptanceRejectsBadAccuracyAndAcceptsFirst() {
        let filter = FixFilter(minDistanceMeters: 2, minTimeMillis: 500, minAccuracyMeters: 30, minSatellites: 4)
        let bad = fix(t: 1, lat: 47, lon: 19, accuracy: 40, sats: 8)
        XCTAssertFalse(FixAcceptance.shouldAccept(previous: nil, current: bad, filter: filter))
        let good = fix(t: 1, lat: 47, lon: 19, accuracy: 5, sats: 8)
        XCTAssertTrue(FixAcceptance.shouldAccept(previous: nil, current: good, filter: filter))
        let lowSats = fix(t: 2, lat: 47.001, lon: 19, accuracy: 5, sats: 2)
        XCTAssertFalse(FixAcceptance.shouldAccept(previous: good, current: lowSats, filter: filter))
        let unknownSats = fix(t: 2, lat: 47.01, lon: 19, accuracy: 5, sats: -1)
        XCTAssertTrue(FixAcceptance.shouldAccept(previous: good, current: unknownSats, filter: filter, density: .SMART, usage: .FOUR_WHEELERS))
    }

    func testLoggingKeepsALateFixThatLiveModeDrops() {
        let started: Int64 = 1_000_000
        let late = started + 41_000
        XCTAssertTrue(FixAcceptance.keepFix(
            logging: true,
            ageSeconds: 41,
            locating: false,
            fixMillis: late,
            startedAtMillis: started,
            lastAcceptMillis: started + 5_000
        ))
        XCTAssertFalse(FixAcceptance.keepFix(
            logging: false,
            ageSeconds: 41,
            locating: false,
            fixMillis: late,
            startedAtMillis: nil,
            lastAcceptMillis: nil
        ))
        XCTAssertFalse(FixAcceptance.keepFix(
            logging: true,
            ageSeconds: 30,
            locating: false,
            fixMillis: started - 60_000,
            startedAtMillis: started,
            lastAcceptMillis: nil
        ))
        XCTAssertFalse(FixAcceptance.keepFix(
            logging: true,
            ageSeconds: 5,
            locating: false,
            fixMillis: started + 4_000,
            startedAtMillis: started,
            lastAcceptMillis: started + 5_000
        ))
    }

    func testBackgroundLoggingRequiresRecordingAndAlways() {
        XCTAssertFalse(BackgroundLogging.isActive(recording: false, authorization: .authorizedAlways))
        XCTAssertFalse(BackgroundLogging.isActive(recording: true, authorization: .authorizedWhenInUse))
        XCTAssertFalse(BackgroundLogging.isActive(recording: true, authorization: .denied))
        XCTAssertTrue(BackgroundLogging.isActive(recording: true, authorization: .authorizedAlways))
    }

    func testUsageDefaults() {
        XCTAssertEqual(UsageType.AIRCRAFT.defaultMeasurementSystem(), .ICAO)
        XCTAssertEqual(UsageType.RUNNER.pauseSpeedMps(), 0.25)
        XCTAssertEqual(UsageType.FOUR_WHEELERS.pauseSpeedMps(), 0.4)
        XCTAssertFalse(UsageType.RUNNER.defaultSmoothing().trackSmoothingEnabled)
        XCTAssertTrue(UsageType.TWO_WHEELERS.defaultSmoothing().trackSmoothingEnabled)
        XCTAssertEqual(UsageType.BICYCLE.kmlLabel(), "Bicycle")
        XCTAssertTrue(OsmRenderOptions.cyclewaysForUsage(.BICYCLE))
        XCTAssertFalse(OsmRenderOptions.cyclewaysForUsage(.FOUR_WHEELERS))
    }

    func testSmoothingMultiplier() {
        XCTAssertEqual(SmoothingStrength.processNoiseMultiplier(0), 4)
        XCTAssertEqual(SmoothingStrength.processNoiseMultiplier(1), 0.25, accuracy: 0.0001)
    }

    func testBaroAltitude() {
        let meters = BaroAltitude.metersFromPressureHpa(1013.25)
        XCTAssertNotNil(meters)
        XCTAssertEqual(meters ?? 0, 0, accuracy: 1)
        XCTAssertEqual(BaroAltitude.clampQnh(800), 900)
        XCTAssertFalse(BaroAltitude.isPlausiblePressureHpa(10))
        XCTAssertTrue(GpsAltitude.isPlausible(100))
        XCTAssertFalse(GpsAltitude.isPlausible(-500))
        XCTAssertEqual(GpsAltitude.pick(gnssMsl: nil, fusedMsl: 120, gnssEllipsoid: 140, fusedEllipsoid: nil), 120)
    }

    func testLeanAndCompass() {
        XCTAssertEqual(BikeLeanAngle.fromGravity(ax: 0, ay: 0, az: 1), 0, accuracy: 0.01)
        let display = CompassHeading.display(magneticDegrees: 350, wantTrue: true, declinationDegrees: 20)
        XCTAssertEqual(display.degrees, 10, accuracy: 0.01)
        XCTAssertTrue(display.trueNorth)
        XCTAssertTrue(CompassHeading.display(magneticDegrees: 10, wantTrue: true, declinationDegrees: nil).missingFix)
        XCTAssertFalse(CompassHeading.needsFigureEight(0))
        XCTAssertFalse(CompassHeading.needsFigureEight(10))
        XCTAssertTrue(CompassHeading.needsFigureEight(-1))
        XCTAssertTrue(CompassHeading.needsFigureEight(40))
    }

    func testHudAndTrackVisibility() {
        XCTAssertEqual(MapHudVisibility.mode(logging: true, selectedSessionId: 1, hasFix: true), .full)
        XCTAssertEqual(MapHudVisibility.mode(logging: false, selectedSessionId: 1, hasFix: true), .hidden)
        XCTAssertEqual(MapHudVisibility.mode(logging: false, selectedSessionId: nil, hasFix: true), .compact)
        XCTAssertTrue(MapTrackVisibility.visible(logging: true, showLastTrackOnMap: false, selectedSessionId: nil, mapCleared: true))
        XCTAssertFalse(MapTrackVisibility.visible(logging: false, showLastTrackOnMap: true, selectedSessionId: nil, mapCleared: true))
        XCTAssertEqual(MapCameraMode.of(logging: true, keepWholeTrack: false, viewingSaved: false), .followLive)
        let live = TrackLine.withLiveEnd(
            [TrackVertex(latitude: 47, longitude: 19, altitude: nil, speedMps: 1)],
            logging: true,
            latitude: 47.01,
            longitude: 19,
            speedMps: 2
        )
        XCTAssertEqual(live.count, 2)
        XCTAssertEqual(live.last?.latitude ?? 0, 47.01, accuracy: 0.0001)
        XCTAssertEqual(live.last?.speedMps ?? 0, 2, accuracy: 0.001)
        XCTAssertTrue(GpsQualityNotice.isPoor(20_000))
    }

    func testGpxAndMarkers() {
        let events = [
            TrackLogEvent(timestampMillis: 0, latitude: 47, longitude: 19, altitude: 100, speedMps: 1, kind: .START),
            TrackLogEvent(timestampMillis: 1000, latitude: 47.01, longitude: 19.01, altitude: 110, speedMps: 3, kind: .MOVE),
            TrackLogEvent(timestampMillis: 2000, latitude: 47.02, longitude: 19.02, altitude: 120, speedMps: 0, kind: .STOP)
        ]
        let markers = TrackLogExport.markers(events)
        XCTAssertEqual(markers.map(\.kind), [.START, .STOP])
        let gpx = GpxExporter.export(GpxDocument(tracks: [
            GpxTrack(name: "GTL test", points: [GpxTrackPoint(point: events[0].point(), timestampMillis: 0)], waypoints: [])
        ]))
        XCTAssertTrue(gpx.contains("creator=\"GTL\""))
        XCTAssertTrue(gpx.contains("1970-01-01T00:00:00Z"))
        let kml = KmlExporter.export(KmlDocument(name: "GTL", trackColorAabbggrr: "ff0000ff", trackWidth: 6, tracks: [
            KmlTrackBuilder.build(name: "GTL", events: events, system: .METRIC)
        ]))
        XCTAssertTrue(kml.contains("<gx:Track>"))
        XCTAssertTrue(kml.contains("icons/play.png"))
        XCTAssertTrue(kml.contains("<altitudeMode>absolute</altitudeMode>"))
        XCTAssertTrue(kml.contains("19,47,100"))
        XCTAssertTrue(kml.contains("19.01,47.01,110"))
        XCTAssertTrue(kml.contains("<gx:coord>19 47 100</gx:coord>"))
        XCTAssertFalse(kml.contains("<tessellate>"))
        XCTAssertTrue(kml.contains("<altitudeMode>clampToGround</altitudeMode>"))
        let flat = KmlExporter.export(KmlDocument(name: "GTL", trackColorAabbggrr: "ff0000ff", trackWidth: 6, tracks: [
            KmlTrackBuilder.build(name: "GTL", events: [
                TrackLogEvent(timestampMillis: 0, latitude: 47, longitude: 19, altitude: nil, speedMps: 1, kind: .START),
                TrackLogEvent(timestampMillis: 1000, latitude: 47.01, longitude: 19.01, altitude: nil, speedMps: 1, kind: .MOVE)
            ], system: .METRIC)
        ]))
        XCTAssertTrue(flat.contains("<altitudeMode>clampToGround</altitudeMode>"))
        XCTAssertFalse(flat.contains("<altitudeMode>absolute</altitudeMode>"))
        XCTAssertTrue(flat.contains("<tessellate>1</tessellate>"))
        let kmz = KmzExporter.pack(kml: kml, files: ["icons/play.png": Data([1, 2, 3])])
        XCTAssertEqual(kmz.prefix(2), Data([0x50, 0x4b]))
    }

    func testUnitsAndSearch() {
        XCTAssertEqual(Units.formatDuration(3661000), "01:01:01")
        XCTAssertEqual(Units.hudSpeedUnit(.ICAO), "kt")
        XCTAssertEqual(MapSearch.fold("Őrség"), "orseg")
        XCTAssertEqual(MapSearch.fold("Magyar-hegy"), "magyarhegy")
        XCTAssertEqual(MapSearch.fold("Hármashatárhegy"), "harmashatarhegy")
        XCTAssertEqual(MapSearch.ftsMatch("Magyar-hegy"), "\"magyarhegy\"*")
        let hill = MapSearch.rank(
            rawQuery: "Magyar-hegy",
            candidates: [MapSearchCandidate(name: "Magyar-hegy", nameFold: MapSearch.fold("Magyar-hegy"), kind: .Peak, latitude: 47.55, longitude: 18.96)],
            originLatitude: 47.5,
            originLongitude: 19.0
        )
        XCTAssertEqual(hill.first?.name, "Magyar-hegy")
        XCTAssertTrue(MapSearch.accepts("Bud"))
        XCTAssertFalse(MapSearch.accepts("Bu"))
        let record = MapSearch.record(tags: ["place": "city", "name": "Budapest"])
        XCTAssertEqual(record?.kind, .City)
        XCTAssertEqual(IndexResume.action(nil, nowMillis: 0), .resume)
        XCTAssertEqual(IndexResume.action(IndexProgress(done: true, truncated: false, nextAttemptAtMillis: 0), nowMillis: 1), .ready)
    }

    func testMapFileMagicAndOfflineRules() {
        XCTAssertFalse(OsmOfflineAvailability.effectiveUseOffline(wantOffline: true, hasDownloadedMap: false))
        XCTAssertTrue(OfflineMapUse.isInUse(useOffline: true, selectedPath: "a", candidatePath: "a"))
        XCTAssertTrue(OsmMapLocale.countryMatches(regionCountryCode: "hu", localeCountry: "HU"))
        XCTAssertEqual(MapFitZoom.clamp(99), 20)
        XCTAssertNil(TrackEndpoints.end([GeoPoint(latitude: 1, longitude: 2)], logging: false))
        XCTAssertEqual(TapReadout.formatCoordinate(47, 19), "47.000000, 19.000000")
        XCTAssertEqual(TapReadout.formatStraightLine(1000, .METRIC, prefix: "D"), "D1.0km")
        XCTAssertEqual(TapReadout.formatStraightLine(1609.344, .IMPERIAL, prefix: "D"), "D1.0mi")
        XCTAssertEqual(TapReadout.formatStraightLine(1852, .ICAO, prefix: "D"), "D1.0NM")
        XCTAssertEqual(TapReadout.formatStraightLine(20_000, .METRIC, prefix: "D"), "D20km")
        XCTAssertEqual(
            MapAddressLookup.format(
                houseNumber: "12",
                street: "Kossuth Lajos utca",
                locality: "Budapest",
                postalCode: "1053",
                country: "Magyarország",
                hungarian: true
            ),
            "Kossuth Lajos utca 12\n1053 Budapest\nMagyarország"
        )
        XCTAssertEqual(
            MapAddressLookup.format(
                houseNumber: "12",
                street: "Kossuth Lajos utca",
                locality: "Budapest",
                postalCode: "1053",
                country: "Hungary",
                hungarian: false
            ),
            "12 Kossuth Lajos utca\nBudapest 1053\nHungary"
        )
        XCTAssertEqual(
            MapAddressLookup.format(
                houseNumber: nil,
                street: "  Fő út  ",
                locality: nil,
                postalCode: " ",
                country: nil,
                hungarian: true
            ),
            "Fő út"
        )
        XCTAssertEqual(
            MapAddressLookup.format(
                houseNumber: nil,
                street: nil,
                locality: "Budapest",
                postalCode: nil,
                country: nil,
                hungarian: false
            ),
            "Budapest"
        )
        XCTAssertNil(
            MapAddressLookup.format(
                houseNumber: " ",
                street: nil,
                locality: "",
                postalCode: nil,
                country: "\n",
                hungarian: false
            )
        )
    }

    func testFollowCameraTravelAndSpeed() {
        let aimed = FollowCamera.pose(
            logging: true,
            keepWholeTrack: false,
            headingUp: true,
            travelDegrees: 90,
            storedPitch: FollowCamera.defaultPitch,
            previousHeading: 0,
            movedMeters: 10
        )
        XCTAssertEqual(aimed?.heading ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(aimed?.pitch ?? 0, 52, accuracy: 0.001)
        XCTAssertEqual(aimed?.recenter, true)
        XCTAssertEqual(aimed?.updateAim, true)
        let held = FollowCamera.pose(
            logging: true,
            keepWholeTrack: false,
            headingUp: true,
            travelDegrees: 90,
            storedPitch: 30,
            previousHeading: 90,
            movedMeters: 3
        )
        XCTAssertEqual(held?.pitch ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(held?.recenter, false)
        XCTAssertEqual(held?.updateAim, false)
        XCTAssertEqual(FollowCamera.clampPitch(80), 65, accuracy: 0.001)
        let fitted = FollowCamera.pose(
            logging: true,
            keepWholeTrack: true,
            headingUp: true,
            travelDegrees: 90,
            storedPitch: 40,
            previousHeading: 0,
            movedMeters: 1
        )
        XCTAssertEqual(fitted?.heading ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(fitted?.pitch ?? -1, 0, accuracy: 0.001)
        let turned = FollowCamera.pose(
            logging: true,
            keepWholeTrack: false,
            headingUp: true,
            travelDegrees: 5,
            storedPitch: 52,
            previousHeading: 0,
            movedMeters: 1
        )
        XCTAssertEqual(turned?.recenter, false)
        XCTAssertEqual(turned?.updateAim, true)
        XCTAssertEqual(turned?.heading ?? 0, 5, accuracy: 0.001)
        XCTAssertNil(FollowCamera.pose(
            logging: false,
            keepWholeTrack: false,
            headingUp: true,
            travelDegrees: 10,
            storedPitch: 52,
            previousHeading: 0,
            movedMeters: 20
        ))
        let course = TravelHeading.resolve(
            courseDegrees: 40,
            speedMps: 2,
            magneticHeading: 10,
            declinationDegrees: 3,
            compassAccuracy: 5,
            lastGoodDegrees: 1
        )
        XCTAssertEqual(course?.degrees ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(course?.dimmed, false)
        let compass = TravelHeading.resolve(
            courseDegrees: 40,
            speedMps: 0.2,
            magneticHeading: 10,
            declinationDegrees: 3,
            compassAccuracy: 5,
            lastGoodDegrees: 1
        )
        XCTAssertEqual(compass?.degrees ?? 0, 13, accuracy: 0.001)
        let weak = TravelHeading.resolve(
            courseDegrees: nil,
            speedMps: 0,
            magneticHeading: 80,
            declinationDegrees: 2,
            compassAccuracy: 40,
            lastGoodDegrees: 15
        )
        XCTAssertEqual(weak?.degrees ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(weak?.dimmed, true)
        let slow = TrackVertex(latitude: 47, longitude: 19, altitude: nil, speedMps: nil)
        let mid = TrackVertex(latitude: 47.001, longitude: 19, altitude: nil, speedMps: 0.5)
        let fast = TrackVertex(latitude: 47.002, longitude: 19, altitude: nil, speedMps: 5)
        let runs = SpeedColorScale.runs(points: [slow, mid, fast], usage: .RUNNER)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].bin, 0)
        XCTAssertEqual(runs[1].bin, 5)
        XCTAssertEqual(runs[0].points.last?.latitude ?? 0, runs[1].points.first?.latitude ?? 1, accuracy: 0.00001)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: nil, usage: .BICYCLE), 0)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 6, usage: .BICYCLE), 2)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(49) / Float(3.6), usage: .BICYCLE), 4)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(50) / Float(3.6), usage: .BICYCLE), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 14, usage: .FOUR_WHEELERS), 2)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(129) / Float(3.6), usage: .FOUR_WHEELERS), 4)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(130) / Float(3.6), usage: .TWO_WHEELERS), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(200) / Float(3.6), usage: .FOUR_WHEELERS), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 50, usage: .AIRCRAFT), 1)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(599) / Float(3.6), usage: .AIRCRAFT), 4)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(600) / Float(3.6), usage: .AIRCRAFT), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: Float(700) / Float(3.6), usage: .AIRCRAFT), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 3.5, usage: .RUNNER), 4)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 4, usage: .RUNNER), 5)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 5, usage: .WALKING_HIKE), 4)
        XCTAssertEqual(SpeedColorScale.bin(speedMps: 5, usage: .WATERCRAFT), 2)
        var alternating: [TrackVertex] = []
        for index in 0..<302 {
            alternating.append(TrackVertex(
                latitude: 47 + Double(index) * 0.0001,
                longitude: 19,
                altitude: nil,
                speedMps: index % 2 == 0 ? 0.2 : 5
            ))
        }
        XCTAssertLessThanOrEqual(SpeedColorScale.runs(points: alternating, usage: .RUNNER).count, SpeedColorScale.maxRuns)
        XCTAssertEqual(RouteTransport.forUsage(.WALKING_HIKE), .walking)
        XCTAssertEqual(RouteTransport.forUsage(.RUNNER), .walking)
        XCTAssertEqual(RouteTransport.forUsage(.BICYCLE), .cycling)
        XCTAssertEqual(RouteTransport.forUsage(.FOUR_WHEELERS), .automobile)
        XCTAssertEqual(RouteTransport.forUsage(.TWO_WHEELERS), .automobile)
        XCTAssertNil(RouteTransport.forUsage(.AIRCRAFT))
        XCTAssertNil(RouteTransport.forUsage(.WATERCRAFT))
    }

    func testKalmanStaysNearMeasurement() {
        let filter = KalmanTrackFilter()
        var current = fix(t: 0, lat: 47, lon: 19, accuracy: 5, sats: 8)
        var output = filter.observe(current, usage: .FOUR_WHEELERS, strength: .MEDIUM, stationaryLock: true)
        XCTAssertEqual(output.latitude, 47, accuracy: 0.0001)
        current = fix(t: 1000, lat: 47.0001, lon: 19.0001, accuracy: 5, sats: 8)
        current.speedMps = 5
        current.bearing = 45
        output = filter.observe(current, usage: .FOUR_WHEELERS, strength: .MEDIUM, stationaryLock: true)
        XCTAssertEqual(output.latitude, 47.0001, accuracy: 0.01)
    }

    func testAndorraMapDecodesWays() throws {
        let url = URL(fileURLWithPath: "/tmp/andorra.map")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        guard let header = MapsforgeReader.header(of: url) else {
            XCTFail("header")
            return
        }
        let span = 0.04
        let bounds = LatLonBounds(
            minLatitude: header.startLatitude - span,
            minLongitude: header.startLongitude - span,
            maxLatitude: header.startLatitude + span,
            maxLongitude: header.startLongitude + span
        )
        let features = MapsforgeReader.features(url: url, bounds: bounds, zoom: 14, limit: 400)
        var near = 0
        var localLines = 0
        var huge = 0
        for feature in features {
            switch feature.geometry {
            case .point(let latitude, let longitude):
                if abs(latitude - header.startLatitude) < 0.05, abs(longitude - header.startLongitude) < 0.05 { near += 1 }
            case .line(let line):
                let lats = line.map(\.latitude)
                let lons = line.map(\.longitude)
                let latSpan = (lats.max() ?? 0) - (lats.min() ?? 0)
                let lonSpan = (lons.max() ?? 0) - (lons.min() ?? 0)
                if latSpan > 0.4 || lonSpan > 0.4 { huge += 1 }
                if latSpan < 0.05, lonSpan < 0.05,
                   line.contains(where: { abs($0.latitude - header.startLatitude) < 0.05 && abs($0.longitude - header.startLongitude) < 0.05 }) {
                    localLines += 1
                    near += 1
                }
            }
        }
        XCTAssertGreaterThan(localLines, 30)
        XCTAssertEqual(huge, 0)
        let indexed = MapsforgeReader.namedPlaces(url: url, limit: 5_000)
        XCTAssertGreaterThan(indexed.count, 20)
        XCTAssertTrue(indexed.allSatisfy { !$0.name.isEmpty && !$0.folded.isEmpty })
        XCTAssertGreaterThan(near, 30)
    }

    func testElevationAndStats() {
        let samples = ElevationSeries.fromPoints([
            ElevationPoint(latitude: 47, longitude: 19, gpsAltitude: 100, baroAltitude: 101),
            ElevationPoint(latitude: 47.01, longitude: 19, gpsAltitude: 120, baroAltitude: 119)
        ])
        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(ElevationSeries.hasBaroLine(samples))
        let stats = TrackStatsCalculator.compute([
            TrackSample(timestampMillis: 0, latitude: 47, longitude: 19, altitude: 10, speedMps: 0, bearing: 0, ambientTemperature: nil, eventKind: .START),
            TrackSample(timestampMillis: 1000, latitude: 47.001, longitude: 19, altitude: 12, speedMps: 2, bearing: 0, ambientTemperature: nil, eventKind: .MOVE)
        ])
        XCTAssertGreaterThan(stats.odometerMeters, 0)
        XCTAssertEqual(stats.movingMillis, 1000)
    }

    private func fix(t: Int64, lat: Double, lon: Double, accuracy: Float, sats: Int) -> TrackFix {
        TrackFix(timestampMillis: t, latitude: lat, longitude: lon, altitude: 100, speedMps: 0, bearing: 0, accuracyMeters: accuracy, satellitesInFix: sats)
    }
}
