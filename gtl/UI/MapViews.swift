import MapKit
@preconcurrency import MapLibre
import SwiftUI

struct MapTab: View {
    @Bindable var model: TrackerModel
    @State private var searchOpen = false
    @State private var layersOpen = false
    @State private var speedScaleToggled = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            map
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    roundButton("trash", id: "clearTrack") { model.clearMapTrack() }
                    roundButton("location", id: "locateMe") { model.locateMe() }
                    roundButton("magnifyingglass", id: "mapSearch") { searchOpen.toggle() }
                    Spacer()
                    northDial
                }
                if searchOpen {
                    searchBox
                }
                Spacer()
                    .allowsHitTesting(false)
                HStack(alignment: .bottom) {
                    hud
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        roundButton("plus", id: "zoomIn") { model.bumpZoom(1) }
                        roundButton("minus", id: "zoomOut") { model.bumpZoom(-1) }
                        roundButton("square.3.layers.3d", id: "mapLayers") { layersOpen = true }
                        if showsSpeedScale {
                            speedLegend
                        }
                        Text(model.effectiveOffline && model.settings.selectedMapId == OsmCatalog.tuhuId ? "© Turistautak.hu" : model.effectiveOffline ? "© OpenStreetMap contributors" : "")
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $layersOpen, onDismiss: { model.commitMapLayers() }) {
            MapLayerSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .topLeading) {
            mapTapCard
        }
    }

    @ViewBuilder
    private var mapTapCard: some View {
        if model.mapTapMenu {
            VStack(alignment: .leading, spacing: 0) {
                Button(L10n.text("Distance", "Távolság")) { model.chooseTapDistance() }
                    .accessibilityIdentifier("mapTapDistance")
                Button(L10n.text("GPS coordinate", "GPS koordináta")) { model.chooseTapCoordinate() }
                    .accessibilityIdentifier("mapTapCoordinate")
                Button(L10n.text("Address", "Cím")) { model.chooseTapAddress() }
                    .accessibilityIdentifier("mapTapAddress")
                routeButtons
                if let notice = model.routeNotice {
                    Text(notice)
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
            .buttonStyle(.bordered)
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .offset(x: model.mapTapX, y: model.mapTapY)
        } else if model.mapTapCoordinate, let latitude = model.mapTapLatitude, let longitude = model.mapTapLongitude {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("Lat: \(TapReadout.formatLatitude(latitude))", "Lat: \(TapReadout.formatLatitude(latitude))"))
                        Text(L10n.text("Lon: \(TapReadout.formatLongitude(longitude))", "Lon: \(TapReadout.formatLongitude(longitude))"))
                    }
                    .font(.subheadline.monospaced())
                    Button {
                        UIPasteboard.general.string = TapReadout.formatCoordinate(latitude, longitude)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityIdentifier("mapTapCopy")
                }
                Button(L10n.text("Close", "Bezárás")) { model.closeMapTap() }
                    .accessibilityIdentifier("mapTapClose")
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .offset(x: model.mapTapX, y: model.mapTapY)
        } else if model.mapTapAddress {
            VStack(alignment: .leading, spacing: 4) {
                if model.addressBusy {
                    Text(L10n.text("Looking up address…", "Cím keresése…"))
                        .font(.subheadline)
                } else if let address = model.mapTapAddressText {
                    HStack(alignment: .top) {
                        Text(address)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            UIPasteboard.general.string = address
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityIdentifier("mapTapCopy")
                    }
                } else if let notice = model.addressNotice {
                    Text(notice)
                        .font(.subheadline)
                }
                Button(L10n.text("Close", "Bezárás")) { model.closeMapTap() }
                    .accessibilityIdentifier("mapTapClose")
            }
            .padding(8)
            .frame(maxWidth: 260, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .offset(x: model.mapTapX, y: model.mapTapY)
        }
    }

    @ViewBuilder
    private var map: some View {
        if model.effectiveOffline {
            OfflineMapRepresentable(
                model: model,
                features: model.offlineFeatures,
                layerEpoch: model.layerEpoch,
                zoomTicket: model.zoomTicket,
                locateToken: model.locateToken,
                userLatitude: model.latitude,
                userLongitude: model.longitude,
                distanceLatitude: model.distanceTarget?.latitude,
                distanceLongitude: model.distanceTarget?.longitude,
                trackCount: model.trackPoints.count,
                routeCount: model.routeCoordinates.count,
                travelDegrees: model.travelDegrees,
                tiltResetToken: model.tiltResetToken,
                logging: model.logging
            )
        } else {
            OnlineMap(model: model)
        }
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.text("Place", "Hely"), text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit { model.search() }
                .onChange(of: model.searchQuery) { _, _ in model.search() }
            if model.searchIndexing && model.effectiveOffline {
                Text(L10n.text("Indexing places…", "Helyek indexelése…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !model.searchBusy && model.searchHits.isEmpty && MapSearch.accepts(model.searchQuery) {
                Text(L10n.text("No places", "Nincs találat"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.searchHits.enumerated()), id: \.offset) { _, hit in
                Button(hit.name) {
                    model.selectSearchHit(hit)
                    searchOpen = false
                }
                .font(.subheadline)
            }
        }
        .padding(8)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var distanceReadout: String? {
        guard let target = model.distanceTarget else { return nil }
        guard let latitude = model.latitude, let longitude = model.longitude else { return "—" }
        let meters = FixAcceptance.haversineMeters(latitude, longitude, target.latitude, target.longitude)
        return TapReadout.formatStraightLine(meters, model.settings.measurementSystem, prefix: L10n.text("D", "T"))
    }

    @ViewBuilder
    private var routeButtons: some View {
        if let transport = RouteTransport.forUsage(model.settings.usageType) {
            Button(L10n.text("Route", "Útvonal")) { model.chooseTapRoute(transport) }
                .accessibilityIdentifier("mapTapRoute")
        } else {
            Button(L10n.text("Walk", "Gyalog")) { model.chooseTapRoute(.walking) }
                .accessibilityIdentifier("mapTapRouteWalk")
            Button(L10n.text("Bicycle", "Kerékpár")) { model.chooseTapRoute(.cycling) }
                .accessibilityIdentifier("mapTapRouteBike")
            Button(L10n.text("Car", "Autó")) { model.chooseTapRoute(.automobile) }
                .accessibilityIdentifier("mapTapRouteCar")
        }
    }

    private var showsSpeedScale: Bool {
        !model.speedRuns.isEmpty || model.liveTail != nil
    }

    private var activeSpeedBin: Int? {
        guard model.selectedSessionId == nil, let speed = model.speedMps, speed.isFinite, speed >= 0 else { return nil }
        return SpeedColorScale.bin(speedMps: speed, usage: model.settings.usageType)
    }

    private var speedScaleOpen: Bool {
        model.settings.speedLegendAlwaysOpen || speedScaleToggled
    }

    private var speedLegend: some View {
        let usage = model.settings.usageType
        let system = model.settings.measurementSystem
        let bands = SpeedColorScale.bands(for: usage)
        let ranges = bands.map { SpeedColorScale.legendRange($0, system) }
        return Group {
            if model.settings.speedLegendAlwaysOpen {
                speedScaleBody(bands: bands, ranges: ranges, system: system, open: true)
            } else {
                Button {
                    speedScaleToggled.toggle()
                } label: {
                    speedScaleBody(bands: bands, ranges: ranges, system: system, open: speedScaleToggled)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("speedLegend")
        .accessibilityLabel(L10n.text("Speed scale", "Sebességskála"))
        .accessibilityHint(model.settings.speedLegendAlwaysOpen
            ? L10n.text("Speed bands for this usage", "Az aktuális használat sebességsávjai")
            : L10n.text("Tap to show the bands, tap again to hide them", "Koppintásra jönnek a sávok, újabb koppintásra eltűnnek"))
        .accessibilityValue(speedScaleOpen ? ranges.joined(separator: ", ") : "")
        .onChange(of: model.settings.speedLegendAlwaysOpen) { _, open in
            if !open { speedScaleToggled = false }
        }
    }

    private func speedScaleBody(bands: [SpeedBand], ranges: [String], system: MeasurementSystem, open: Bool) -> some View {
        Group {
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Units.hudSpeedUnit(system))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    ForEach(Array(bands.enumerated()), id: \.offset) { index, _ in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SpeedColor.at(index).color)
                                .frame(width: activeSpeedBin == index ? 10 : 8, height: activeSpeedBin == index ? 10 : 8)
                            Text(ranges[index])
                                .font(.caption.monospacedDigit().weight(activeSpeedBin == index ? .bold : .regular))
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 3) {
                    ForEach(bands.indices, id: \.self) { index in
                        Circle()
                            .fill(SpeedColor.at(index).color)
                            .frame(width: activeSpeedBin == index ? 9 : 8, height: activeSpeedBin == index ? 9 : 8)
                    }
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
    }

    private var hud: some View {
        let distance = distanceReadout
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                switch model.hudMode {
                case .hidden:
                    if let distance {
                        distanceChip(distance)
                    }
                case .compact, .full:
                    hudPanel(compact: model.hudMode == .compact, distance: distance)
                }
            }
            if let meters = model.routeMeters {
                Button(TapReadout.formatStraightLine(meters, model.settings.measurementSystem, prefix: L10n.text("R", "U"))) {
                    model.clearRoute()
                }
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(GtlColor.hudCyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(GtlColor.cockpit.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("mapRouteClear")
            } else if let notice = model.routeNotice, !model.mapTapMenu {
                Text(notice)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func distanceChip(_ distance: String) -> some View {
        Button(distance) { model.clearDistance() }
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .foregroundStyle(GtlColor.hudCyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GtlColor.cockpit.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("mapDistance")
    }

    private func hudPanel(compact: Bool, distance: String?) -> some View {
        let speed = model.speedMps.map { Units.hudSpeedNumber($0, model.settings.measurementSystem) } ?? "—"
        let accuracy = model.accuracy.map { String(format: "%.1f m", $0) } ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 12) {
                if !compact {
                    Text("REC")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(GtlColor.carmine)
                        .padding(.bottom, 6)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(speed)
                        .font(.system(size: compact ? 28 : 44, weight: .medium, design: .monospaced))
                        .foregroundStyle(hudSpeedColor)
                        .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                    Text(Units.hudSpeedUnit(model.settings.measurementSystem))
                        .font(.caption)
                        .foregroundStyle(GtlColor.moonCream.opacity(0.8))
                }
                if !compact {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Units.formatDistance(model.stats.odometerMeters, model.settings.measurementSystem))
                        Text(Units.formatDuration(model.stats.elapsedMillis))
                    }
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(GtlColor.hudCyan)
                }
            }
            Text(accuracy)
                .font(.caption)
                .foregroundStyle(GtlColor.moonCream.opacity(0.8))
            if let distance {
                Button(distance) { model.clearDistance() }
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(GtlColor.hudCyan)
                    .accessibilityIdentifier("mapDistance")
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .background(GtlColor.cockpit.opacity(compact ? 0.55 : 0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(compact ? 0.85 : 1)
        .accessibilityIdentifier("mapHud")
    }

    private var hudSpeedColor: Color {
        guard model.selectedSessionId == nil, let speed = model.speedMps, speed.isFinite, speed >= 0 else {
            return GtlColor.hudCyan
        }
        return SpeedColor.at(SpeedColorScale.bin(speedMps: speed, usage: model.settings.usageType)).color
    }

    private var northDial: some View {
        Button {
            model.resetMapTilt()
        } label: {
            ZStack {
                Circle().stroke(GtlColor.hudTeal, lineWidth: 2)
                Text("N").font(.caption2.bold()).offset(y: -10)
            }
            .frame(width: 36, height: 36)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .rotationEffect(.degrees(-model.mapHeading))
        }
        .accessibilityIdentifier("northDial")
    }

    private func roundButton(_ system: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityIdentifier(id)
    }
}

struct OnlineMap: View {
    @Bindable var model: TrackerModel
    @State private var position: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 8_000
    @State private var applyingFollow = false
    @State private var followLatitude: Double?
    @State private var followLongitude: Double?
    @State private var previousAim: Double = 0

    var body: some View {
        MapReader { proxy in
        Map(position: $position) {
            trackLines
            routeLine
            endpoints
            if let latitude = model.latitude, let longitude = model.longitude {
                userMark(latitude: latitude, longitude: longitude)
                if model.settings.showAccuracyMarker, let accuracy = model.accuracy {
                    MapCircle(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: CLLocationDistance(accuracy))
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 1).opacity(0.2))
                        .stroke(Color(red: 0.08, green: 0.08, blue: 0.99), lineWidth: 1)
                }
            }
                if model.settings.showFixCloud {
                ForEach(Array(model.fixCloud.samples.enumerated()), id: \.offset) { _, sample in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)) {
                        Circle().fill(Color(red: 0.96, green: 0.56, blue: 0.69)).frame(width: 6, height: 6)
                    }
                }
            }
            if let latitude = model.distanceTarget?.latitude, let longitude = model.distanceTarget?.longitude {
                Annotation("Distance", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                    Circle()
                        .fill(GtlColor.hudTeal)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(mapStyle)
        .onChange(of: model.trackPoints.count) { _, _ in follow() }
        .onChange(of: model.latitude) { _, _ in follow() }
        .onChange(of: model.focusToken) { _, _ in showTarget() }
        .onChange(of: model.zoomTicket) { _, _ in zoomBy(model.zoomStep) }
        .onChange(of: model.locateToken) { _, _ in showTarget() }
        .onAppear { follow() }
        .onTapGesture { location in
            guard let coordinate = proxy.convert(location, from: .local) else { return }
            model.beginMapTap(latitude: coordinate.latitude, longitude: coordinate.longitude, x: location.x, y: location.y)
        }
        .onMapCameraChange { context in
            if applyingFollow {
                applyingFollow = false
            } else {
                model.mapPitch = FollowCamera.clampPitch(context.camera.pitch)
            }
            model.mapHeading = context.camera.heading
            guard model.mapTapMenu || model.mapTapCoordinate || model.mapTapAddress,
                  let latitude = model.mapTapLatitude,
                  let longitude = model.mapTapLongitude,
                  let point = proxy.convert(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), to: .local) else { return }
            model.moveMapTapAnchor(x: point.x, y: point.y)
        }
        .onChange(of: model.travelDegrees) { _, _ in follow() }
        .onChange(of: model.logging) { _, logging in
            if logging { follow() }
        }
        .onChange(of: model.tiltResetToken) { _, _ in applyTiltReset() }
        }
    }

    private func coordinates(_ points: [GeoPoint]) -> [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    @MapContentBuilder
    private var trackLines: some MapContent {
        ForEach(Array(model.speedRuns.enumerated()), id: \.offset) { _, run in
            MapPolyline(coordinates: coordinates(run.points))
                .stroke(SpeedColor.at(run.bin).color, lineWidth: 4)
        }
        if let tail = model.liveTail {
            MapPolyline(coordinates: coordinates(tail.points))
                .stroke(SpeedColor.at(tail.bin).color, lineWidth: 4)
        }
    }

    @MapContentBuilder
    private var routeLine: some MapContent {
        if model.routeCoordinates.count >= 2 {
            MapPolyline(coordinates: coordinates(model.routeCoordinates))
                .stroke(
                    Color(red: 0.13, green: 0.45, blue: 0.93),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6])
                )
        }
    }

    @MapContentBuilder
    private var endpoints: some MapContent {
        let points = model.displayPoints
        if let start = TrackEndpoints.start(points) {
            Annotation("S", coordinate: coordinate(start)) {
                Text("S").font(.caption.bold()).padding(5).background(.green).clipShape(Circle()).foregroundStyle(.white)
            }
        }
        if let end = TrackEndpoints.end(points, logging: model.logging) {
            Annotation("E", coordinate: coordinate(end)) {
                Text("E").font(.caption.bold()).padding(5).background(GtlColor.carmine).clipShape(Circle()).foregroundStyle(.white)
            }
        }
    }

    private func userMark(latitude: Double, longitude: Double) -> some MapContent {
        Annotation("You", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
            ZStack {
                Circle()
                    .fill(GtlColor.carmine)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 22, height: 22)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(FollowCamera.angleDelta(model.mapHeading, model.travelDegrees ?? model.mapHeading)))
            }
        }
    }

    private func zoomBy(_ step: Int) {
        let center = position.camera?.centerCoordinate
            ?? position.region?.center
            ?? CLLocationCoordinate2D(
                latitude: model.latitude ?? model.target?.latitude ?? 47.497,
                longitude: model.longitude ?? model.target?.longitude ?? 19.040
            )
        if let camera = position.camera {
            cameraDistance = camera.distance
        } else if let region = position.region {
            cameraDistance = max(200, region.span.latitudeDelta * 111_000)
        }
        cameraDistance = min(20_000_000, max(100, cameraDistance * (step > 0 ? 0.5 : 2)))
        applyingFollow = true
        position = .camera(MapCamera(
            centerCoordinate: center,
            distance: cameraDistance,
            heading: model.mapHeading,
            pitch: model.mapPitch
        ))
    }

    private func showTarget() {
        guard let target = model.target else { return }
        let meters = max(250, 600 * pow(2.0, Double(18 - model.focusZoom)))
        cameraDistance = meters
        applyingFollow = true
        position = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            distance: meters,
            heading: model.mapHeading,
            pitch: model.mapPitch
        ))
    }

    private var mapStyle: MapStyle {
        switch model.settings.mapLayer {
        case .standard: return .standard(elevation: .realistic)
        case .satellite: return .imagery(elevation: .realistic)
        case .hybrid: return .hybrid(elevation: .realistic)
        }
    }

    private func applyTiltReset() {
        let center = position.camera?.centerCoordinate
            ?? position.region?.center
            ?? CLLocationCoordinate2D(
                latitude: model.latitude ?? model.target?.latitude ?? 47.497,
                longitude: model.longitude ?? model.target?.longitude ?? 19.040
            )
        let heading = model.headingUp ? (model.travelDegrees ?? 0) : 0
        previousAim = heading
        model.mapHeading = heading
        model.mapPitch = FollowCamera.defaultPitch
        applyingFollow = true
        position = .camera(MapCamera(
            centerCoordinate: center,
            distance: cameraDistance,
            heading: heading,
            pitch: FollowCamera.defaultPitch
        ))
    }

    private func follow() {
        guard model.logging else { return }
        let latitude = model.latitude ?? model.trackPoints.last?.latitude
        let longitude = model.longitude ?? model.trackPoints.last?.longitude
        guard let latitude, let longitude else { return }
        if model.settings.keepWholeTrackOnScreen, let bounds = TrackCameraBounds.of(model.displayPoints, extra: nil) {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (bounds.minLatitude + bounds.maxLatitude) / 2, longitude: (bounds.minLongitude + bounds.maxLongitude) / 2),
                span: MKCoordinateSpan(latitudeDelta: max(0.01, bounds.maxLatitude - bounds.minLatitude), longitudeDelta: max(0.01, bounds.maxLongitude - bounds.minLongitude))
            )
            cameraDistance = max(200, region.span.latitudeDelta * 111_000)
            applyingFollow = true
            position = .region(region)
            model.mapHeading = 0
            model.mapPitch = 0
            previousAim = 0
            return
        }
        let moved: Double
        if let previousLatitude = followLatitude, let previousLongitude = followLongitude {
            moved = FixAcceptance.haversineMeters(previousLatitude, previousLongitude, latitude, longitude)
        } else {
            moved = FollowCamera.recenterMeters
        }
        guard let pose = FollowCamera.pose(
            logging: true,
            keepWholeTrack: false,
            headingUp: model.headingUp,
            travelDegrees: model.travelDegrees,
            storedPitch: model.mapPitch,
            previousHeading: previousAim,
            movedMeters: moved
        ) else { return }
        guard pose.recenter || pose.updateAim else { return }
        if cameraDistance > 5_000 { cameraDistance = 1200 }
        let centerLatitude = pose.recenter ? latitude : (followLatitude ?? latitude)
        let centerLongitude = pose.recenter ? longitude : (followLongitude ?? longitude)
        if pose.recenter {
            followLatitude = latitude
            followLongitude = longitude
        }
        previousAim = pose.heading
        model.mapHeading = pose.heading
        model.mapPitch = pose.pitch
        applyingFollow = true
        position = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude),
            distance: cameraDistance,
            heading: pose.heading,
            pitch: pose.pitch
        ))
    }

    private func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}

final class OfflineLabelView: UIView {
    struct Mark {
        var text: String
        var point: CGPoint
        var font: UIFont
        var color: UIColor
        var angle: CGFloat
    }

    var marks: [Mark] = [] {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for mark in marks {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: mark.font,
                .foregroundColor: mark.color,
                .strokeColor: UIColor(white: 1, alpha: 0.94),
                .strokeWidth: -2.6
            ]
            let size = (mark.text as NSString).size(withAttributes: attributes)
            context.saveGState()
            context.translateBy(x: mark.point.x, y: mark.point.y)
            context.rotate(by: mark.angle)
            (mark.text as NSString).draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
            context.restoreGState()
        }
    }
}

private struct LabelAnchor {
    var text: String
    var latitude: Double
    var longitude: Double
    var endLatitude: Double
    var endLongitude: Double
    var rotate: Bool
    var rank: Int
    var font: UIFont
    var color: UIColor
}

extension SpeedColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

struct OfflineMapRepresentable: UIViewRepresentable {
    var model: TrackerModel
    var features: [MapFeature]
    var layerEpoch: Int
    var zoomTicket: Int
    var locateToken: Int
    var userLatitude: Double?
    var userLongitude: Double?
    var distanceLatitude: Double?
    var distanceLongitude: Double?
    var trackCount: Int
    var routeCount: Int
    var travelDegrees: Double?
    var tiltResetToken: Int
    var logging: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let style = Bundle.main.url(forResource: "offline-style", withExtension: "json")
        let map = MLNMapView(frame: .zero, styleURL: style)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.compassView.isHidden = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        let labels = OfflineLabelView(frame: map.bounds)
        labels.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.addSubview(labels)
        context.coordinator.labels = labels
        context.coordinator.mapView = map
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.model = model
        context.coordinator.features = features
        context.coordinator.layerEpoch = layerEpoch
        context.coordinator.zoomTicket = zoomTicket
        context.coordinator.locateToken = locateToken
        context.coordinator.userLatitude = userLatitude
        context.coordinator.userLongitude = userLongitude
        context.coordinator.distanceLatitude = distanceLatitude
        context.coordinator.distanceLongitude = distanceLongitude
        context.coordinator.trackCount = trackCount
        context.coordinator.routeCount = routeCount
        context.coordinator.travelDegrees = travelDegrees
        context.coordinator.tiltResetToken = tiltResetToken
        context.coordinator.logging = logging
        context.coordinator.mapView = map
        context.coordinator.place(map)
        context.coordinator.applyZoom(map)
        context.coordinator.applyFocus(map)
        context.coordinator.sync(map)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var model: TrackerModel
        var features: [MapFeature] = []
        private var source: MLNShapeSource?
        private var overlaySource: MLNShapeSource?
        private var builtLayerEpoch = -1
        private var followLatitude: Double?
        private var followLongitude: Double?
        private var lastLabelTime: TimeInterval = 0
        private var placedId = ""
        private var cameraReady = false
        private var cameraSet = false
        private var framed = false
        var layerEpoch = 0
        var zoomTicket = 0
        var locateToken = 0
        var userLatitude: Double?
        var userLongitude: Double?
        var distanceLatitude: Double?
        var distanceLongitude: Double?
        var trackCount = 0
        var routeCount = 0
        var travelDegrees: Double?
        var tiltResetToken = 0
        var logging = false
        private var storedPitch = FollowCamera.defaultPitch
        private var previousAim = 0.0
        private var applyingFollow = false
        private var appliedTilt = 0
        weak var mapView: MLNMapView?
        private var appliedFocus = 0
        private var appliedZoom = 0
        private var suppressFollow = false
        fileprivate var labels: OfflineLabelView?
        private var anchorsDirty = true
        private var cachedZoom = Int.min
        private var cachedAnchors: [LabelAnchor] = []
        init(model: TrackerModel) { self.model = model }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let map = mapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            model.beginMapTap(latitude: coordinate.latitude, longitude: coordinate.longitude, x: point.x, y: point.y)
        }

        private func moveTapAnchor(_ mapView: MLNMapView) {
            guard model.mapTapMenu || model.mapTapCoordinate || model.mapTapAddress,
                  let latitude = model.mapTapLatitude,
                  let longitude = model.mapTapLongitude else { return }
            let point = mapView.convert(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), toPointTo: mapView)
            model.moveMapTapAnchor(x: point.x, y: point.y)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            install(style)
            cameraSet = false
            place(mapView)
            sync(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            guard cameraSet else { return }
            let now = CACurrentMediaTime()
            if now - lastLabelTime > 0.08 {
                lastLabelTime = now
                redrawLabels(mapView)
            }
            moveTapAnchor(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard cameraSet else { return }
            if applyingFollow {
                applyingFollow = false
            } else {
                storedPitch = FollowCamera.clampPitch(mapView.camera.pitch)
                model.mapPitch = storedPitch
            }
            model.mapHeading = mapView.camera.heading
            lastLabelTime = CACurrentMediaTime()
            redrawLabels(mapView)
            moveTapAnchor(mapView)
            let zoom = Int(mapView.zoomLevel.rounded())
            let bounds = mapView.visibleCoordinateBounds
            let box = LatLonBounds(
                minLatitude: bounds.sw.latitude,
                minLongitude: bounds.sw.longitude,
                maxLatitude: bounds.ne.latitude,
                maxLongitude: bounds.ne.longitude
            )
            model.refreshOffline(bounds: box, zoom: zoom)
        }

        private func install(_ style: MLNStyle) {
            let empty = MLNShapeCollectionFeature(shapes: [])
            let source = MLNShapeSource(identifier: "offline", shape: empty, options: nil)
            style.addSource(source)
            self.source = source
            addFill(style, "fill-water", "water", UIColor(red: 0.67, green: 0.83, blue: 0.87, alpha: 1), 1)
            addFill(style, "fill-land", "land", UIColor(red: 0.76, green: 0.86, blue: 0.70, alpha: 1), 0.9)
            addFill(style, "fill-park", "park", UIColor(red: 0.68, green: 0.84, blue: 0.62, alpha: 1), 0.95)
            addFill(style, "fill-building", "building", UIColor(red: 0.86, green: 0.80, blue: 0.74, alpha: 1), 1, outline: UIColor(red: 0.62, green: 0.55, blue: 0.50, alpha: 1))
            addLine(style, "line-contour", "contour", UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 0.85), 1)
            addLine(style, "line-waterway", "waterway", UIColor(red: 0.45, green: 0.68, blue: 0.78, alpha: 1), 1.6)
            addLine(style, "line-casing", ["motorway", "primary", "secondary", "tertiary", "road"], UIColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1), 4.2)
            addLine(style, "line-road", "road", UIColor(red: 1, green: 1, blue: 1, alpha: 1), 2.2)
            addLine(style, "line-tertiary", "tertiary", UIColor(red: 1, green: 1, blue: 1, alpha: 1), 2.6)
            addLine(style, "line-secondary", "secondary", UIColor(red: 0.98, green: 0.86, blue: 0.55, alpha: 1), 3.2)
            addLine(style, "line-primary", "primary", UIColor(red: 0.98, green: 0.70, blue: 0.55, alpha: 1), 3.6)
            addLine(style, "line-motorway", "motorway", UIColor(red: 0.91, green: 0.55, blue: 0.62, alpha: 1), 4.2)
            addLine(style, "line-path", "path", UIColor(red: 0.55, green: 0.40, blue: 0.24, alpha: 1), 1.5)
            addLine(style, "line-cycle", "cycle", UIColor(red: 0.16, green: 0.52, blue: 0.72, alpha: 1), 2.2)
            addLine(style, "line-emphasis", "emphasis", UIColor(red: 0.77, green: 0.0, blue: 0.48, alpha: 1), 3.2)
            addLine(style, "line-blaze", "blaze", UIColor(red: 0.12, green: 0.35, blue: 0.66, alpha: 1), 2.6)
            let points = MLNCircleStyleLayer(identifier: "points", source: source)
            points.predicate = NSPredicate(format: "paint == 'poi'")
            points.circleColor = NSExpression(forConstantValue: UIColor(red: 0.12, green: 0.42, blue: 0.38, alpha: 1))
            points.circleRadius = NSExpression(forConstantValue: 3.5)
            points.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            points.circleStrokeWidth = NSExpression(forConstantValue: 1)
            style.addLayer(points)
            let overlay = MLNShapeSource(identifier: "overlay", shape: MLNShapeCollectionFeature(shapes: []), options: nil)
            style.addSource(overlay)
            overlaySource = overlay
            style.setImage(Self.userArrow(), forName: "user-arrow")
            let track = MLNLineStyleLayer(identifier: "line-track", source: overlay)
            track.predicate = NSPredicate(format: "paint == 'track'")
            track.lineColor = NSExpression(
                format: "TERNARY(speedBin == 0, %@, TERNARY(speedBin == 1, %@, TERNARY(speedBin == 2, %@, TERNARY(speedBin == 3, %@, TERNARY(speedBin == 4, %@, %@)))))",
                SpeedColor.at(0).uiColor,
                SpeedColor.at(1).uiColor,
                SpeedColor.at(2).uiColor,
                SpeedColor.at(3).uiColor,
                SpeedColor.at(4).uiColor,
                SpeedColor.at(5).uiColor
            )
            track.lineWidth = NSExpression(forConstantValue: 4)
            track.lineCap = NSExpression(forConstantValue: "round")
            track.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(track)
            let route = MLNLineStyleLayer(identifier: "line-route", source: overlay)
            route.predicate = NSPredicate(format: "paint == 'route'")
            route.lineColor = NSExpression(forConstantValue: UIColor(red: 0.13, green: 0.45, blue: 0.93, alpha: 1))
            route.lineWidth = NSExpression(forConstantValue: 4)
            route.lineCap = NSExpression(forConstantValue: "round")
            route.lineDashPattern = NSExpression(forConstantValue: [NSNumber(value: 2), NSNumber(value: 1.5)])
            style.addLayer(route)
            let here = MLNSymbolStyleLayer(identifier: "here", source: overlay)
            here.predicate = NSPredicate(format: "paint == 'here'")
            here.iconImageName = NSExpression(forConstantValue: "user-arrow")
            here.iconRotation = NSExpression(forKeyPath: "bearing")
            here.iconRotationAlignment = NSExpression(forConstantValue: "map")
            here.iconPitchAlignment = NSExpression(forConstantValue: "map")
            here.iconAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(here)
            let target = MLNCircleStyleLayer(identifier: "target", source: overlay)
            target.predicate = NSPredicate(format: "paint == 'target'")
            target.circleRadius = NSExpression(forConstantValue: 7)
            target.circleColor = NSExpression(forConstantValue: UIColor(red: 0.12, green: 0.54, blue: 0.50, alpha: 1))
            target.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            target.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(target)
        }

        private func addFill(_ style: MLNStyle, _ identifier: String, _ paint: String, _ color: UIColor, _ opacity: CGFloat, outline: UIColor? = nil) {
            guard let source else { return }
            let layer = MLNFillStyleLayer(identifier: identifier, source: source)
            layer.predicate = NSPredicate(format: "paint == %@", paint)
            layer.fillColor = NSExpression(forConstantValue: color)
            layer.fillOpacity = NSExpression(forConstantValue: opacity)
            if let outline { layer.fillOutlineColor = NSExpression(forConstantValue: outline) }
            style.addLayer(layer)
        }

        private func addLine(_ style: MLNStyle, _ identifier: String, _ paint: String, _ color: UIColor, _ width: CGFloat) {
            addLine(style, identifier, [paint], color, width)
        }

        private func addLine(_ style: MLNStyle, _ identifier: String, _ paints: [String], _ color: UIColor, _ width: CGFloat) {
            guard let source else { return }
            let layer = MLNLineStyleLayer(identifier: identifier, source: source)
            layer.predicate = NSPredicate(format: "paint IN %@", paints)
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineWidth = NSExpression(forConstantValue: width)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
        }

        private func frameLocalStreets(_ map: MLNMapView) {
            guard !framed else { return }
            var minLat = 90.0
            var maxLat = -90.0
            var minLon = 180.0
            var maxLon = -180.0
            var count = 0
            for feature in features {
                guard case .line(let line) = feature.geometry, line.count >= 2 else { continue }
                let latSpan = (line.map(\.latitude).max() ?? 0) - (line.map(\.latitude).min() ?? 0)
                let lonSpan = (line.map(\.longitude).max() ?? 0) - (line.map(\.longitude).min() ?? 0)
                if latSpan > 0.01 || lonSpan > 0.01 { continue }
                for node in line {
                    minLat = min(minLat, node.latitude)
                    maxLat = max(maxLat, node.latitude)
                    minLon = min(minLon, node.longitude)
                    maxLon = max(maxLon, node.longitude)
                    count += 1
                }
            }
            guard count > 40, maxLat > minLat, maxLon > minLon else { return }
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            guard abs(centerLat - map.centerCoordinate.latitude) < 0.05, abs(centerLon - map.centerCoordinate.longitude) < 0.05 else { return }
            framed = true
            let span = max(maxLat - minLat, maxLon - minLon, 0.002)
            let zoom = min(16, max(13, Int(log2(160 / span).rounded())))
            map.setCenter(
                CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                zoomLevel: Double(zoom),
                animated: false
            )
        }

        func place(_ map: MLNMapView) {
            let id = model.settings.selectedMapId
            guard let url = try? MapPaths.mapFile(id: id), let header = MapsforgeReader.header(of: url) else { return }
            let first = placedId != id
            if first { framed = false }
            placedId = id
            cameraReady = true
            guard first || !cameraSet else { return }
            cameraSet = true
            let zoom = 14
            map.setCenter(
                CLLocationCoordinate2D(latitude: header.startLatitude, longitude: header.startLongitude),
                zoomLevel: Double(zoom),
                animated: false
            )
            let span = 0.04
            model.refreshOffline(
                bounds: LatLonBounds(
                    minLatitude: header.startLatitude - span,
                    minLongitude: header.startLongitude - span,
                    maxLatitude: header.startLatitude + span,
                    maxLongitude: header.startLongitude + span
                ),
                zoom: zoom
            )
        }

        func applyZoom(_ map: MLNMapView) {
            guard appliedZoom != zoomTicket else { return }
            appliedZoom = zoomTicket
            let next = min(18, max(2, map.zoomLevel + Double(model.zoomStep)))
            map.setZoomLevel(next, animated: true)
        }

        func applyFocus(_ map: MLNMapView) {
            guard appliedFocus != model.focusToken, let target = model.target else { return }
            appliedFocus = model.focusToken
            suppressFollow = true
            let zoom = Double(model.focusZoom)
            map.setCenter(
                CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                zoomLevel: zoom,
                animated: true
            )
            let span = max(0.002, 360.0 / pow(2.0, zoom))
            model.refreshOffline(
                bounds: LatLonBounds(
                    minLatitude: target.latitude - span,
                    minLongitude: target.longitude - span,
                    maxLatitude: target.latitude + span,
                    maxLongitude: target.longitude + span
                ),
                zoom: Int(zoom.rounded())
            )
        }

        func sync(_ map: MLNMapView) {
            if builtLayerEpoch != layerEpoch {
                builtLayerEpoch = layerEpoch
                source?.shape = MLNShapeCollectionFeature(shapes: mapShapes())
                anchorsDirty = true
                frameLocalStreets(map)
            }
            var overlay: [MLNShape & MLNFeature] = []
            for run in model.speedRuns {
                guard run.points.count >= 2 else { continue }
                var coords = run.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                polyline.attributes = ["paint": "track", "speedBin": run.bin]
                overlay.append(polyline)
            }
            if let tail = model.liveTail, tail.points.count >= 2 {
                var coords = tail.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                polyline.attributes = ["paint": "track", "speedBin": tail.bin]
                overlay.append(polyline)
            }
            if model.routeCoordinates.count >= 2 {
                var coords = model.routeCoordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let route = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                route.attributes = ["paint": "route"]
                overlay.append(route)
            }
            if let latitude = userLatitude, let longitude = userLongitude {
                let here = MLNPointFeature()
                here.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                here.attributes = ["paint": "here", "bearing": travelDegrees ?? 0]
                overlay.append(here)
            }
            if let latitude = distanceLatitude, let longitude = distanceLongitude {
                let target = MLNPointFeature()
                target.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                target.attributes = ["paint": "target"]
                overlay.append(target)
            }
            overlaySource?.shape = MLNShapeCollectionFeature(shapes: overlay)
            if anchorsDirty { redrawLabels(map) }
            if !suppressFollow {
                applyFollow(map)
            }
            suppressFollow = false
        }

        private func applyFollow(_ map: MLNMapView) {
            if tiltResetToken != appliedTilt {
                appliedTilt = tiltResetToken
                storedPitch = FollowCamera.defaultPitch
                model.mapPitch = FollowCamera.defaultPitch
                model.headingUp = true
                previousAim = model.headingUp ? (model.travelDegrees ?? 0) : 0
                writeCamera(map, heading: previousAim, pitch: FollowCamera.defaultPitch, latitude: userLatitude, longitude: userLongitude, recenter: false)
                model.mapHeading = previousAim
                return
            }
            guard model.logging, let latitude = userLatitude, let longitude = userLongitude else { return }
            if followLatitude == nil && storedPitch < 20 {
                storedPitch = FollowCamera.defaultPitch
            }
            if model.settings.keepWholeTrackOnScreen {
                let flat = map.camera.pitch > 0.5 || abs(FollowCamera.angleDelta(map.camera.heading, 0)) > 1
                if flat {
                    writeCamera(map, heading: 0, pitch: 0, latitude: latitude, longitude: longitude, recenter: false)
                }
                model.mapHeading = 0
                model.mapPitch = 0
                previousAim = 0
                return
            }
            let moved: Double
            if let previousLatitude = followLatitude, let previousLongitude = followLongitude {
                moved = FixAcceptance.haversineMeters(previousLatitude, previousLongitude, latitude, longitude)
            } else {
                moved = FollowCamera.recenterMeters
            }
            guard let pose = FollowCamera.pose(
                logging: true,
                keepWholeTrack: false,
                headingUp: model.headingUp,
                travelDegrees: model.travelDegrees,
                storedPitch: storedPitch,
                previousHeading: previousAim,
                movedMeters: moved
            ) else { return }
            guard pose.recenter || pose.updateAim else { return }
            let centerLatitude = pose.recenter ? latitude : (followLatitude ?? latitude)
            let centerLongitude = pose.recenter ? longitude : (followLongitude ?? longitude)
            if pose.recenter {
                followLatitude = latitude
                followLongitude = longitude
            }
            previousAim = pose.heading
            storedPitch = pose.pitch
            model.mapHeading = pose.heading
            model.mapPitch = pose.pitch
            writeCamera(map, heading: pose.heading, pitch: pose.pitch, latitude: centerLatitude, longitude: centerLongitude, recenter: true)
        }

        private func writeCamera(
            _ map: MLNMapView,
            heading: Double,
            pitch: Double,
            latitude: Double?,
            longitude: Double?,
            recenter: Bool
        ) {
            let camera = map.camera
            camera.heading = heading
            camera.pitch = CGFloat(pitch)
            if recenter, let latitude, let longitude {
                camera.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            applyingFollow = true
            map.setCamera(camera, animated: false)
        }

        private static func userArrow() -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28))
            return renderer.image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 22, height: 22))
                UIColor(red: 0.76, green: 0.23, blue: 0.18, alpha: 1).setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2
                circle.stroke()
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: 14, y: 6))
                arrow.addLine(to: CGPoint(x: 19, y: 18))
                arrow.addLine(to: CGPoint(x: 14, y: 15))
                arrow.addLine(to: CGPoint(x: 9, y: 18))
                arrow.close()
                UIColor.white.setFill()
                arrow.fill()
            }
        }

        private func mapShapes() -> [MLNShape & MLNFeature] {
            let hiking = model.settings.selectedMapId == OsmCatalog.tuhuId
            let settings = model.settings
            var shapes: [MLNShape & MLNFeature] = []
            for feature in features {
                switch feature.geometry {
                case .point(let latitude, let longitude):
                    guard showsPoint(feature, settings: settings, hiking: hiking) else { continue }
                    let point = MLNPointFeature()
                    point.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    point.attributes = ["paint": "poi", "name": feature.name ?? ""]
                    shapes.append(point)
                case .line(let line):
                    var coords = line.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    guard coords.count >= 2 else { continue }
                    let closed = coords.count >= 4 && abs(coords[0].latitude - coords[coords.count - 1].latitude) < 0.00002 && abs(coords[0].longitude - coords[coords.count - 1].longitude) < 0.00002
                    let paints = layerPaints(feature, closed: closed, settings: settings, hiking: hiking)
                    for paint in paints where closed && (paint == "water" || paint == "land" || paint == "park" || paint == "building") {
                        let polygon = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
                        polygon.attributes = ["paint": paint]
                        shapes.append(polygon)
                    }
                    for paint in paints where !(closed && (paint == "water" || paint == "land" || paint == "park" || paint == "building")) {
                        let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                        polyline.attributes = ["paint": paint]
                        shapes.append(polyline)
                    }
                }
            }
            return shapes
        }

        private func redrawLabels(_ map: MLNMapView) {
            guard let labels else { return }
            if labels.superview !== map { map.addSubview(labels) }
            labels.frame = map.bounds
            map.bringSubviewToFront(labels)
            map.bringSubviewToFront(map.logoView)
            let zoom = Int(map.zoomLevel.rounded())
            if anchorsDirty || cachedZoom != zoom {
                cachedZoom = zoom
                anchorsDirty = false
                cachedAnchors = offlineLabelAnchors(features: features, zoom: map.zoomLevel)
            }
            labels.marks = projectLabels(cachedAnchors, map: map)
        }
    }
}

private let labelInk = UIColor(red: 0.17, green: 0.13, blue: 0.11, alpha: 1)
private let labelRoad = UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1)
private let labelWater = UIColor(red: 0.14, green: 0.34, blue: 0.46, alpha: 1)

private func offlineLabelText(_ feature: MapFeature) -> String? {
    let name = (feature.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let ref = (feature.tags["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let text = name.isEmpty && feature.tags["highway"] != nil ? ref : name
    guard !text.isEmpty else { return nil }
    if text.count > 42 { return String(text.prefix(40)) + "…" }
    return text
}

private func pointLabelRank(_ feature: MapFeature, zoom: Double) -> Int? {
    switch feature.tags["place"] ?? "" {
    case "city", "town", "municipality":
        return zoom >= 8 ? 0 : nil
    case "village":
        return zoom >= 11 ? 1 : nil
    case "suburb", "hamlet", "neighbourhood", "quarter":
        return zoom >= 13 ? 2 : nil
    case "locality", "isolated_dwelling":
        return zoom >= 14 ? 3 : nil
    default:
        break
    }
    if feature.tags["natural"] == "peak" || feature.tags["mountain_pass"] != nil {
        return zoom >= 13 ? 3 : nil
    }
    if zoom < 15 { return nil }
    return 6
}

private func lineLabelRank(_ feature: MapFeature, zoom: Double) -> Int? {
    if feature.tags["building"] != nil { return zoom >= 17 ? 7 : nil }
    switch feature.tags["highway"] ?? "" {
    case "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link":
        return zoom >= 11 ? 1 : nil
    case "secondary", "secondary_link":
        return zoom >= 12 ? 2 : nil
    case "tertiary", "tertiary_link":
        return zoom >= 13 ? 3 : nil
    case "residential", "unclassified", "living_street", "road":
        return zoom >= 15 ? 4 : nil
    case "service":
        return zoom >= 16 ? 5 : nil
    case "path", "footway", "track", "cycleway", "bridleway", "steps":
        return zoom >= 15 ? 5 : nil
    default:
        break
    }
    if feature.tags["waterway"] != nil || feature.category == "water" {
        return zoom >= 12 ? 3 : nil
    }
    if feature.tags["place"] != nil { return zoom >= 10 ? 2 : nil }
    if feature.category == "land" || feature.category == OsmRenderOptions.catParks || feature.tags["leisure"] != nil {
        return zoom >= 13 ? 4 : nil
    }
    return nil
}

@MainActor
private func offlineLabelAnchors(features: [MapFeature], zoom: Double) -> [LabelAnchor] {
    var anchors: [LabelAnchor] = []
    for feature in features {
        if feature.tags["contour"] != nil || feature.tags["contour_ext"] != nil { continue }
        if feature.category == TuhuRenderOptions.catContours || feature.category == TuhuRenderOptions.catContoursMinor { continue }
        guard let text = offlineLabelText(feature) else { continue }
        switch feature.geometry {
        case .point(let latitude, let longitude):
            guard let rank = pointLabelRank(feature, zoom: zoom) else { continue }
            let font = rank <= 1
                ? UIFont.systemFont(ofSize: rank == 0 ? 15 : 13, weight: .semibold)
                : UIFont.systemFont(ofSize: 12, weight: .medium)
            anchors.append(LabelAnchor(
                text: text,
                latitude: latitude,
                longitude: longitude,
                endLatitude: latitude,
                endLongitude: longitude,
                rotate: false,
                rank: rank,
                font: font,
                color: labelInk
            ))
        case .line(let line):
            guard line.count >= 2, let rank = lineLabelRank(feature, zoom: zoom) else { continue }
            let closed = abs(line[0].latitude - line[line.count - 1].latitude) < 0.00002
                && abs(line[0].longitude - line[line.count - 1].longitude) < 0.00002
            let area = closed && (feature.category == "land" || feature.category == "water" || feature.category == OsmRenderOptions.catParks || feature.tags["place"] != nil || feature.tags["leisure"] != nil)
            if area {
                let latitude = line.reduce(0.0) { $0 + $1.latitude } / Double(line.count)
                let longitude = line.reduce(0.0) { $0 + $1.longitude } / Double(line.count)
                anchors.append(LabelAnchor(
                    text: text,
                    latitude: latitude,
                    longitude: longitude,
                    endLatitude: latitude,
                    endLongitude: longitude,
                    rotate: false,
                    rank: rank,
                    font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    color: feature.category == "water" ? labelWater : labelInk
                ))
            } else {
                var best = -1.0
                var start = line[0]
                var end = line[1]
                for index in 1..<line.count {
                    let dLat = line[index].latitude - line[index - 1].latitude
                    let dLon = line[index].longitude - line[index - 1].longitude
                    let score = dLat * dLat + dLon * dLon
                    if score > best {
                        best = score
                        start = line[index - 1]
                        end = line[index]
                    }
                }
                let water = feature.tags["waterway"] != nil || feature.category == "water"
                anchors.append(LabelAnchor(
                    text: text,
                    latitude: start.latitude,
                    longitude: start.longitude,
                    endLatitude: end.latitude,
                    endLongitude: end.longitude,
                    rotate: true,
                    rank: rank,
                    font: UIFont.systemFont(ofSize: zoom >= 15 ? 12 : 11, weight: .medium),
                    color: water ? labelWater : labelRoad
                ))
            }
        }
    }
    anchors.sort { $0.rank < $1.rank }
    if anchors.count > 180 { return Array(anchors.prefix(180)) }
    return anchors
}

@MainActor
private func projectLabels(_ anchors: [LabelAnchor], map: MLNMapView) -> [OfflineLabelView.Mark] {
    guard map.bounds.width > 2, map.bounds.height > 2 else { return [] }
    let usable = CGRect(x: 4, y: 52, width: max(0, map.bounds.width - 58), height: max(0, map.bounds.height - 60))
    var occupied: [CGRect] = []
    var marks: [OfflineLabelView.Mark] = []
    for anchor in anchors {
        let start = map.convert(CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude), toPointTo: map)
        let end = map.convert(CLLocationCoordinate2D(latitude: anchor.endLatitude, longitude: anchor.endLongitude), toPointTo: map)
        let point = anchor.rotate ? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) : start
        guard usable.contains(point) else { continue }
        var angle: CGFloat = 0
        if anchor.rotate {
            let dx = end.x - start.x
            let dy = end.y - start.y
            if hypot(dx, dy) < 34 { continue }
            angle = atan2(dy, dx)
            if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }
        }
        let size = (anchor.text as NSString).size(withAttributes: [.font: anchor.font])
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height).insetBy(dx: -4, dy: -2)
        if occupied.contains(where: { $0.intersects(rect) }) { continue }
        occupied.append(rect)
        marks.append(OfflineLabelView.Mark(text: anchor.text, point: point, font: anchor.font, color: anchor.color, angle: angle))
        if marks.count >= 56 { break }
    }
    return marks
}

private func mapPaint(_ feature: MapFeature, closed: Bool) -> String {
    let highway = feature.tags["highway"] ?? ""
    switch feature.category {
    case "water":
        return closed ? "water" : "waterway"
    case OsmRenderOptions.catParks, TuhuRenderOptions.catParks:
        return closed ? "park" : "path"
    case OsmRenderOptions.catBuildings:
        return closed ? "building" : "road"
    case TuhuRenderOptions.catContours, TuhuRenderOptions.catContoursMinor:
        return "contour"
    case TuhuRenderOptions.catPaths, TuhuRenderOptions.catBlazes:
        return "path"
    case OsmRenderOptions.catCycleways:
        return "cycle"
    case "land":
        return closed ? "land" : "path"
    default:
        switch highway {
        case "motorway", "motorway_link", "trunk", "trunk_link": return "motorway"
        case "primary", "primary_link": return "primary"
        case "secondary", "secondary_link": return "secondary"
        case "tertiary", "tertiary_link": return "tertiary"
        case "path", "footway", "track", "bridleway", "steps": return "path"
        case "cycleway": return "cycle"
        default: return "road"
        }
    }
}

private func layerPaints(_ feature: MapFeature, closed: Bool, settings: GtlSettings, hiking: Bool) -> [String] {
    let tags = feature.tags
    let highway = tags["highway"] ?? ""
    let base = mapPaint(feature, closed: closed)
    let pathLike = highway == "path" || highway == "footway" || highway == "track" || highway == "bridleway" || highway == "steps" || feature.category == TuhuRenderOptions.catPaths
    var paints: [String] = []
    let hideBuilding = base == "building" && !hiking && !settings.osm.buildings
    let hidePark = base == "park" && !(hiking ? settings.tuhu.parks : settings.osm.parks)
    let hideContour = base == "contour" && (
        (feature.category == TuhuRenderOptions.catContoursMinor || tags["contour_ext"] == "elevation_minor")
            ? !settings.tuhu.contoursMinor
            : !settings.tuhu.contours
    )
    let hideTransit = feature.category == OsmRenderOptions.catTransit && !(hiking ? settings.tuhu.urbanPoi : settings.osm.transit)
    if !hideBuilding && !hidePark && !hideContour && !hideTransit {
        paints.append(base)
    }
    if hiking && settings.tuhu.paths && pathLike {
        paints.append("emphasis")
    }
    if !hiking && settings.osm.cycleways && (highway == "cycleway" || tags["bicycle"] == "designated" || feature.category == OsmRenderOptions.catCycleways) {
        paints.append("emphasis")
    }
    let marked = tags["osmc:symbol"] != nil || tags["kct_red"] != nil || tags["kct_blue"] != nil || tags["kct_green"] != nil || tags["kct_yellow"] != nil || (tags["ref"] != nil && pathLike)
    if hiking && settings.tuhu.blazes && marked {
        paints.append("blaze")
    }
    if hiking && settings.tuhu.contours && tags["contour_ext"] != "elevation_minor" && (tags["contour"] != nil || tags["contour_ext"] == "elevation_major") && !paints.contains("contour") {
        paints.append("contour")
    }
    if hiking && settings.tuhu.contoursMinor && tags["contour_ext"] == "elevation_minor" && !paints.contains("contour") {
        paints.append("contour")
    }
    return paints
}

private func showsPoint(_ feature: MapFeature, settings: GtlSettings, hiking: Bool) -> Bool {
    let tags = feature.tags
    if hiking {
        if hikePoint(tags) { return settings.tuhu.hikePoi }
        if urbanPoint(tags) { return settings.tuhu.urbanPoi }
        return false
    }
    if feature.category == OsmRenderOptions.catTransit || tags["railway"] != nil || tags["public_transport"] != nil || tags["highway"] == "bus_stop" {
        return settings.osm.transit
    }
    return settings.osm.poi
}

private func hikePoint(_ tags: [String: String]) -> Bool {
    switch tags["natural"] {
    case "peak", "spring", "cave_entrance", "cliff", "saddle", "volcano": return true
    default: break
    }
    switch tags["tourism"] {
    case "alpine_hut", "wilderness_hut", "viewpoint", "camp_site", "information": return true
    default: break
    }
    return tags["amenity"] == "shelter"
}

private func urbanPoint(_ tags: [String: String]) -> Bool {
    if hikePoint(tags) { return false }
    return tags["amenity"] != nil || tags["shop"] != nil || tags["highway"] == "bus_stop"
}

struct MapLayerSheet: View {
    @Bindable var model: TrackerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if model.effectiveOffline {
                    OfflineLayerControls(model: model)
                } else {
                    Section(L10n.text("Apple Maps", "Apple térkép")) {
                        layerButton("Standard", .standard)
                        layerButton("Satellite", .satellite)
                        layerButton("Hybrid", .hybrid)
                    }
                }
            }
            .navigationTitle(L10n.text("Map layers", "Térképrétegek"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Done", "Kész")) {
                    model.commitMapLayers()
                    dismiss()
                }
                }
            }
        }
    }

    private func layerButton(_ title: String, _ layer: MapLayer) -> some View {
        Button {
            model.updateSettings { $0.mapLayer = layer }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if model.settings.mapLayer == layer {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

struct OfflineLayerControls: View {
    @Bindable var model: TrackerModel

    var body: some View {
        if model.settings.selectedMapId == OsmCatalog.tuhuId {
            Section("Turistautak.hu") {
                toggle(L10n.text("Trail blazes", "Jelzések"), key: \.tuhu.blazes)
                toggle(L10n.text("Emphasize paths", "Utak kiemelése"), key: \.tuhu.paths)
                toggle(L10n.text("Contour lines", "Szintvonalak"), key: \.tuhu.contours)
                toggle(L10n.text("Minor contours", "Mellékszintvonalak"), key: \.tuhu.contoursMinor)
                toggle(L10n.text("Hiking POI", "Turista POI"), key: \.tuhu.hikePoi)
                toggle(L10n.text("Protected areas", "Védett területek"), key: \.tuhu.parks)
                toggle(L10n.text("Urban POI", "Városi POI"), key: \.tuhu.urbanPoi)
                hillshade(\.tuhu.hillshading)
            }
        } else {
            Section("OpenStreetMap") {
                toggle(L10n.text("Buildings", "Épületek"), key: \.osm.buildings)
                toggle("POI", key: \.osm.poi)
                toggle(L10n.text("Public transport", "Tömegközlekedés"), key: \.osm.transit)
                toggle(L10n.text("Highlight cycleways", "Kerékpárutak"), key: \.osm.cycleways)
                toggle(L10n.text("Parks", "Parkok"), key: \.osm.parks)
                hillshade(\.osm.hillshading)
            }
        }
    }

    private func toggle(_ title: String, key: WritableKeyPath<GtlSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.settings[keyPath: key] },
            set: { value in model.updateSettings { $0[keyPath: key] = value } }
        ))
    }

    private func hillshade(_ key: WritableKeyPath<GtlSettings, Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L10n.text("Terrain relief", "Domborzat"), isOn: Binding(
                get: { false },
                set: { _ in model.updateSettings { $0[keyPath: key] = false } }
            ))
            .disabled(true)
            Text(model.hillshadeAvailable
                ? L10n.text(
                    "Elevation files are next to this map. This view does not draw a relief overlay.",
                    "A magasságfájlok a térkép mellett vannak. Ez a nézet nem rajzol domborzatárnyékot."
                )
                : L10n.text(
                    "No hillshade for this map. Official downloads do not include relief files.",
                    "Ehhez a térképhez nincs domborzatárnyékolás. A hivatalos letöltésben nincsenek magasságfájlok."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
