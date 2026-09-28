import Foundation

struct OsmRegion: Identifiable, Equatable {
    var id: String
    var label: String
    var url: URL
    var countryCode: String
}

enum OsmCatalog {
    private static let base = "https://download.mapsforge.org/maps/v5"

    static let regions: [OsmRegion] = [
        region("eu-hungary", "EU Hungary", "europe/hungary.map", "HU"),
        region("eu-austria", "EU Austria", "europe/austria.map", "AT"),
        region("eu-slovakia", "EU Slovakia", "europe/slovakia.map", "SK"),
        region("eu-romania", "EU Romania", "europe/romania.map", "RO"),
        region("eu-croatia", "EU Croatia", "europe/croatia.map", "HR"),
        region("eu-slovenia", "EU Slovenia", "europe/slovenia.map", "SI"),
        region("eu-germany", "EU Germany", "europe/germany.map", "DE"),
        region("eu-poland", "EU Poland", "europe/poland.map", "PL"),
        region("eu-czech", "EU Czech Republic", "europe/czech_republic.map", "CZ"),
        region("eu-italy", "EU Italy", "europe/italy.map", "IT"),
        region("eu-france", "EU France", "europe/france.map", "FR"),
        region("eu-spain", "EU Spain", "europe/spain.map", "ES"),
        region("eu-portugal", "EU Portugal", "europe/portugal.map", "PT"),
        region("eu-netherlands", "EU Netherlands", "europe/netherlands.map", "NL"),
        region("eu-belgium", "EU Belgium", "europe/belgium.map", "BE"),
        region("eu-switzerland", "EU Switzerland", "europe/switzerland.map", "CH"),
        region("eu-england", "EU England", "europe/great_britain/england.map", "GB"),
        region("eu-scotland", "EU Scotland", "europe/great_britain/scotland.map", "GB"),
        region("eu-wales", "EU Wales", "europe/great_britain/wales.map", "GB"),
        region("eu-ireland", "EU Ireland", "europe/ireland.map", "IE"),
        region("eu-greece", "EU Greece", "europe/greece.map", "GR"),
        region("eu-sweden", "EU Sweden", "europe/sweden.map", "SE"),
        region("eu-norway", "EU Norway", "europe/norway.map", "NO"),
        region("eu-finland", "EU Finland", "europe/finland.map", "FI"),
        region("eu-denmark", "EU Denmark", "europe/denmark.map", "DK"),
        region("eu-ukraine", "EU Ukraine", "europe/ukraine.map", "UA"),
        region("eu-serbia", "EU Serbia", "europe/serbia.map", "RS"),
        region("eu-bulgaria", "EU Bulgaria", "europe/bulgaria.map", "BG"),
        region("asia-japan", "Japan", "asia/japan.map", "JP"),
        region("asia-india", "India", "asia/india.map", "IN"),
        region("us-california", "US California", "north-america/united-states/california.map", "US"),
        region("us-new-york", "US New York", "north-america/united-states/new-york.map", "US"),
        region("us-texas", "US Texas", "north-america/united-states/texas.map", "US"),
        region("ca-ontario", "CA Ontario", "north-america/canada/ontario.map", "CA"),
        region("sa-brazil", "Brazil", "south-america/brazil.map", "BR"),
        region("au-australia", "Australia", "australia-oceania/australia.map", "AU")
    ]

    static let tuhuId = "tuhu"
    static let tuhuURL = URL(string: "https://turistautak.elte.hu/tuhu/tuhu_mapsforge.zip")!
    static let tuhuWebsite = URL(string: "https://turistautak.hu")!

    private static func region(_ id: String, _ label: String, _ path: String, _ country: String) -> OsmRegion {
        OsmRegion(id: id, label: label, url: URL(string: "\(base)/\(path)")!, countryCode: country)
    }
}

struct PendingMapDownload: Identifiable {
    var id: String
    var title: String
    var bytes: Int64
    var url: URL
    var cap: Int64
}

enum DownloadBudget {
    static let maxOsmBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let reserveBytes: Int64 = 64 * 1024 * 1024
    static let maxTuhuDownloadBytes: Int64 = 500 * 1024 * 1024
    static let maxTuhuUnzipBytes: Int64 = 1024 * 1024 * 1024
    static let maxTuhuEntries = 4000

    static func canStart(contentLength: Int64, usableSpace: Int64, cap: Int64) -> Bool {
        if usableSpace <= reserveBytes { return false }
        if contentLength > cap { return false }
        if contentLength >= 0 && contentLength > usableSpace - reserveBytes { return false }
        return true
    }

    static func tuhuURLAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.query == nil else {
            return false
        }
        return url.host?.lowercased() == "turistautak.elte.hu" && url.path == "/tuhu/tuhu_mapsforge.zip"
    }
}

enum MapPaths {
    static func mapsDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("maps", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: dir.path)
        excludeFromBackup(dir)
        return dir
    }

    static func mapFile(id: String) throws -> URL {
        try mapsDirectory().appendingPathComponent("\(id).map")
    }

    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}
