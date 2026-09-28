import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Bindable var model: TrackerModel
    var body: some View {
        Form {
            Section(L10n.text("Usage", "Használat")) {
                Picker(L10n.text("Usage", "Használat"), selection: Binding(
                    get: { model.settings.usageType },
                    set: { model.setUsage($0) }
                )) {
                    ForEach(UsageType.selectable, id: \.self) { usage in
                        Text(label(usage)).tag(usage)
                    }
                }
                Picker(L10n.text("Units", "Mértékegység"), selection: Binding(
                    get: { model.settings.measurementSystem },
                    set: { value in model.updateSettings { $0.measurementSystem = value } }
                )) {
                    Text("Metric").tag(MeasurementSystem.METRIC)
                    Text("Imperial").tag(MeasurementSystem.IMPERIAL)
                    Text("ICAO").tag(MeasurementSystem.ICAO)
                }
            }
            Section(L10n.text("Appearance", "Megjelenés")) {
                Toggle(L10n.text("Use downloaded map", "Letöltött térkép"), isOn: Binding(
                    get: { model.settings.useOfflineMap },
                    set: { value in model.updateSettings { $0.useOfflineMap = value } }
                ))
                Toggle(L10n.text("Simplify track on map", "Útvonal egyszerűsítése"), isOn: Binding(
                    get: { model.settings.optimizationActive },
                    set: { value in model.updateSettings { $0.optimizationActive = value } }
                ))
                Toggle(L10n.text("Show last logged route", "Utolsó útvonal"), isOn: Binding(
                    get: { model.settings.showLastTrackOnMap },
                    set: { value in model.updateSettings { $0.showLastTrackOnMap = value } }
                ))
                Toggle(L10n.text("Keep whole track", "Teljes útvonal"), isOn: Binding(
                    get: { model.settings.keepWholeTrackOnScreen },
                    set: { value in model.updateSettings { $0.keepWholeTrackOnScreen = value } }
                ))
                Toggle(L10n.text("Show accuracy marker", "Pontosság jelölő"), isOn: Binding(
                    get: { model.settings.showAccuracyMarker },
                    set: { value in model.updateSettings { $0.showAccuracyMarker = value } }
                ))
                Toggle(L10n.text("Show fix cloud", "Pozíciófelhő"), isOn: Binding(
                    get: { model.settings.showFixCloud },
                    set: { value in model.updateSettings { $0.showFixCloud = value } }
                ))
                Toggle(L10n.text("Keep screen on while logging", "Képernyő bekapcsolva naplózás közben"), isOn: Binding(
                    get: { model.settings.keepScreenOnWhileLogging },
                    set: { value in model.updateSettings { $0.keepScreenOnWhileLogging = value } }
                ))
            }
            if model.effectiveOffline {
                OfflineLayerControls(model: model)
            }
            Section(L10n.text("Recording", "Rögzítés")) {
                Toggle(L10n.text("Smooth recorded track", "Simított nyomvonal"), isOn: Binding(
                    get: { model.settings.trackSmoothingEnabled },
                    set: { value in model.updateSettings { $0.trackSmoothingEnabled = value } }
                ))
                Toggle(L10n.text("Hold still when stopped", "Megálláskor tartás"), isOn: Binding(
                    get: { model.settings.stationaryLockEnabled },
                    set: { value in model.updateSettings { $0.stationaryLockEnabled = value } }
                ))
                VStack(alignment: .leading) {
                    Text(L10n.text("Recording density", "Rögzítési sűrűség"))
                    Slider(value: Binding(
                        get: { Double(model.settings.recordingDensityValue) },
                        set: { value in model.updateSettings { $0.recordingDensityValue = Float(value) } }
                    ), in: 0...1)
                }
            }
            if model.altimeterAvailable {
                Section(L10n.text("Barometer", "Barométer")) {
                    Toggle(L10n.text("Auto-calibrate", "Automatikus kalibrálás"), isOn: Binding(
                        get: { model.settings.autoCalibrateBaroEnabled },
                        set: { value in model.updateSettings { $0.autoCalibrateBaroEnabled = value } }
                    ))
                    VStack(alignment: .leading) {
                        Text("QNH \(String(format: "%.1f", model.settings.qnhHpa)) hPa")
                        Slider(value: Binding(
                            get: { Double(model.settings.qnhHpa) },
                            set: { value in model.updateSettings { $0.qnhHpa = Float(value) } }
                        ), in: Double(BaroAltitude.minQnhHpa)...Double(BaroAltitude.maxQnhHpa))
                    }
                    Button(L10n.text("Calibrate", "Kalibrálás")) {
                        if let pressure = model.pressureHpa, let gps = model.altitude {
                            model.updateSettings { $0.baroPressureOffsetHpa = BaroAltitude.offsetHpa(pressureHpa: pressure, gpsMeters: gps, qnhHpa: $0.qnhHpa) }
                        }
                    }
                    Button(L10n.text("Reset", "Visszaállítás")) {
                        model.updateSettings { $0.baroPressureOffsetHpa = 0 }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Settings", "Beállítások"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ usage: UsageType) -> String {
        switch usage {
        case .AIRCRAFT: return L10n.text("Aircraft", "Légijármű")
        case .WATERCRAFT: return L10n.text("Watercraft", "Vízi jármű")
        case .FOUR_WHEELERS: return L10n.text("Car", "Autó")
        case .TWO_WHEELERS: return L10n.text("Motorbike", "Motor")
        case .BICYCLE: return L10n.text("Bicycle", "Kerékpár")
        case .RUNNER: return L10n.text("Run/Hike", "Futás/Túra")
        default: return usage.kmlLabel()
        }
    }
}

struct MapDownloadScreen: View {
    @Bindable var model: TrackerModel
    var body: some View {
        List {
            if let error = model.downloadError {
                Text(error).foregroundStyle(GtlColor.carmine)
            }
            Section("Turistautak.hu") {
                row(id: OsmCatalog.tuhuId, title: "Turistautak.hu", country: "HU") { model.downloadTuhu() }
            }
            Section("OpenStreetMap") {
                ForEach(OsmCatalog.regions) { region in
                    row(id: region.id, title: region.label, country: region.countryCode) { model.download(region) }
                }
            }
        }
        .navigationTitle(L10n.text("Offline maps", "Offline térképek"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(id: String, title: String, country: String, download: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if let fraction = model.downloadFraction[id], fraction < 1 {
                ProgressView(value: fraction)
            }
            HStack {
                if model.downloadedIds.contains(id) {
                    Button(model.settings.selectedMapId == id && model.settings.useOfflineMap ? L10n.text("In use", "Használatban") : L10n.text("Use", "Használat")) {
                        model.useMap(id)
                    }
                    Button(L10n.text("Delete", "Törlés"), role: .destructive) { model.deleteMap(id) }
                } else {
                    Button(L10n.text("Download", "Letöltés"), action: download)
                }
            }
            .buttonStyle(.bordered)
            Text(country).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TracksScreen: View {
    @Bindable var model: TrackerModel
    @State private var selected: Set<Int64> = []
    @State private var sharing = false
    var body: some View {
        List {
            ForEach(model.sessions) { session in
                Button {
                    if selected.contains(session.id) { selected.remove(session.id) } else { selected.insert(session.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(session.id) ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text(sessionTitle(session.startedAt))
                            Text(session.usageType).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Saved tracks", "Mentett útvonalak"))
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.text("Show on map", "Térképen")) {
                    if let id = selected.first { model.showSession(id) }
                }
                .disabled(selected.count != 1)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("GPX") { model.share(ids: Array(selected), kmz: false) }.disabled(selected.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("KMZ") { model.share(ids: Array(selected), kmz: true) }.disabled(selected.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(L10n.text("Delete", "Törlés"), role: .destructive) { model.deleteSessions(selected); selected.removeAll() }
                    .disabled(selected.isEmpty)
            }
        }
        .alert(
            L10n.text("Track saved", "Útvonal mentve"),
            isPresented: Binding(get: { model.exportNotice != nil }, set: { if !$0 { model.exportNotice = nil } })
        ) {
            Button(L10n.text("Share", "Megosztás")) { sharing = true }
            Button(L10n.text("OK", "Rendben"), role: .cancel) {}
        } message: {
            Text(model.exportNotice ?? "")
        }
        .sheet(isPresented: $sharing) {
            if let url = model.pendingShare { ShareSheet(url: url) }
        }
    }

    private func sessionTitle(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct HelpScreen: View {
    var model: TrackerModel
    @State private var expanded = "usage"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                section(L10n.text("Usage", "Használati mód"), id: "usage") {
                    Text(L10n.text(
                        "Allow location when asked. GPS and Compass update while this screen is open. Tap Start to record a route into the database on this phone, draw it on the Map, and fill the Route totals. Tap Stop to end the session. Menu → Saved tracks to delete a route, show it on the map, or share KMZ or GPX. Settings picks usage (motorbike is the default), units, and whether the last track stays on the map. Menu → Download offline map for OSM regions or Turistautak (Hungary). Nothing is uploaded.",
                        "A helyhozzáférést az első kérdésnél engedélyezd. A GPS és az iránytű a képernyőn él. Az Indít a telefon adatbázisába rögzíti az útvonalat, kirajzolja a Térképen, és kitölti az Útvonal összesítőket. A Leállít bezárja a munkamenetet. Menü → Mentett útvonalak: törlés, megjelenítés, vagy KMZ / GPX. A Beállításokban a használat (alapból motor), a mértékegység, és hogy maradjon-e az utolsó track. Menü → Offline térkép: OSM-régió vagy Turistautak (Magyarország). Semmi nem kerül fel szerverre."
                    ))
                }
                section(L10n.text("Settings", "Beállítások"), id: "settings") {
                    Text(L10n.text(
                        "Usage writes a preset for units, smoothing, density, and map simplify. Aircraft and watercraft default to ICAO; the others default to metric. You can change any control afterwards. OSM and Turistautak layer switches are on the map layers button, and the same switches are in Settings while that map is in use. The barometer section appears only if this phone has a pressure sensor. Apple Maps is standard, satellite, or hybrid.",
                        "A használat előbeállítást ír a mértékegységre, a simításra, a sűrűségre és a térképi egyszerűsítésre. Repülőnél és hajónál az alap az ICAO, a többinél a metrikus. Utána bármelyik kapcsoló módosítható. Az OSM és a Turistautak rétegek a térkép réteg gombján vannak, és ugyanazok a Beállításokban, amíg az a térkép van használatban. A barométer csak akkor látszik, ha van nyomásszenzor. Az Apple térkép standard, műhold vagy hibrid."
                    ))
                }
                section(L10n.text("Track logging", "Nyomvonal rögzítés"), id: "logging") {
                    Text(L10n.text(
                        "Kalman smooths stored points when Smooth recorded track is on. Simplify only thins the line drawn on the map. The stored route and shared KMZ or GPX keep every accepted point. Smart density uses speed bands. Run/Hike and bicycle keep points closer together. Recording quality uses horizontal accuracy. Fixes older than 10 seconds are dropped.",
                        "A Kalman a letárolt pontokat simítja, ha a Rögzített útvonal simítása be van. Az egyszerűsítés csak a térképen rajzolt vonalat ritkítja. A tárolt útvonal és a megosztott KMZ vagy GPX minden elfogadott pontot megtart. Az okos sűrűség sebességsávokat használ. Futásnál és kerékpárnál sűrűbbek a pontok. A rögzítés a vízszintes pontosságot használja. A 10 másodpercnél régebbi fixek kiesnek."
                    ))
                }
                section("GPS", id: "gps") {
                    Text(L10n.text(
                        "Latitude, longitude, accuracy, course, speed, GPS altitude, and barometric altitude when a pressure sensor exists. Logging status is on the Route tab. There is no ambient temperature sensor, so temperature is not stored.",
                        "Szélesség, hosszúság, pontosság, irány, sebesség, GPS-magasság, és barometrikus magasság, ha van nyomásszenzor. A naplózás állapota az Útvonal fülön van. Nincs hőmérséklet-szenzor, ezért a hőmérséklet nem kerül tárolásra."
                    ))
                }
                section(L10n.text("Route", "Útvonal"), id: "route") {
                    Text(L10n.text(
                        "Session totals after Start: elapsed time, odometer, time moving, time waiting, altitude, bearing, speed, and a GPS elevation profile. A dashed line is barometric altitude when pressure samples exist. Speed is 0 while idle.",
                        "Indítás utáni összesítő: eltelt idő, számláló, mozgásban töltött idő, várakozás, magasság, irányszög, sebesség, és GPS magassági profil. A szaggatott vonal a barometrikus magasság, ha van nyomásminta. Idle-ben a sebesség 0."
                    ))
                }
                section(L10n.text("Map", "Térkép"), id: "map") {
                    Text(L10n.text(
                        "The map centers on you when a fix exists. Idle, you can pan away. After Start it follows you and draws the track. The HUD shows large speed, the unit from Settings, and accuracy in metres. While logging it also shows odometer, elapsed time, and REC. It is hidden when a saved track is on the map and you are not logging. Altitude is not on the HUD. Apple Maps offers standard, satellite, and hybrid. There is no separate terrain raster style. A downloaded OSM or Turistautak map replaces Apple Maps while that file is in use.",
                        "A térkép a fixre centrál, ha van. Idle-ben elhúzható. Indítás után követ, és kirajzolja a nyomvonalat. A HUD a nagy sebességet, a beállított mértékegységet és a pontosságot mutatja méterben. Naplózáskor az út, az eltelt idő és a REC is látszik. Mentett tracknél, ha nem naplózol, a HUD rejtve van. A HUD nem mutat magasságot. Az Apple térkép standard, műhold vagy hibrid. Külön terep-raszter nincs. A letöltött OSM vagy Turistautak térkép lecseréli az Apple térképet, amíg az a fájl van használatban."
                    ))
                }
                section(L10n.text("OSM map options", "OSM térkép opciók"), id: "osm") {
                    Text(L10n.text(
                        "These switches are on the map layers button and in Settings when a downloaded OSM region is on Map. Buildings, POI, public transport, cycleways, and parks. Terrain relief stays off unless elevation files sit next to the map. Official downloads do not include hillshade.",
                        "Ezek a kapcsolók a térkép réteg gombján és a Beállításokban vannak, ha egy OSM-régió van a Térképen. Épületek, POI, tömegközlekedés, kerékpárutak és parkok. A domborzat kikapcsolva marad, amíg nincsenek magasságfájlok a térkép mellett. A hivatalos letöltésben nincs domborzatárnyékolás."
                    ))
                }
                section(L10n.text("Turistautak options", "Turistautak opciók"), id: "tuhu") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.downloadedIds.contains(OsmCatalog.tuhuId) {
                            Text(L10n.text("The Turistautak map is on this phone.", "A Turistautak térkép a telefonon van."))
                        }
                        Text(L10n.text(
                            "Hungary only. This is a map from Turistautak.hu, not an OSM country download. Trail blazes, paths, contours, minor contours, hiking POI, protected areas, urban POI, and relief apply only while that map is on Map.",
                            "Csak Magyarország. Ez a Turistautak.hu térképe, nem OSM-országletöltés. A jelzések, utak, szintvonalak, mellékszintvonalak, túra POI, védett területek, városi POI és a domborzat csak akkor érvényes, ha ez a térkép van a Térképen."
                        ))
                        Link(L10n.text("Turistautak.hu website", "Turistautak.hu weboldal"), destination: OsmCatalog.tuhuWebsite)
                            .foregroundStyle(GtlColor.titleMagenta)
                    }
                }
                section(L10n.text("Compass", "Iránytű"), id: "compass") {
                    Text(L10n.text(
                        "MAG is magnetic north. TRUE is geographic north: magnetic heading plus declination from the last GPS fix. Switch them on this tab. TRUE needs a GPS fix; without one the dial stays MAG and shows No GPS. If the compass is inaccurate, the tab asks you to wave the phone in a figure-8 so the sensor can calibrate. Works without Start.",
                        "A MAG a mágneses észak. A TRUE a földrajzi észak: a mágneses irányszög plusz a legutóbbi GPS-fix deklinációja. Ezen a fülön váltható. A TRUE-hoz GPS-fix kell; anélkül a számlap MAG marad, és Nincs GPS látszik. Ha az iránytű pontatlan, a fül arra kér, hogy a kalibráláshoz rajzolj nyolcast a levegőben. Indítás nélkül is működik."
                    ))
                }
                section(L10n.text("Sharing KMZ and GPX", "KMZ és GPX megosztás"), id: "share") {
                    Text(L10n.text(
                        "Saved tracks → select sessions → GPX or KMZ. The file is saved in the Files app under On My iPhone → GPS Track Logger → Exports, and a share sheet can copy it elsewhere. KMZ is KML plus start, pause, and stop icons. GPX 1.1 has one track per session, with latitude, longitude, GPS elevation, and UTC time. Several sessions become one file.",
                        "Mentett útvonalak → kijelölés → GPX vagy KMZ. A fájl a Fájlok appban van: A(z) iPhone-omon → GPS Track Logger → Exports, és a megosztó lapról máshova is másolható. A KMZ KML, plusz indulás, szünet és megállás ikon. A GPX 1.1 munkamenetenként egy track: szélesség, hosszúság, GPS-magasság és UTC idő. Több munkamenet egy fájlba kerül."
                    ))
                }
                section(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), id: "privacy") {
                    Link("lkovari.github.io", destination: URL(string: "https://lkovari.github.io/KLHome/assets/bigfiles/gtl-privacy-policy.html")!)
                        .foregroundStyle(GtlColor.titleMagenta)
                }
                section(L10n.text("A stored trackpoint", "Egy tárolt pont"), id: "point") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "One GPS fix in the database.",
                            "Egy GPS-fix az adatbázisban."
                        ))
                        .foregroundStyle(.secondary)
                        TrackpointTable()
                    }
                }
            }
            .padding(16)
        }
        .background { GtlBackground() }
        .navigationTitle(L10n.text("Help", "Súgó"))
    }

    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        AccordionCard(title: title, expanded: expanded == id) {
            expanded = expanded == id ? "" : id
        } content: {
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AboutScreen: View {
    @Bindable var model: TrackerModel
    @State private var expanded = "app"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                AccordionCard(title: L10n.text("App info", "Alkalmazás adatai"), expanded: expanded == "app") {
                    expanded = expanded == "app" ? "" : "app"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2.0.15  ·  com.lkovari.mobile.apps.gtl")
                            .onTapGesture { model.tapVersion() }
                        Text("\(L10n.text("Device", "Készülék")): \(UIDevice.current.name)")
                    }
                }
                AccordionCard(title: L10n.text("Local GPS track logger", "Helyi GPS útvonalnapló"), expanded: expanded == "logger") {
                    expanded = expanded == "logger" ? "" : "logger"
                } content: {
                    Text(L10n.text(
                        "No account, no ads, no IMEI, no remote tracking.",
                        "Nincs fiók, reklám, IMEI vagy távoli követés."
                    ))
                }
                AccordionCard(title: "OSM. OpenStreetMap", expanded: expanded == "osm") {
                    expanded = expanded == "osm" ? "" : "osm"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "The Map tab can show OpenStreetMap data from a file you download on the phone. Map data © OpenStreetMap contributors, licensed under the Open Database License (ODbL).",
                            "A Térkép fül OpenStreetMap adatot mutathat egy telefonra letöltött fájlból. Térképadat © OpenStreetMap közreműködők, Open Database License (ODbL) alatt."
                        ))
                        aboutLink(L10n.text("OpenStreetMap website", "OpenStreetMap weboldal"), "https://www.openstreetmap.org")
                        aboutLink(L10n.text("OpenStreetMap copyright", "OpenStreetMap szerzői jog"), "https://www.openstreetmap.org/copyright")
                    }
                }
                AccordionCard(title: "TUHU. Turistautak.hu", expanded: expanded == "tuhu") {
                    expanded = expanded == "tuhu" ? "" : "tuhu"
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(
                            "After you download the Turistautak map, Map can show Hungarian hiking waymarks and contours. Map data from Turistautak.hu.",
                            "A Turistautak térkép letöltése után a Térkép magyar turistajelzéseket és szintvonalat tud mutatni. Térképadat: Turistautak.hu."
                        ))
                        aboutLink(L10n.text("Turistautak.hu website", "Turistautak.hu weboldal"), "https://turistautak.hu")
                    }
                }
                AccordionCard(title: L10n.text("Original repository", "Eredeti tároló"), expanded: expanded == "repo") {
                    expanded = expanded == "repo" ? "" : "repo"
                } content: {
                    aboutLink("https://bitbucket.org/laszlokovary/gtl-e/src/master/", "https://bitbucket.org/laszlokovary/gtl-e/src/master/")
                }
                AccordionCard(title: L10n.text("Copyright", "Szerzői jog"), expanded: expanded == "copyright") {
                    expanded = expanded == "copyright" ? "" : "copyright"
                } content: {
                    Text("Copyright © 2014 - 2026 by László Kővári")
                        .accessibilityIdentifier("about.author")
                }
            }
            .padding(16)
        }
        .background { GtlBackground() }
        .navigationTitle(L10n.text("About", "Névjegy"))
    }

    private func aboutLink(_ label: String, _ url: String) -> some View {
        Link(label, destination: URL(string: url)!)
            .foregroundStyle(GtlColor.titleMagenta)
    }
}

private struct TrackpointTable: View {
    private var rows: [(String, String)] {
        [
            ("id", L10n.text("primary key", "elsődleges kulcs")),
            ("sessionId", L10n.text("which track", "melyik útvonal")),
            ("timestamp", L10n.text("time (epoch ms)", "idő (epoch ms)")),
            ("latitude / longitude / altitude", L10n.text("location", "hely")),
            ("speed", "m/s"),
            ("bearing", L10n.text("heading °", "irányszög °")),
            ("accuracy", L10n.text("GPS accuracy m", "GPS pontosság m")),
            ("baroAltitude", L10n.text("metres from the barometer when this phone has a pressure sensor", "méter a barométerből, ha van nyomásszenzor")),
            ("pressureHpa", L10n.text("raw hPa, or empty", "nyers hPa, vagy üres")),
            ("accelX / accelY / accelZ", L10n.text("acceleration", "gyorsulás")),
            ("leanAngle", L10n.text("lean °", "dőlés °")),
            ("usageType", L10n.text("usage at this fix", "használat ennél a fixnél")),
            ("isPlacemark", L10n.text("true = START / PAUSE / STOP icon in the KMZ", "igaz = START / PAUSE / STOP ikon a KMZ-ben")),
            ("eventKind", "START, MOVE, PAUSE, STOP")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().opacity(0.35)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(row.0)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(GtlColor.hudCyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, 10)
        .background(GtlColor.cockpitPanel)
        .foregroundStyle(GtlColor.moonCream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AccordionCard<Content: View>: View {
    var title: String
    var expanded: Bool
    var onToggle: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                content()
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme == .dark ? GtlColor.cockpitPanel : Color.white.opacity(0.94))
        .foregroundStyle(scheme == .dark ? GtlColor.moonCream : GtlColor.nightInk)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct LocationSettingsScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.text("Location access is controlled in Settings.", "A helyhozzáférést a Beállításokban lehet kezelni."))
            Button(L10n.text("Open Settings", "Beállítások megnyitása")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(GtlPrimaryButton(color: GtlColor.hudTeal))
            .padding()
        }
        .navigationTitle(L10n.text("Location settings", "Helyzet beállítások"))
    }
}

struct ErrorLogScreen: View {
    @State private var text = ErrorLogStore.text()
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? L10n.text("No errors", "Nincs hiba") : text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(L10n.text("Error log", "Hibanapló"))
        .toolbar {
            Button(L10n.text("Clear", "Törlés")) {
                ErrorLogStore.clear()
                text = ""
            }
        }
    }
}
