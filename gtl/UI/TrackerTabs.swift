import SwiftUI

struct TrackerScreen: View {
    @Bindable var model: TrackerModel
    @Environment(\.colorScheme) private var scheme
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                Group {
                    switch model.tab {
                    case .gps: GpsTab(model: model, openLocationSettings: { path.append("location") })
                    case .route: RouteTab(model: model)
                    case .map: MapTab(model: model)
                    case .compass: CompassTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                tabBar
            }
            .background { GtlBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { route in
                Group {
                    switch route {
                    case "settings": SettingsScreen(model: model)
                    case "maps": MapDownloadScreen(model: model)
                    case "tracks": TracksScreen(model: model)
                    case "help": HelpScreen(model: model)
                    case "about": AboutScreen(model: model)
                    case "location": LocationSettingsScreen()
                    case "diagnostics": ErrorLogScreen()
                    default: EmptyView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
        }
        .onChange(of: model.tab) { _, _ in model.onTabChange() }
        .onChange(of: model.returnToMap) { _, go in
            if go {
                path.removeAll()
                model.returnToMap = false
            }
        }
        .onAppear { model.onTabChange() }
        .onChange(of: model.showErrorLog) { _, show in
            if show {
                path.append("diagnostics")
                model.showErrorLog = false
            }
        }
        .sheet(isPresented: $model.showAlwaysExplanation) {
            AlwaysExplanationSheet(
                allow: { model.allowBackgroundLogging() },
                whileUsing: { model.logOnlyWhileUsingApp() }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GPS Track Logger")
                    .font(.headline)
                    .foregroundStyle(GtlColor.titleMagenta)
                    .accessibilityIdentifier("brandTitle")
                Spacer()
                Button(model.logging ? L10n.text("Stop", "Stop") : L10n.text("Start", "Start")) {
                    model.logging ? model.stopLogging() : model.startLogging()
                }
                .buttonStyle(GtlPrimaryButton(color: model.logging ? GtlColor.trackingOrange : GtlColor.startBlue))
                .frame(width: 110)
                .accessibilityIdentifier(model.logging ? "stopLogging" : "startLogging")
                Menu {
                    Button(L10n.text("Settings", "Beállítások")) { path.append("settings") }
                    Button(L10n.text("Download offline map", "Offline térkép letöltése")) { path.append("maps") }
                    Button(L10n.text("Saved tracks", "Mentett útvonalak")) { path.append("tracks") }
                    Button(L10n.text("Help", "Súgó")) { path.append("help") }
                    Button(L10n.text("About", "Névjegy")) { path.append("about") }
                    Button(L10n.text("Location settings", "Helyzet beállítások")) { path.append("location") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .accessibilityIdentifier("mainMenu")
            }
            if model.logging && !model.recordsWhileLocked {
                Text(L10n.text(
                    "A locked screen stops this recording. Set Location to Always to keep the track.",
                    "Zárolt képernyőn ez a rögzítés megáll. A folyamatos nyomvonalhoz a Helyzet legyen Mindig."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lockedScreenNotice")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack {
            tabButton(.gps, L10n.text("GPS", "GPS"), "location.fill")
            tabButton(.route, L10n.text("Route", "Útvonal"), "point.topleft.down.curvedto.point.bottomright.up")
            tabButton(.map, L10n.text("Map", "Térkép"), "map")
            tabButton(.compass, L10n.text("Compass", "Iránytű"), "safari")
        }
        .padding(.vertical, 8)
        .background(scheme == .dark ? GtlColor.cockpitPanel : GtlColor.paper)
    }

    private func tabButton(_ tab: TrackerTab, _ title: String, _ icon: String) -> some View {
        Button {
            model.tab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(model.tab == tab ? GtlColor.hudTeal : .secondary)
        }
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

struct AlwaysExplanationSheet: View {
    var allow: () -> Void
    var whileUsing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Location while locked", "Helyzet zárolt képernyőn"))
                .font(.title2.bold())
            Text(L10n.text(
                "Recording on a locked screen needs Location set to Always. The blue indicator stays visible until Stop. Stop ends background updates.",
                "Zárolt képernyőn a rögzítéshez a Helyzet legyen Mindig. A kék jelző a Stopig látszik. A Stop leállítja a háttérfrissítést."
            ))
            Button(L10n.text("Allow Always", "Mindig engedélyezése"), action: allow)
                .buttonStyle(GtlPrimaryButton(color: GtlColor.startBlue))
            Button(L10n.text("Only while using the app", "Csak az app használata közben"), action: whileUsing)
                .buttonStyle(GtlPrimaryButton(color: GtlColor.hudTeal))
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

struct GpsTab: View {
    let model: TrackerModel
    var openLocationSettings: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var degreeSize: CGFloat = 44

    var body: some View {
        let ink = instrumentInk(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
                .accessibilityIdentifier("gpsStatus")
                if model.locationAuthorization == .denied || model.locationAuthorization == .restricted || model.preciseLocationRequired {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(locationGate)
                            .font(.body)
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: openLocationSettings) {
                            Text(L10n.text("Location settings", "Helyzet beállítások"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(GtlColor.carmine)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    degreeLine(L10n.text("Latitude", "Szélesség"), model.latitude, north: true, ink: ink)
                    degreeLine(L10n.text("Longitude", "Hosszúság"), model.longitude, north: false, ink: ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.accuracy.map { String(format: "%.0f m", $0) } ?? "—")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accuracyTint)
                    Text(L10n.text("Accuracy", "Pontosság"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 18)
            InstrumentRule()
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                FieldPair(
                    leftTitle: L10n.text("GPS altitude", "GPS magasság"),
                    leftValue: altitude(model.altitude),
                    rightTitle: L10n.text("Baro", "Baro"),
                    rightValue: altitude(model.baroAltitude),
                    ink: ink
                )
                FieldPair(
                    leftTitle: L10n.text("Ellipsoid", "Ellipszoid"),
                    leftValue: altitude(model.ellipsoidalAltitude),
                    rightTitle: L10n.text("Pressure", "Nyomás"),
                    rightValue: model.pressureHpa.map { String(format: "%.1f hPa", $0) } ?? "—",
                    ink: ink
                )
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FieldPair(
                        leftTitle: L10n.text("Vertical accuracy", "Függőleges pontosság"),
                        leftValue: model.verticalAccuracy.map { String(format: "%.0f m", $0) } ?? "—",
                        rightTitle: L10n.text("Fix age", "Fix kora"),
                        rightValue: fixAge(at: context.date),
                        ink: ink
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            if model.settings.showFixCloud {
                InstrumentRule()
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                HStack(alignment: .top, spacing: 12) {
                    FieldReading(title: "n", value: "\(model.fixCloud.stats.sampleCount)", ink: ink)
                    FieldReading(title: "RMS", value: model.fixCloud.stats.rmsMeters.map { String(format: "%.1f m", $0) } ?? "—", ink: ink)
                    FieldReading(title: "CEP95", value: model.fixCloud.stats.cep95Meters.map { String(format: "%.1f m", $0) } ?? "—", ink: ink)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
            }
            .padding(.bottom, 12)
        }
    }

    private func degreeLine(_ title: String, _ value: Double?, north: Bool, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.map { String(format: "%.6f°", abs($0)) } ?? "—")
                    .font(.system(size: degreeSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                if let value {
                    Text(hemisphere(value, north: north))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(north && value >= 0 ? GtlColor.carmine : ink)
                }
            }
        }
    }

    private func hemisphere(_ value: Double, north: Bool) -> String {
        if north { return value >= 0 ? "N" : "S" }
        return value >= 0 ? "E" : "W"
    }

    private func altitude(_ meters: Double?) -> String {
        meters.map { Units.formatAltitude($0, model.settings.measurementSystem) } ?? "—"
    }

    private func fixAge(at now: Date) -> String {
        guard let lastFixAt = model.lastFixAt else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(lastFixAt)))
        return "\(seconds) s"
    }

    private var locationGate: String {
        if model.preciseLocationRequired {
            return L10n.text(
                "Precise location is required. Turn on Precise Location in Settings.",
                "Pontos hely kell. Kapcsold be a Pontos helyet a Beállításokban."
            )
        }
        return L10n.text(
            "Location is off. Turn it on in Settings to record a route.",
            "A helyzet ki van kapcsolva. Az útvonal rögzítéséhez kapcsold be a Beállításokban."
        )
    }

    private var statusLine: String {
        if model.locationAuthorization == .denied || model.locationAuthorization == .restricted {
            return L10n.text("Location is off", "A helyzet ki van kapcsolva")
        }
        if model.preciseLocationRequired {
            return L10n.text("Precise location is required", "Pontos hely kell")
        }
        if model.logging && model.poorGps { return L10n.text("GPS quality is too low", "A GPS minősége túl alacsony") }
        if model.logging { return L10n.text("Logging", "Naplózás") }
        if model.latitude == nil { return L10n.text("Waiting for GPS", "Várakozás a GPS-re") }
        return L10n.text("Idle", "Üresjárat")
    }

    private var statusTint: Color {
        if model.locationAuthorization == .denied || model.locationAuthorization == .restricted || model.preciseLocationRequired {
            return GtlColor.carmine
        }
        if model.logging && model.poorGps { return GtlColor.amber }
        if model.logging { return liveAccent(scheme) }
        return Color.secondary
    }

    private var accuracyTint: Color {
        guard let meters = model.accuracy else { return Color.secondary }
        if meters <= 15 { return liveAccent(scheme) }
        if meters <= 40 { return instrumentInk(scheme) }
        return GtlColor.amber
    }
}

struct RouteTab: View {
    let model: TrackerModel
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var speedSize: CGFloat = 92

    var body: some View {
        let ink = instrumentInk(scheme)
        let accent = liveAccent(scheme)
        let speed = Units.formatSpeed(RouteTabSpeeds.instantMps(logging: model.logging, liveSpeedMps: model.speedMps) ?? 0, model.settings.measurementSystem)
        let average = Units.formatSpeed(RouteTabSpeeds.averageMps(logging: model.logging, sessionAverageMps: model.stats.averageSpeedMps), model.settings.measurementSystem)
        let parts = MeasureParts(speed)
        GeometryReader { geo in
            let chartHeight = min(160, max(128, geo.size.height * 0.22))
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Text(parts.number)
                            .font(.system(size: speedSize, weight: model.logging ? .medium : .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(model.logging ? ink : Color.secondary)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Text(parts.unit)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(model.logging ? accent : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.text("Speed", "Sebesség"))
                    .accessibilityValue(speed)
                    .padding(.top, 8)
                    VStack(spacing: 2) {
                        Text(average)
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                        Text(L10n.text("Average", "Átlag"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    InstrumentRule()
                    HStack(alignment: .center, spacing: 0) {
                        VStack(spacing: 22) {
                            FieldReading(
                                title: L10n.text("Elapsed", "Eltelt"),
                                value: Units.formatDuration(model.stats.elapsedMillis),
                                ink: ink,
                                centered: true
                            )
                            FieldReading(
                                title: L10n.text("Time moving", "Mozgásban"),
                                value: Units.formatDuration(model.stats.movingMillis),
                                ink: ink,
                                centered: true
                            )
                        }
                        VStack(spacing: 22) {
                            FieldReading(
                                title: L10n.text("Odometer", "Számláló"),
                                value: Units.formatDistance(model.stats.odometerMeters, model.settings.measurementSystem),
                                ink: ink,
                                centered: true
                            )
                            FieldReading(
                                title: L10n.text("Waiting", "Várakozás"),
                                value: Units.formatDuration(model.stats.waitingMillis),
                                ink: ink,
                                centered: true
                            )
                        }
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 1)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 18)
                    InstrumentRule()
                    HStack(alignment: .top, spacing: 8) {
                        FieldReading(
                            title: L10n.text("Altitude", "Magasság"),
                            value: model.altitude.map { Units.formatAltitude($0, model.settings.measurementSystem) } ?? "—",
                            ink: ink,
                            centered: true
                        )
                        FieldReading(
                            title: L10n.text("Bearing", "Irány"),
                            value: model.bearing.map { String(format: "%.0f°", $0) } ?? "—",
                            ink: ink,
                            centered: true
                        )
                        FieldReading(
                            title: L10n.text("Lean", "Dőlés"),
                            value: model.leanAngle.map { String(format: "%.0f°", $0) } ?? "—",
                            ink: ink,
                            centered: true
                        )
                    }
                    .padding(.top, 16)
                    FieldReading(
                        title: L10n.text("Ambient", "Környezet"),
                        value: L10n.text("No sensor", "Nincs érzékelő"),
                        ink: ink,
                        centered: true,
                        quiet: true
                    )
                    .padding(.top, 8)
                    if model.elevation.compactMap(\.gpsAltitude).count >= 2 {
                        InstrumentRule()
                            .padding(.top, 18)
                        ElevationChart(samples: model.elevation, system: model.settings.measurementSystem, accent: accent)
                            .frame(height: chartHeight)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
        }
    }
}

struct ElevationChart: View {
    var samples: [ElevationSample]
    var system: MeasurementSystem
    var accent: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ElevationSeries.hasBaroLine(samples) {
                HStack(spacing: 16) {
                    legend(GtlColor.carmine, dashed: false, L10n.text("GPS altitude", "GPS magasság"))
                    legend(accent, dashed: true, L10n.text("Baro", "Baro"))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if let span = altitudeSpan {
                    VStack {
                        Text(span.high)
                        Spacer(minLength: 0)
                        Text(span.low)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                }
                Canvas { context, size in
                    let plot = CGRect(x: 2, y: 8, width: max(1, size.width - 4), height: max(1, size.height - 16))
                    for fraction in [0.33, 0.66] {
                        var guide = Path()
                        let y = plot.maxY - plot.height * fraction
                        guide.move(to: CGPoint(x: plot.minX, y: y))
                        guide.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(guide, with: .color(Color.primary.opacity(0.08)), lineWidth: 1)
                    }
                    var base = Path()
                    base.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                    base.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    context.stroke(base, with: .color(Color.primary.opacity(0.18)), lineWidth: 1)
                    guard samples.count >= 2 else { return }
                    let scale = ElevationSeries.plotScale(samples)
                    let maxDistance = max(samples.last?.distanceMeters ?? 1, 1)
                    func point(_ sample: ElevationSample, altitude: Double) -> CGPoint {
                        let x = plot.minX + plot.width * sample.distanceMeters / maxDistance
                        let y = plot.maxY - plot.height * scale.yFraction(altitude)
                        return CGPoint(x: x, y: y)
                    }
                    var gps = Path()
                    var started = false
                    var first: CGPoint?
                    var last: CGPoint?
                    for sample in samples {
                        guard let altitude = sample.gpsAltitude else { continue }
                        let p = point(sample, altitude: altitude)
                        if started {
                            gps.addLine(to: p)
                        } else {
                            gps.move(to: p)
                            first = p
                            started = true
                        }
                        last = p
                    }
                    if let first, let last {
                        var fill = Path()
                        fill.addPath(gps)
                        fill.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                        fill.addLine(to: CGPoint(x: first.x, y: plot.maxY))
                        fill.closeSubpath()
                        context.fill(
                            fill,
                            with: .linearGradient(
                                Gradient(colors: [GtlColor.carmine.opacity(scheme == .dark ? 0.42 : 0.24), GtlColor.carmine.opacity(0.02)]),
                                startPoint: CGPoint(x: 0, y: plot.minY),
                                endPoint: CGPoint(x: 0, y: plot.maxY)
                            )
                        )
                    }
                    context.stroke(gps, with: .color(GtlColor.carmine), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let last {
                        let halo = scheme == .dark ? GtlColor.cockpit : GtlColor.paper
                        context.fill(Path(ellipseIn: CGRect(x: last.x - 5.5, y: last.y - 5.5, width: 11, height: 11)), with: .color(halo))
                        context.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)), with: .color(GtlColor.carmine))
                    }
                    if ElevationSeries.hasBaroLine(samples) {
                        var baro = Path()
                        started = false
                        for sample in samples {
                            guard let altitude = sample.baroAltitude else { continue }
                            let p = point(sample, altitude: altitude)
                            if started { baro.addLine(to: p) } else { baro.move(to: p); started = true }
                        }
                        context.stroke(baro, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var altitudeSpan: (low: String, high: String)? {
        let gps = samples.compactMap(\.gpsAltitude)
        guard let low = gps.min(), let high = gps.max(), gps.count >= 2 else { return nil }
        return (Units.formatAltitude(low, system), Units.formatAltitude(high, system))
    }

    private func legend(_ color: Color, dashed: Bool, _ title: String) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let style = dashed
                    ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3])
                    : StrokeStyle(lineWidth: 2.5, lineCap: .round)
                context.stroke(line, with: .color(color), style: style)
            }
            .frame(width: 18, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldReading: View {
    var title: String
    var value: String
    var ink: Color
    var centered: Bool = false
    var quiet: Bool = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 3) {
            Text(value)
                .font(.system(quiet ? .body : .title3, design: .rounded, weight: quiet ? .regular : .medium))
                .monospacedDigit()
                .foregroundStyle(quiet || value == "—" ? Color.secondary : ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

private struct FieldPair: View {
    var leftTitle: String
    var leftValue: String
    var rightTitle: String
    var rightValue: String
    var ink: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            FieldReading(title: leftTitle, value: leftValue, ink: ink)
            FieldReading(title: rightTitle, value: rightValue, ink: ink)
        }
        .padding(.vertical, 12)
    }
}

private struct InstrumentRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }
}

private struct MeasureParts {
    var number: String
    var unit: String

    init(_ formatted: String) {
        if let space = formatted.lastIndex(of: " ") {
            number = String(formatted[..<space])
            unit = String(formatted[formatted.index(after: space)...])
        } else {
            number = formatted
            unit = ""
        }
    }
}

private func instrumentInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? GtlColor.moonCream : GtlColor.nightInk
}

private func liveAccent(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? GtlColor.hudCyan : GtlColor.hudTeal
}

struct CompassTab: View {
    let model: TrackerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let display = CompassHeading.display(
            magneticDegrees: model.headingDegrees ?? 0,
            wantTrue: model.settings.compassTrueNorth,
            declinationDegrees: model.declination
        )
        let reference = display.trueNorth ? "TRUE" : "MAG"
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                modeChip("MAG", selected: !model.settings.compassTrueNorth) {
                    model.updateSettings { $0.compassTrueNorth = false }
                }
                modeChip("TRUE", selected: model.settings.compassTrueNorth) {
                    model.updateSettings { $0.compassTrueNorth = true }
                }
            }
            if display.missingFix {
                Text(L10n.text("No GPS", "Nincs GPS"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CompassRose(heading: display.degrees, reference: reference, dark: scheme == .dark)
            if let accuracy = model.headingAccuracy, CompassHeading.needsFigureEight(accuracy) {
                Text(L10n.text(
                    "Wave the phone in a figure-8 to calibrate the compass",
                    "A kalibráláshoz rajzolj nyolcast a levegőben"
                ))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(GtlColor.amber)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear { model.onTabChange() }
    }

    private func modeChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? GtlColor.hudTeal.opacity(0.85) : Color.primary.opacity(0.08))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compass.\(title)")
    }
}

struct CompassRose: View {
    var heading: Float
    var reference: String
    var dark: Bool

    var body: some View {
        let bezel = dark ? GtlColor.hudCyan : GtlColor.hudTeal
        let cardinal = dark ? GtlColor.moonCream : GtlColor.nightInk
        let shown = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2.15
            var fill = Path()
            fill.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(fill, with: .color(bezel.opacity(0.12)))
            context.stroke(fill, with: .color(bezel), lineWidth: 3)
            func point(_ degrees: Double, _ distance: CGFloat) -> CGPoint {
                let rad = (degrees - Double(shown)) * .pi / 180
                return CGPoint(x: center.x + sin(rad) * distance, y: center.y - cos(rad) * distance)
            }
            for deg in stride(from: 0, to: 360, by: 10) {
                let major = deg % 30 == 0
                var tick = Path()
                tick.move(to: point(Double(deg), radius - (major ? 18 : 10)))
                tick.addLine(to: point(Double(deg), radius - 3))
                let color: Color = deg == 0 ? GtlColor.carmine : Color.secondary
                context.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: major ? 3 : 1.5, lineCap: .round))
            }
            let labels = [(0, "N", GtlColor.carmine), (90, "E", cardinal), (180, "S", cardinal), (270, "W", cardinal)]
            for item in labels {
                let at = point(Double(item.0), radius - 42)
                var label = context
                label.translateBy(x: at.x, y: at.y)
                label.rotate(by: .degrees(Double(item.0) - Double(shown)))
                label.draw(Text(item.1).font(.title2.bold()).foregroundStyle(item.2), at: .zero, anchor: .center)
            }
            var lubber = Path()
            let tip = point(Double(shown), radius - 4)
            let left = point(Double(shown) - 6, radius - 22)
            let right = point(Double(shown) + 6, radius - 22)
            lubber.move(to: tip)
            lubber.addLine(to: left)
            lubber.addLine(to: right)
            lubber.closeSubpath()
            context.fill(lubber, with: .color(GtlColor.carmine))
            var needle = Path()
            needle.move(to: point(Double(shown), 28))
            needle.addLine(to: point(Double(shown), radius - 26))
            context.stroke(needle, with: .color(bezel), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .overlay {
            VStack(spacing: 0) {
                Text(String(format: "%03.0f°", shown))
                    .font(.system(size: 36, weight: .medium, design: .monospaced))
                Text(reference)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(bezel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }
}
