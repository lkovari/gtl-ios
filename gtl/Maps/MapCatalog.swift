import Foundation

struct OsmRegion: Identifiable, Equatable {
    var id: String
    var label: String
    var url: URL
    var countryCode: String
}

enum OsmCatalog {
    private static let base = "https://ftp-stud.hs-esslingen.de/Mirrors/download.mapsforge.org/maps/v5"

    static let regions: [OsmRegion] = [
        region("eu-hungary", "Hungary", "europe/hungary.map", "HU"),
        region("eu-austria", "Austria", "europe/austria.map", "AT"),
        region("eu-slovakia", "Slovakia", "europe/slovakia.map", "SK"),
        region("eu-romania", "Romania", "europe/romania.map", "RO"),
        region("eu-croatia", "Croatia", "europe/croatia.map", "HR"),
        region("eu-slovenia", "Slovenia", "europe/slovenia.map", "SI"),
        region("eu-germany", "Germany", "europe/germany.map", "DE"),
        region("eu-poland", "Poland", "europe/poland.map", "PL"),
        region("eu-czech", "Czech Republic", "europe/czech-republic.map", "CZ"),
        region("eu-italy", "Italy", "europe/italy.map", "IT"),
        region("eu-france", "France", "europe/france.map", "FR"),
        region("eu-spain", "Spain", "europe/spain.map", "ES"),
        region("eu-portugal", "Portugal", "europe/portugal.map", "PT"),
        region("eu-netherlands", "Netherlands", "europe/netherlands.map", "NL"),
        region("eu-belgium", "Belgium", "europe/belgium.map", "BE"),
        region("eu-switzerland", "Switzerland", "europe/switzerland.map", "CH"),
        region("eu-england", "England", "europe/united-kingdom/england.map", "GB"),
        region("eu-scotland", "Scotland", "europe/united-kingdom/scotland.map", "GB"),
        region("eu-wales", "Wales", "europe/united-kingdom/wales.map", "GB"),
        region("eu-ireland", "Ireland and Northern Ireland", "europe/ireland-and-northern-ireland.map", "IE"),
        region("eu-greece", "Greece", "europe/greece.map", "GR"),
        region("eu-sweden", "Sweden", "europe/sweden.map", "SE"),
        region("eu-norway", "Norway", "europe/norway.map", "NO"),
        region("eu-finland", "Finland", "europe/finland.map", "FI"),
        region("eu-denmark", "Denmark", "europe/denmark.map", "DK"),
        region("eu-ukraine", "Ukraine", "europe/ukraine.map", "UA"),
        region("eu-serbia", "Serbia", "europe/serbia.map", "RS"),
        region("eu-bulgaria", "Bulgaria", "europe/bulgaria.map", "BG"),
        region("asia-japan", "Japan", "asia/japan.map", "JP"),
        region("asia-india", "India", "asia/india.map", "IN"),
        region("us-california", "California", "north-america/us/california.map", "US"),
        region("us-new-york", "New York", "north-america/us/new-york.map", "US"),
        region("us-texas", "Texas", "north-america/us/texas.map", "US"),
        region("ca-ontario", "Ontario", "north-america/canada/ontario.map", "CA"),
        region("sa-brazil", "Brazil", "south-america/brazil.map", "BR"),
        region("au-australia", "Australia", "australia-oceania/australia.map", "AU")
    ]

    static let tuhuId = "tuhu"
    static let tuhuURL = URL(string: "https://turistautak.elte.hu/tuhu/tuhu_mapsforge.zip")!
    static let tuhuWebsite = URL(string: "https://turistautak.hu")!

    private static let subnationalTitles: [String: (String, String)] = [
        "eu-england": ("England", "Anglia"),
        "eu-scotland": ("Scotland", "Skócia"),
        "eu-wales": ("Wales", "Wales"),
        "eu-ireland": ("Ireland and Northern Ireland", "Írország és Észak-Írország"),
        "us-california": ("California", "Kalifornia"),
        "us-new-york": ("New York", "New York"),
        "us-texas": ("Texas", "Texas"),
        "ca-ontario": ("Ontario", "Ontario")
    ]

    private static let continents: [(prefixes: [String], en: String, hu: String)] = [
        (["eu-"], "Europe", "Európa"),
        (["asia-"], "Asia", "Ázsia"),
        (["us-", "ca-"], "North America", "Észak-Amerika"),
        (["sa-"], "South America", "Dél-Amerika"),
        (["au-"], "Australia and Oceania", "Ausztrália és Óceánia")
    ]

    static func localizedTitle(_ region: OsmRegion, hungarian: Bool = L10n.hungarian, locale: Locale = .current) -> String {
        if let names = subnationalTitles[region.id] {
            return hungarian ? names.1 : names.0
        }
        return locale.localizedString(forRegionCode: region.countryCode) ?? region.label
    }

    static func groups(hungarian: Bool = L10n.hungarian) -> [OsmRegionGroup] {
        continents.compactMap { continent in
            let members = regions.filter { region in continent.prefixes.contains { region.id.hasPrefix($0) } }
            guard !members.isEmpty else { return nil }
            return OsmRegionGroup(title: hungarian ? continent.hu : continent.en, regions: members)
        }
    }

    private static func region(_ id: String, _ label: String, _ path: String, _ country: String) -> OsmRegion {
        OsmRegion(id: id, label: label, url: URL(string: "\(base)/\(path)")!, countryCode: country)
    }
}

struct OsmRegionGroup: Identifiable {
    var title: String
    var regions: [OsmRegion]
    var id: String { title }
}

struct PendingMapDownload: Identifiable {
    var id: String
    var title: String
    var bytes: Int64
    var url: URL
    var cap: Int64
}

enum DownloadBudget {
    static let maxOsmBytes: Int64 = 5 * 1024 * 1024 * 1024
    static let reserveBytes: Int64 = 64 * 1024 * 1024
    static let maxTuhuDownloadBytes: Int64 = 500 * 1024 * 1024
    static let maxTuhuUnzipBytes: Int64 = 1024 * 1024 * 1024
    static let maxTuhuEntries = 4000

    static func canStart(contentLength: Int64, usableSpace: Int64?, cap: Int64) -> Bool {
        guard let usableSpace else { return false }
        if usableSpace <= reserveBytes { return false }
        if contentLength > cap { return false }
        if contentLength >= 0 && contentLength > usableSpace - reserveBytes { return false }
        return true
    }

    static func canUnpack(uncompressedBytes: Int64, usableSpace: Int64?) -> Bool {
        guard let usableSpace else { return false }
        return uncompressedBytes <= usableSpace - reserveBytes
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
