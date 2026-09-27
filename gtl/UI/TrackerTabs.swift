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
                    case .gps: GpsTab(model: model)
                    case .route: RouteTab(model: model)
                    case .map: MapTab(model: model)
                    case .compass: CompassTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                tabBar
            }
            .background { GtlBackground() }
            .navigationDestination(for: String.self) { route in
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
        }
        .onChange(of: model.tab) { _, _ in model.onTabChange() }
        .onAppear { model.onTabChange() }
        .onChange(of: model.showErrorLog) { _, show in
            if show {
                path.append("diagnostics")
                model.showErrorLog = false
            }
        }
    }

    private var header: some View {
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

struct GpsTab: View {
    let model: TrackerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metric(L10n.text("Latitude", "Szélesség"), model.latitude.map { String(format: "%.6f", $0) } ?? "—")
                metric(L10n.text("Longitude", "Hosszúság"), model.longitude.map { String(format: "%.6f", $0) } ?? "—")
                metric(L10n.text("Accuracy", "Pontosság"), model.accuracy.map { String(format: "%.0f m", $0) } ?? "—")
                metric(L10n.text("GPS / Baro", "GPS / Baro"), altitudeLine)
                metric(L10n.text("Status", "Állapot"), statusLine)
                Text(L10n.text(
                    "The chip uses GPS, Galileo, BeiDou, GLONASS, and QZSS. iOS does not tell apps which satellites are in view, so there is no sky plot or SNR.",
                    "A chip GPS-t, Galileót, BeiDou-t, GLONASS-t és QZSS-t használ. Az iOS nem mondja meg az appnak, melyik műhold látszik, ezért nincs égboltkép és SNR."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if model.settings.showFixCloud {
                    metric("n", "\(model.fixCloud.stats.sampleCount)")
                    metric("RMS", model.fixCloud.stats.rmsMeters.map { String(format: "%.1f m", $0) } ?? "—")
                    metric("CEP95", model.fixCloud.stats.cep95Meters.map { String(format: "%.1f m", $0) } ?? "—")
                }
            }
            .padding()
        }
    }

    private var altitudeLine: String {
        let gps = model.altitude.map { Units.formatAltitude($0, model.settings.measurementSystem) } ?? "—"
        let baro = model.baroAltitude.map { Units.formatAltitude($0, model.settings.measurementSystem) } ?? "—"
        return "\(gps) / \(baro)"
    }

    private var statusLine: String {
        if model.logging && model.poorGps { return L10n.text("GPS quality is too low", "A GPS minősége túl alacsony") }
        if model.logging { return L10n.text("Logging", "Naplózás") }
        if model.latitude == nil { return L10n.text("Waiting for GPS", "Várakozás a GPS-re") }
        return L10n.text("Idle", "Üresjárat")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}

struct RouteTab: View {
    let model: TrackerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metric(L10n.text("Elapsed", "Eltelt"), Units.formatDuration(model.stats.elapsedMillis))
                metric(L10n.text("Odometer", "Számláló"), Units.formatDistance(model.stats.odometerMeters, model.settings.measurementSystem))
                metric(L10n.text("Time moving", "Mozgásban"), Units.formatDuration(model.stats.movingMillis))
                metric(L10n.text("Waiting", "Várakozás"), Units.formatDuration(model.stats.waitingMillis))
                metric(L10n.text("Speed", "Sebesség"), Units.formatSpeed(RouteTabSpeeds.instantMps(logging: model.logging, liveSpeedMps: model.speedMps) ?? 0, model.settings.measurementSystem))
                metric(L10n.text("Average", "Átlag"), Units.formatSpeed(RouteTabSpeeds.averageMps(logging: model.logging, sessionAverageMps: model.stats.averageSpeedMps), model.settings.measurementSystem))
                metric(L10n.text("Altitude", "Magasság"), model.altitude.map { Units.formatAltitude($0, model.settings.measurementSystem) } ?? "—")
                metric(L10n.text("Bearing", "Irány"), model.bearing.map { String(format: "%.0f°", $0) } ?? "—")
                metric(L10n.text("Lean", "Dőlés"), model.leanAngle.map { String(format: "%.0f°", $0) } ?? "—")
                metric(L10n.text("Ambient", "Környezet"), L10n.text("No sensor", "Nincs érzékelő"))
                ElevationChart(samples: model.elevation)
                    .frame(height: 140)
            }
            .padding()
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}

struct ElevationChart: View {
    var samples: [ElevationSample]
    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }
            let scale = ElevationSeries.plotScale(samples)
            let maxDistance = max(samples.last?.distanceMeters ?? 1, 1)
            func point(_ sample: ElevationSample, altitude: Double) -> CGPoint {
                let x = size.width * sample.distanceMeters / maxDistance
                let y = size.height * (1 - scale.yFraction(altitude))
                return CGPoint(x: x, y: y)
            }
            var gps = Path()
            var started = false
            for sample in samples {
                guard let altitude = sample.gpsAltitude else { continue }
                let p = point(sample, altitude: altitude)
                if started { gps.addLine(to: p) } else { gps.move(to: p); started = true }
            }
            context.stroke(gps, with: .color(GtlColor.carmine), lineWidth: 2)
            if ElevationSeries.hasBaroLine(samples) {
                var baro = Path()
                started = false
                for sample in samples {
                    guard let altitude = sample.baroAltitude else { continue }
                    let p = point(sample, altitude: altitude)
                    if started { baro.addLine(to: p) } else { baro.move(to: p); started = true }
                }
                context.stroke(baro, with: .color(GtlColor.hudTeal), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .background(GtlColor.paper.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
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
