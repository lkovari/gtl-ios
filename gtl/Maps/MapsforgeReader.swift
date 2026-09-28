import Foundation

struct IndexedPlace: Sendable {
    var name: String
    var folded: String
    var kind: String
    var latitude: Double
    var longitude: Double
}

struct MapFeature {
    enum Geometry {
        case point(latitude: Double, longitude: Double)
        case line([(latitude: Double, longitude: Double)])
    }

    var geometry: Geometry
    var category: String
    var name: String?
    var tags: [String: String]
}

struct MapsforgeHeader {
    var bounds: LatLonBounds
    var startLatitude: Double
    var startLongitude: Double
    var startZoom: Int
    var tileSize: Int
    var poiTags: [String]
    var wayTags: [String]
    var subFiles: [MapsforgeSubFile]
    var debug: Bool
    var fileVersion: Int
}

struct MapsforgeSubFile {
    var baseZoom: Int
    var minZoom: Int
    var maxZoom: Int
    var startAddress: Int64
    var indexStartAddress: Int64
    var subFileSize: Int64
}

private final class MapFileCache: @unchecked Sendable {
    private var key = ""
    private var data: Data?
    private let lock = NSLock()

    func data(at url: URL) -> Data? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let next = "\(url.path)#\(size)"
        lock.lock()
        defer { lock.unlock() }
        if key == next, let data { return data }
        guard let loaded = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        key = next
        data = loaded
        return loaded
    }
}

enum MapsforgeReader {
    private static let mapFileCache = MapFileCache()
    static func header(of url: URL) -> MapsforgeHeader? {
        guard OsmMapFile.isReadable(url), let data = mapFileCache.data(at: url) else {
            return nil
        }
        return parseHeader(data)
    }

    static func namedPlaces(url: URL, limit: Int, isCancelled: () -> Bool = { false }) -> [IndexedPlace] {
        guard let data = mapFileCache.data(at: url), let header = parseHeader(data) else {
            return []
        }
        var rows: [IndexedPlace] = []
        var seen = Set<String>()
        let subs = header.subFiles.sorted { $0.baseZoom < $1.baseZoom }
        let cursor = ByteCursor(data)
        for sub in subs {
            if rows.count >= limit || isCancelled() { break }
            let grid = tileGrid(header.bounds, sub.baseZoom)
            let queryZoom = sub.maxZoom
            for row in 0..<grid.height {
                if rows.count >= limit || isCancelled() { break }
                for col in 0..<grid.width {
                    if rows.count >= limit || isCancelled() { break }
                    let block = row * grid.width + col
                    let entryPos = sub.indexStartAddress + Int64(block * 5)
                    guard entryPos >= 0, entryPos + 5 <= Int64(data.count) else { continue }
                    cursor.offset = Int(entryPos)
                    let first = readFive(cursor)
                    let offset = first & 0x7fffffffff
                    let next: Int64
                    if block + 1 == grid.width * grid.height {
                        next = sub.subFileSize
                    } else {
                        guard entryPos + 10 <= Int64(data.count) else { continue }
                        next = readFive(cursor) & 0x7fffffffff
                    }
                    if offset <= 0 || offset >= next || offset > sub.subFileSize { continue }
                    let tileStart = sub.startAddress + offset
                    let tileEnd = min(sub.startAddress + next, sub.startAddress + sub.subFileSize)
                    guard tileStart < tileEnd, tileEnd <= Int64(data.count) else { continue }
                    cursor.offset = Int(tileStart)
                    if header.debug { cursor.offset += 32 }
                    let origin = tileOrigin(x: grid.left + col, y: grid.top + row, zoom: sub.baseZoom)
                    guard let decoded = decodeTile(
                        cursor,
                        end: Int(tileEnd),
                        header: header,
                        sub: sub,
                        queryZoom: queryZoom,
                        originLat: origin.lat,
                        originLon: origin.lon,
                        limit: 80_000,
                        poiLimit: 80_000
                    ) else { continue }
                    for feature in decoded {
                        guard rows.count < limit else { break }
                        guard let point = searchAnchor(feature), let record = MapSearch.record(tags: feature.tags) else { continue }
                        let key = "\(record.kind.rawValue)|\(MapSearch.fold(record.displayName))|\(Int((point.0 / 0.0004).rounded()))|\(Int((point.1 / 0.0004).rounded()))"
                        guard seen.insert(key).inserted else { continue }
                        rows.append(IndexedPlace(
                            name: record.displayName,
                            folded: record.foldedAliases.joined(separator: " "),
                            kind: record.kind.rawValue,
                            latitude: point.0,
                            longitude: point.1
                        ))
                    }
                }
            }
        }
        return rows
    }

    static func searchCandidates(_ features: [MapFeature]) -> [MapSearchCandidate] {
        var rows: [MapSearchCandidate] = []
        var seen = Set<String>()
        for feature in features {
            let record = MapSearch.record(tags: feature.tags)
            let fallback = feature.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let display = record?.displayName ?? fallback
            guard display.count >= 2, let point = searchAnchor(feature) else { continue }
            let kind = record?.kind ?? .Place
            let key = "\(kind.rawValue)|\(MapSearch.fold(display))|\(Int((point.0 / 0.0004).rounded()))|\(Int((point.1 / 0.0004).rounded()))"
            guard seen.insert(key).inserted else { continue }
            rows.append(MapSearchCandidate(
                name: display,
                nameFold: MapSearch.fold(display),
                kind: kind,
                latitude: point.0,
                longitude: point.1
            ))
        }
        return rows
    }

    private static func searchAnchor(_ feature: MapFeature) -> (Double, Double)? {
        switch feature.geometry {
        case .point(let latitude, let longitude):
            return (latitude, longitude)
        case .line(let line):
            guard line.count >= 2 else { return nil }
            let closed = abs(line[0].latitude - line[line.count - 1].latitude) < 0.00002
                && abs(line[0].longitude - line[line.count - 1].longitude) < 0.00002
            if closed {
                let latitude = line.reduce(0.0) { $0 + $1.latitude } / Double(line.count)
                let longitude = line.reduce(0.0) { $0 + $1.longitude } / Double(line.count)
                return (latitude, longitude)
            }
            let mid = line[line.count / 2]
            return (mid.latitude, mid.longitude)
        }
    }

    static func features(
        url: URL,
        bounds: LatLonBounds,
        zoom: Int,
        limit: Int,
        poiLimit: Int = 28,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [MapFeature] {
        guard let data = mapFileCache.data(at: url), let header = parseHeader(data) else {
            return []
        }
        let queryZoom = min(max(zoom, 0), 22)
        guard let sub = chooseSubfile(header, bounds: bounds, queryZoom: queryZoom) else { return [] }
        let grid = tileGrid(header.bounds, sub.baseZoom)
        let query = queryTiles(bounds, zoom: sub.baseZoom, grid: grid)
        guard !query.isEmpty else { return [] }
        let overview = queryZoom <= 11 || query.count > 36
        let cap = overview ? min(limit, 2400) : limit
        let share = cap / max(query.count, 1)
        let floor = query.count <= 12 ? min(cap, overview ? 160 : 400) : (overview ? 20 : 70)
        let perTile = min(overview ? 180 : 700, max(share, floor))
        let poisPerTile = overview ? min(poiLimit, 4) : poiLimit
        var features: [MapFeature] = []
        let cursor = ByteCursor(data)
        for tile in query {
            if features.count >= cap || isCancelled() { break }
            let block = tile.row * grid.width + tile.col
            let entryPos = sub.indexStartAddress + Int64(block * 5)
            guard entryPos >= 0, entryPos + 5 <= Int64(data.count) else { continue }
            cursor.offset = Int(entryPos)
            let first = readFive(cursor)
            let offset = first & 0x7fffffffff
            let next: Int64
            if block + 1 == grid.width * grid.height {
                next = sub.subFileSize
            } else {
                guard entryPos + 10 <= Int64(data.count) else { continue }
                next = readFive(cursor) & 0x7fffffffff
            }
            if offset <= 0 || offset >= next || offset > sub.subFileSize { continue }
            let tileStart = sub.startAddress + offset
            let tileEnd = min(sub.startAddress + next, sub.startAddress + sub.subFileSize)
            guard tileStart < tileEnd, tileEnd <= Int64(data.count) else { continue }
            cursor.offset = Int(tileStart)
            if header.debug { cursor.offset += 32 }
            let origin = tileOrigin(x: grid.left + tile.col, y: grid.top + tile.row, zoom: sub.baseZoom)
            if let decoded = decodeTile(
                cursor,
                end: Int(tileEnd),
                header: header,
                sub: sub,
                queryZoom: queryZoom,
                originLat: origin.lat,
                originLon: origin.lon,
                limit: perTile,
                poiLimit: poisPerTile
            ) {
                features.append(contentsOf: decoded)
            }
        }
        return features
    }

    private static func chooseSubfile(_ header: MapsforgeHeader, bounds: LatLonBounds, queryZoom: Int) -> MapsforgeSubFile? {
        let subs = header.subFiles
        guard !subs.isEmpty else { return nil }
        let containing = subs.filter { queryZoom >= $0.minZoom && queryZoom <= $0.maxZoom }
        let pool = containing.isEmpty ? subs : containing
        let fitted = pool.filter { $0.baseZoom <= queryZoom }
        var chosen = fitted.max(by: { $0.baseZoom < $1.baseZoom })
            ?? pool.min(by: { abs($0.baseZoom - queryZoom) < abs($1.baseZoom - queryZoom) })
            ?? subs[0]
        for _ in 0..<subs.count {
            let grid = tileGrid(header.bounds, chosen.baseZoom)
            if tileCount(bounds, zoom: chosen.baseZoom, grid: grid) <= 28 { return chosen }
            guard let lower = subs.filter({ $0.baseZoom < chosen.baseZoom }).max(by: { $0.baseZoom < $1.baseZoom }) else {
                return chosen
            }
            chosen = lower
        }
        return chosen
    }

    static func parseHeader(_ data: Data) -> MapsforgeHeader? {
        let cursor = ByteCursor(data)
        guard data.count > 70 else { return nil }
        let magic = cursor.readASCII(20)
        guard magic == OsmMapFile.magic else { return nil }
        let headerSize = Int(cursor.readUInt32())
        guard headerSize > 4, 20 + headerSize <= data.count else { return nil }
        let fileVersion = Int(cursor.readUInt32())
        _ = cursor.readUInt64()
        _ = cursor.readUInt64()
        let minLat = Double(cursor.readInt32()) / 1_000_000
        let minLon = Double(cursor.readInt32()) / 1_000_000
        let maxLat = Double(cursor.readInt32()) / 1_000_000
        let maxLon = Double(cursor.readInt32()) / 1_000_000
        let tileSize = Int(cursor.readUInt16())
        _ = cursor.readVBEString()
        let flags = cursor.readByte()
        let debug = flags & 0x80 != 0
        var startLat = (minLat + maxLat) / 2
        var startLon = (minLon + maxLon) / 2
        var startZoom = 12
        if flags & 0x40 != 0 {
            startLat = Double(cursor.readInt32()) / 1_000_000
            startLon = Double(cursor.readInt32()) / 1_000_000
        }
        if flags & 0x20 != 0 { startZoom = Int(cursor.readByte()) }
        if flags & 0x10 != 0 { _ = cursor.readVBEString() }
        if flags & 0x08 != 0 { _ = cursor.readVBEString() }
        if flags & 0x04 != 0 { _ = cursor.readVBEString() }
        let poiTags = readTagList(cursor)
        let wayTags = readTagList(cursor)
        let count = Int(cursor.readByte())
        guard count > 0, count < 32 else { return nil }
        var subs: [MapsforgeSubFile] = []
        for _ in 0..<count {
            let base = Int(cursor.readByte())
            let minZ = Int(cursor.readByte())
            let maxZ = Int(cursor.readByte())
            let start = Int64(bitPattern: cursor.readUInt64())
            let size = Int64(bitPattern: cursor.readUInt64())
            let indexStart = debug ? start + 16 : start
            subs.append(MapsforgeSubFile(
                baseZoom: base, minZoom: minZ, maxZoom: maxZ,
                startAddress: start, indexStartAddress: indexStart, subFileSize: size
            ))
        }
        return MapsforgeHeader(
            bounds: LatLonBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon),
            startLatitude: startLat,
            startLongitude: startLon,
            startZoom: startZoom,
            tileSize: tileSize,
            poiTags: poiTags,
            wayTags: wayTags,
            subFiles: subs,
            debug: debug,
            fileVersion: fileVersion
        )
    }

    private static func decodeTile(
        _ cursor: ByteCursor,
        end: Int,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        queryZoom: Int,
        originLat: Double,
        originLon: Double,
        limit: Int,
        poiLimit: Int
    ) -> [MapFeature]? {
        let rows = sub.maxZoom - sub.minZoom + 1
        guard rows > 0, rows < 30 else { return nil }
        var pois = 0
        var ways = 0
        let queryRow = min(rows - 1, max(0, queryZoom - sub.minZoom))
        for row in 0..<rows {
            let poiCount = cursor.readVBEU()
            let wayCount = cursor.readVBEU()
            if cursor.offset > end { return nil }
            if row <= queryRow {
                pois += poiCount
                ways += wayCount
            }
        }
        let firstWayDelta = cursor.readVBEU()
        let firstWay = cursor.offset + firstWayDelta
        if firstWay > end { return nil }
        var features: [MapFeature] = []
        var keptPois = 0
        let poiCap = max(1, poiLimit)
        for _ in 0..<pois {
            if cursor.offset >= firstWay || cursor.offset >= end { break }
            if header.debug { cursor.offset += 32 }
            guard let feature = readPOI(cursor, header: header, originLat: originLat, originLon: originLon) else { break }
            if keptPois < poiCap {
                features.append(feature)
                keptPois += 1
            }
        }
        cursor.offset = firstWay
        var keptWays = 0
        for _ in 0..<ways {
            if keptWays >= limit || cursor.offset >= end { break }
            if header.debug { cursor.offset += 32 }
            let before = cursor.offset
            let decoded = readWay(
                cursor,
                header: header,
                originLat: originLat,
                originLon: originLon,
                end: end,
                baseZoom: sub.baseZoom
            )
            if decoded.isEmpty {
                if cursor.offset == before { break }
                continue
            }
            for feature in decoded where keptWays < limit {
                features.append(feature)
                keptWays += 1
            }
        }
        return features
    }

    private static func readPOI(_ cursor: ByteCursor, header: MapsforgeHeader, originLat: Double, originLon: Double) -> MapFeature? {
        let latDiff = cursor.readVBES()
        let lonDiff = cursor.readVBES()
        let special = cursor.readByte()
        let tagCount = Int(special & 0x0f)
        var tags: [String: String] = [:]
        for _ in 0..<tagCount {
            let id = cursor.readVBEU()
            let pattern = id >= 0 && id < header.poiTags.count ? header.poiTags[id] : ""
            let value = readVariable(cursor, pattern: pattern)
            let key = pattern.split(separator: "=").first.map(String.init) ?? pattern
            if !key.isEmpty { tags[key] = value.isEmpty ? "yes" : value }
        }
        let flags = cursor.readByte()
        var name: String?
        if flags & 0x80 != 0 { name = readName(cursor, fileVersion: header.fileVersion) }
        if flags & 0x40 != 0 {
            let house = cursor.readVBEString()
            tags["addr:housenumber"] = house
        }
        if flags & 0x20 != 0 { _ = cursor.readVBES() }
        if let name { tags["name"] = name }
        let lat = originLat + Double(latDiff) / 1_000_000
        let lon = originLon + Double(lonDiff) / 1_000_000
        return MapFeature(geometry: .point(latitude: lat, longitude: lon), category: category(for: tags, hiking: false), name: name, tags: tags)
    }

    private static func readWay(
        _ cursor: ByteCursor,
        header: MapsforgeHeader,
        originLat: Double,
        originLon: Double,
        end: Int,
        baseZoom: Int
    ) -> [MapFeature] {
        let size = cursor.readVBEU()
        let blockEnd = min(end, cursor.offset + size)
        _ = cursor.readUInt16()
        let special = cursor.readByte()
        let tagCount = Int(special & 0x0f)
        var tags: [String: String] = [:]
        for _ in 0..<tagCount {
            let id = cursor.readVBEU()
            let pattern = id >= 0 && id < header.wayTags.count ? header.wayTags[id] : ""
            let value = readVariable(cursor, pattern: pattern)
            let key = pattern.split(separator: "=").first.map(String.init) ?? pattern
            if !key.isEmpty { tags[key] = value.isEmpty ? "yes" : value }
        }
        let flags = cursor.readByte()
        var name: String?
        if flags & 0x80 != 0 { name = readName(cursor, fileVersion: header.fileVersion) }
        if flags & 0x40 != 0 { tags["addr:housenumber"] = cursor.readVBEString() }
        if flags & 0x20 != 0 { tags["ref"] = cursor.readVBEString() }
        if flags & 0x10 != 0 {
            _ = cursor.readVBES()
            _ = cursor.readVBES()
        }
        let dataBlocks = flags & 0x08 != 0 ? max(1, cursor.readVBEU()) : 1
        let doubleDelta = flags & 0x04 != 0
        if let name { tags["name"] = name }
        let zoom = min(18, max(0, baseZoom))
        let tileDegrees = 360.0 / Double(1 << zoom)
        let maxSpan = max(0.15, tileDegrees * 3)
        var lines: [[(latitude: Double, longitude: Double)]] = []
        var failed = false
        for _ in 0..<dataBlocks {
            if failed || cursor.offset >= blockEnd { break }
            let coordinateBlocks = cursor.readVBEU()
            if coordinateBlocks <= 0 || coordinateBlocks > 64 || cursor.offset > blockEnd {
                failed = true
                break
            }
            for _ in 0..<coordinateBlocks {
                let nodes = cursor.readVBEU()
                if nodes < 2 || nodes > 1500 || cursor.offset > blockEnd {
                    failed = true
                    break
                }
                let decoded = doubleDelta
                    ? decodeDoubleDelta(cursor, nodes: nodes, originLat: originLat, originLon: originLon)
                    : decodeSingleDelta(cursor, nodes: nodes, originLat: originLat, originLon: originLon)
                if plausible(decoded, header: header, maxSpan: maxSpan) {
                    lines.append(decoded)
                }
            }
        }
        cursor.offset = blockEnd
        let hiking = header.wayTags.joined().contains("osmc")
        let category = category(for: tags, hiking: hiking)
        return lines.map { line in
            MapFeature(geometry: .line(line), category: category, name: name, tags: tags)
        }
    }

    private static func plausible(
        _ line: [(latitude: Double, longitude: Double)],
        header: MapsforgeHeader,
        maxSpan: Double
    ) -> Bool {
        guard line.count >= 2 else { return false }
        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0
        let pad = 1.0
        for node in line {
            guard node.latitude.isFinite, node.longitude.isFinite else { return false }
            guard node.latitude >= header.bounds.minLatitude - pad, node.latitude <= header.bounds.maxLatitude + pad else { return false }
            guard node.longitude >= header.bounds.minLongitude - pad, node.longitude <= header.bounds.maxLongitude + pad else { return false }
            minLat = min(minLat, node.latitude)
            maxLat = max(maxLat, node.latitude)
            minLon = min(minLon, node.longitude)
            maxLon = max(maxLon, node.longitude)
        }
        return (maxLat - minLat) <= maxSpan && (maxLon - minLon) <= maxSpan
    }

    static func category(for tags: [String: String], hiking: Bool) -> String {
        let highway = tags["highway"] ?? ""
        let natural = tags["natural"] ?? ""
        if hiking || tags["osmc:symbol"] != nil || tags["kct_red"] != nil || tags["kct_blue"] != nil || tags["kct_green"] != nil || tags["kct_yellow"] != nil {
            if tags["contour"] != nil || tags["contour_ext"] != nil {
                return (tags["contour_ext"] == "elevation_minor") ? TuhuRenderOptions.catContoursMinor : TuhuRenderOptions.catContours
            }
            if highway == "path" || highway == "footway" || highway == "track" || highway == "cycleway" {
                return tags["osmc:symbol"] != nil ? TuhuRenderOptions.catBlazes : TuhuRenderOptions.catPaths
            }
        }
        if natural == "water" || natural == "coastline" || tags["waterway"] != nil || tags["water"] != nil {
            return "water"
        }
        if tags["building"] != nil { return OsmRenderOptions.catBuildings }
        if highway == "cycleway" || tags["bicycle"] == "designated" { return OsmRenderOptions.catCycleways }
        if tags["railway"] != nil || tags["public_transport"] != nil || highway == "bus_stop" { return OsmRenderOptions.catTransit }
        if tags["leisure"] == "park" || tags["boundary"] == "protected_area" || tags["leisure"] == "nature_reserve" {
            return OsmRenderOptions.catParks
        }
        if tags["landuse"] != nil || natural == "wood" || natural == "scrub" || natural == "grassland" || tags["leisure"] == "garden" {
            return "land"
        }
        if tags["amenity"] != nil || tags["shop"] != nil || tags["tourism"] != nil { return OsmRenderOptions.catPoi }
        if hiking && (highway == "path" || highway == "footway" || highway == "track") {
            return TuhuRenderOptions.catPaths
        }
        return "road"
    }

    private static func readName(_ cursor: ByteCursor, fileVersion: Int) -> String {
        if fileVersion >= 4 {
            let text = cursor.readVBEString()
            if text.contains("\u{0008}") || text.contains("\r") {
                return MapSearch.record(tags: ["name": text])?.displayName ?? text
            }
            return text
        }
        return cursor.readVBEString()
    }

    private static func readVariable(_ cursor: ByteCursor, pattern: String) -> String {
        guard pattern.contains("%") else { return pattern.split(separator: "=").dropFirst().joined(separator: "=") }
        var output = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            if pattern[index] == "%", pattern.index(after: index) < pattern.endIndex {
                let code = pattern[pattern.index(after: index)]
                switch code {
                case "s":
                    output += cursor.readVBEString()
                case "f":
                    output += String(cursor.readFloat())
                case "i":
                    output += String(cursor.readInt32())
                case "d":
                    output += String(cursor.readVBES())
                case "h":
                    output += String(cursor.readInt16())
                case "b":
                    output += String(cursor.readByte())
                default:
                    break
                }
                index = pattern.index(index, offsetBy: 2)
            } else {
                output.append(pattern[index])
                index = pattern.index(after: index)
            }
        }
        if let eq = output.firstIndex(of: "=") {
            return String(output[output.index(after: eq)...])
        }
        return output
    }

    private static func readTagList(_ cursor: ByteCursor) -> [String] {
        let count = Int(cursor.readUInt16())
        guard count >= 0, count < 20_000 else { return [] }
        var tags: [String] = []
        for _ in 0..<count { tags.append(cursor.readVBEString()) }
        return tags
    }

    private struct TileRef {
        var row: Int
        var col: Int
    }

    private struct TileGrid {
        var left: Int
        var top: Int
        var width: Int
        var height: Int
    }

    private static func tileX(_ lon: Double, _ zoom: Int) -> Int {
        let n = Double(1 << zoom)
        return Int(floor((lon + 180) / 360 * n))
    }

    private static func tileY(_ lat: Double, _ zoom: Int) -> Int {
        let n = Double(1 << zoom)
        let rad = min(max(lat, -85), 85) * .pi / 180
        return Int(floor((1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * n))
    }

    private static func tileGrid(_ map: LatLonBounds, _ zoom: Int) -> TileGrid {
        let z = min(18, max(0, zoom))
        let left = tileX(map.minLongitude, z)
        let right = tileX(map.maxLongitude, z)
        let top = tileY(map.maxLatitude, z)
        let bottom = tileY(map.minLatitude, z)
        return TileGrid(left: left, top: top, width: max(1, right - left + 1), height: max(1, bottom - top + 1))
    }

    private static func queryTiles(_ bounds: LatLonBounds, zoom: Int, grid: TileGrid) -> [TileRef] {
        let z = min(18, max(0, zoom))
        let minX = max(grid.left, tileX(bounds.minLongitude, z))
        let maxX = min(grid.left + grid.width - 1, tileX(bounds.maxLongitude, z))
        let minY = max(grid.top, tileY(bounds.maxLatitude, z))
        let maxY = min(grid.top + grid.height - 1, tileY(bounds.minLatitude, z))
        guard minX <= maxX, minY <= maxY else { return [] }
        let centerCol = (minX + maxX) / 2 - grid.left
        let centerRow = (minY + maxY) / 2 - grid.top
        var tiles: [TileRef] = []
        for y in minY...maxY {
            for x in minX...maxX {
                tiles.append(TileRef(row: y - grid.top, col: x - grid.left))
            }
        }
        tiles.sort { lhs, rhs in
            let left = abs(lhs.col - centerCol) + abs(lhs.row - centerRow)
            let right = abs(rhs.col - centerCol) + abs(rhs.row - centerRow)
            return left < right
        }
        return tiles
    }

    private static func tileCount(_ bounds: LatLonBounds, zoom: Int, grid: TileGrid) -> Int {
        let z = min(18, max(0, zoom))
        let minX = max(grid.left, tileX(bounds.minLongitude, z))
        let maxX = min(grid.left + grid.width - 1, tileX(bounds.maxLongitude, z))
        let minY = max(grid.top, tileY(bounds.maxLatitude, z))
        let maxY = min(grid.top + grid.height - 1, tileY(bounds.minLatitude, z))
        guard minX <= maxX, minY <= maxY else { return 0 }
        return (maxX - minX + 1) * (maxY - minY + 1)
    }

    private static func decodeSingleDelta(_ cursor: ByteCursor, nodes: Int, originLat: Double, originLon: Double) -> [(latitude: Double, longitude: Double)] {
        var lat = originLat
        var lon = originLon
        var line: [(latitude: Double, longitude: Double)] = []
        for _ in 0..<nodes {
            lat += Double(cursor.readVBES()) / 1_000_000
            lon += Double(cursor.readVBES()) / 1_000_000
            line.append((lat, lon))
        }
        return line
    }

    private static func decodeDoubleDelta(_ cursor: ByteCursor, nodes: Int, originLat: Double, originLon: Double) -> [(latitude: Double, longitude: Double)] {
        var lat = originLat + Double(cursor.readVBES()) / 1_000_000
        var lon = originLon + Double(cursor.readVBES()) / 1_000_000
        var line: [(latitude: Double, longitude: Double)] = [(lat, lon)]
        var previousLat = 0.0
        var previousLon = 0.0
        if nodes <= 1 { return line }
        for _ in 1..<nodes {
            let singleLat = Double(cursor.readVBES()) / 1_000_000 + previousLat
            let singleLon = Double(cursor.readVBES()) / 1_000_000 + previousLon
            lat += singleLat
            lon += singleLon
            previousLat = singleLat
            previousLon = singleLon
            line.append((lat, lon))
        }
        return line
    }

    private static func tileOrigin(x: Int, y: Int, zoom: Int) -> (lat: Double, lon: Double) {
        let n = Double(1 << zoom)
        let lon = Double(x) / n * 360 - 180
        let latRad = atan(sinh(.pi * (1 - 2 * Double(y) / n)))
        return (latRad * 180 / .pi, lon)
    }

    private static func readFive(_ cursor: ByteCursor) -> Int64 {
        var value: Int64 = 0
        for _ in 0..<5 {
            value = (value << 8) | Int64(cursor.readByte())
        }
        return value
    }
}

final class ByteCursor {
    let data: Data
    var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = 0
    }

    func readByte() -> UInt8 {
        guard offset < data.count else { return 0 }
        let value = data[offset]
        offset += 1
        return value
    }

    func readASCII(_ count: Int) -> String {
        let slice = data.subdata(in: offset..<min(data.count, offset + count))
        offset += count
        return String(data: slice, encoding: .ascii) ?? ""
    }

    func readUInt16() -> UInt16 {
        let hi = UInt16(readByte())
        let lo = UInt16(readByte())
        return (hi << 8) | lo
    }

    func readInt16() -> Int16 { Int16(bitPattern: readUInt16()) }

    func readUInt32() -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(readByte()) }
        return value
    }

    func readInt32() -> Int32 { Int32(bitPattern: readUInt32()) }

    func readUInt64() -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 { value = (value << 8) | UInt64(readByte()) }
        return value
    }

    func readFloat() -> Float { Float(bitPattern: readUInt32()) }

    func readVBEU() -> Int {
        var result = 0
        var shift = 0
        for _ in 0..<8 {
            let byte = Int(readByte())
            result |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    func readVBES() -> Int {
        var result = 0
        var shift = 0
        for _ in 0..<8 {
            let byte = Int(readByte())
            if byte & 0x80 == 0 {
                result |= (byte & 0x3f) << shift
                return byte & 0x40 != 0 ? -result : result
            }
            result |= (byte & 0x7f) << shift
            shift += 7
        }
        return result
    }

    func readVBEString() -> String {
        let length = readVBEU()
        guard length > 0, offset + length <= data.count, length < 1_000_000 else {
            offset = min(data.count, offset + max(0, length))
            return ""
        }
        let slice = data.subdata(in: offset..<(offset + length))
        offset += length
        return String(data: slice, encoding: .utf8) ?? ""
    }
}
