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
    var hiking = false
}

struct MapsforgeSubFile {
    var baseZoom: Int
    var minZoom: Int
    var maxZoom: Int
    var startAddress: Int64
    var indexStartAddress: Int64
    var subFileSize: Int64
}

final class MapFileReader: @unchecked Sendable {
    let url: URL
    let header: MapsforgeHeader
    fileprivate let fileSize: Int64
    private let handle: FileHandle
    private let lock = NSLock()
    private var closed = false

    static func open(_ url: URL) -> MapFileReader? {
        guard OsmMapFile.isReadable(url) else { return nil }
        return MapFileReader(url: url)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? handle.close()
    }

    func placeScan(limit: Int) -> PlaceScan {
        PlaceScan(reader: self, limit: limit)
    }

    func visibleTiles(bounds: LatLonBounds, focus: LatLonBounds, zoom: Int, featureLimit: Int, poiLimit: Int) -> [MapsforgeTileRequest] {
        MapsforgeReader.tileRequests(header: header, bounds: bounds, focus: focus, zoom: zoom, featureLimit: featureLimit, poiLimit: poiLimit)
    }

    func decode(_ requests: [MapsforgeTileRequest], isCancelled: @escaping @Sendable () -> Bool) -> [CachedMapTile] {
        var tiles: [CachedMapTile] = []
        for request in requests {
            if isCancelled() { break }
            guard let features = MapsforgeReader.readTile(
                reader: self,
                header: header,
                sub: request.sub,
                grid: request.grid,
                tile: request.tile,
                queryZoom: request.queryZoom,
                perTile: request.perTile,
                poisPerTile: request.poisPerTile,
                view: request.filterToView ? request.view : nil,
                isCancelled: isCancelled
            ), !isCancelled() else { continue }
            tiles.append(CachedMapTile(
                id: request.id,
                features: features,
                bytes: OfflineTileCache.estimatedBytes(features),
                latitude: request.latitude,
                longitude: request.longitude,
                queryZoom: request.queryZoom,
                perTile: request.perTile,
                covered: request.view
            ))
        }
        return tiles
    }

    fileprivate func read(offset: Int64, length: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, offset >= 0, length > 0, offset <= fileSize else { return nil }
        let available = fileSize - offset
        guard available > 0 else { return nil }
        let count = min(Int64(length), available)
        guard count == Int64(length) else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length)
        } catch {
            return nil
        }
    }

    private init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let size = Int64((try? handle.seekToEnd()) ?? 0)
        guard size >= 24,
              let prefix = Self.read(handle, offset: 0, length: 24, fileSize: size),
              let headerBytes = Self.headerLength(prefix),
              let blob = Self.read(handle, offset: 0, length: Int(min(size, headerBytes)), fileSize: size),
              let header = MapsforgeReader.parseHeader(blob) else {
            try? handle.close()
            return nil
        }
        self.url = url
        self.header = header
        self.fileSize = size
        self.handle = handle
    }

    private static func headerLength(_ prefix: Data) -> Int64? {
        let cursor = ByteCursor(prefix)
        _ = cursor.readASCII(20)
        let headerSize = Int64(cursor.readUInt32())
        guard headerSize > 4, headerSize < 16_000_000 else { return nil }
        return 24 + headerSize
    }

    private static func read(_ handle: FileHandle, offset: Int64, length: Int, fileSize: Int64) -> Data? {
        guard offset >= 0, length > 0, offset + Int64(length) <= fileSize else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: length)
            guard data?.count == length else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

struct MapsforgeTileRequest: Sendable {
    var id: MapsforgeTileId
    var latitude: Double
    var longitude: Double
    fileprivate var tile: MapsforgeReader.TileRef
    fileprivate var sub: MapsforgeSubFile
    fileprivate var grid: MapsforgeReader.TileGrid
    var queryZoom: Int
    var perTile: Int
    fileprivate var poisPerTile: Int
    var view: LatLonBounds
    var filterToView: Bool
}

final class PlaceScan: @unchecked Sendable {
    fileprivate let reader: MapFileReader
    fileprivate let limit: Int
    fileprivate var seen = Set<String>()
    fileprivate var produced = 0
    fileprivate var subIndex = 0
    fileprivate var row = 0
    fileprivate var col = 0
    fileprivate let subs: [MapsforgeSubFile]

    fileprivate init(reader: MapFileReader, limit: Int) {
        self.reader = reader
        self.limit = limit
        self.subs = reader.header.subFiles.sorted { $0.baseZoom < $1.baseZoom }
    }

    func nextBatch(_ count: Int, isCancelled: @escaping @Sendable () -> Bool = { false }) -> [IndexedPlace] {
        MapsforgeReader.nextPlaceBatch(self, count: count, isCancelled: isCancelled)
    }
}

enum ZoomWayBudget {
    static func plan(counts: [Int], queryRow: Int, limit: Int, favorDetail: Bool) -> [Int] {
        var plan = Array(repeating: 0, count: counts.count)
        guard limit > 0, queryRow >= 0, queryRow < counts.count else { return plan }
        if !favorDetail {
            var left = limit
            for row in 0...queryRow {
                let take = min(max(counts[row], 0), left)
                plan[row] = take
                left -= take
                if left == 0 { break }
            }
            return plan
        }
        var left = limit
        let highShare = max(1, limit * 3 / 4)
        let high = min(max(counts[queryRow], 0), highShare)
        plan[queryRow] = high
        left -= high
        if queryRow > 0 {
            for row in stride(from: queryRow - 1, through: 0, by: -1) {
                let take = min(max(counts[row], 0), left)
                plan[row] = take
                left -= take
                if left == 0 { break }
            }
        }
        let room = max(counts[queryRow] - plan[queryRow], 0)
        plan[queryRow] += min(left, room)
        return plan
    }

    static func filled(_ kept: [Int], _ plan: [Int], _ queryRow: Int) -> Bool {
        guard queryRow >= 0 else { return true }
        let last = min(queryRow, plan.count - 1)
        guard last >= 0 else { return true }
        for row in 0...last {
            if row < kept.count, kept[row] < plan[row] { return false }
        }
        return true
    }
}

enum WayView {
    static func expanded(_ bounds: LatLonBounds, fraction: Double) -> LatLonBounds {
        let lat = max(bounds.maxLatitude - bounds.minLatitude, 0.0003) * fraction
        let lon = max(bounds.maxLongitude - bounds.minLongitude, 0.0003) * fraction
        return LatLonBounds(
            minLatitude: bounds.minLatitude - lat,
            minLongitude: bounds.minLongitude - lon,
            maxLatitude: bounds.maxLatitude + lat,
            maxLongitude: bounds.maxLongitude + lon
        )
    }

    static func contains(_ outer: LatLonBounds, _ inner: LatLonBounds) -> Bool {
        inner.minLatitude >= outer.minLatitude - 1e-7
            && inner.maxLatitude <= outer.maxLatitude + 1e-7
            && inner.minLongitude >= outer.minLongitude - 1e-7
            && inner.maxLongitude <= outer.maxLongitude + 1e-7
    }

    static func intersection(_ lhs: LatLonBounds, _ rhs: LatLonBounds) -> LatLonBounds? {
        let minLatitude = max(lhs.minLatitude, rhs.minLatitude)
        let minLongitude = max(lhs.minLongitude, rhs.minLongitude)
        let maxLatitude = min(lhs.maxLatitude, rhs.maxLatitude)
        let maxLongitude = min(lhs.maxLongitude, rhs.maxLongitude)
        guard minLatitude < maxLatitude, minLongitude < maxLongitude else { return nil }
        return LatLonBounds(
            minLatitude: minLatitude,
            minLongitude: minLongitude,
            maxLatitude: maxLatitude,
            maxLongitude: maxLongitude
        )
    }

    static func box(_ feature: MapFeature) -> LatLonBounds? {
        switch feature.geometry {
        case .point(let latitude, let longitude):
            return LatLonBounds(minLatitude: latitude, minLongitude: longitude, maxLatitude: latitude, maxLongitude: longitude)
        case .line(let line):
            guard let first = line.first else { return nil }
            var minLat = first.latitude
            var maxLat = first.latitude
            var minLon = first.longitude
            var maxLon = first.longitude
            for node in line {
                minLat = min(minLat, node.latitude)
                maxLat = max(maxLat, node.latitude)
                minLon = min(minLon, node.longitude)
                maxLon = max(maxLon, node.longitude)
            }
            return LatLonBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
        }
    }

    static func overlaps(_ lhs: LatLonBounds, _ rhs: LatLonBounds) -> Bool {
        lhs.maxLatitude >= rhs.minLatitude && lhs.minLatitude <= rhs.maxLatitude
            && lhs.maxLongitude >= rhs.minLongitude && lhs.minLongitude <= rhs.maxLongitude
    }

    static func intersects(_ feature: MapFeature, _ bounds: LatLonBounds) -> Bool {
        guard let box = box(feature) else { return false }
        return overlaps(box, bounds)
    }

    static func rank(_ feature: MapFeature) -> Int {
        if feature.tags["highway"] != nil || feature.tags["railway"] != nil || feature.tags["waterway"] != nil {
            return 0
        }
        if feature.category == "water" || feature.category == "land" || feature.category == OsmRenderOptions.catParks {
            return 1
        }
        if feature.tags["building"] != nil { return 3 }
        return 2
    }
}

struct WayQuota {
    private(set) var roads: [MapFeature] = []
    private(set) var land: [MapFeature] = []
    private(set) var rest: [MapFeature] = []
    let roadCap: Int
    let landCap: Int
    let restCap: Int
    let queryRoadFloor: Int

    init(limit: Int) {
        let total = max(limit, 1)
        roadCap = max(1, total * 3 / 5)
        landCap = max(1, total / 5)
        restCap = max(0, total - roadCap - landCap)
        queryRoadFloor = 0
    }

    var filled: Bool {
        roads.count >= roadCap && land.count >= landCap && rest.count >= restCap
    }

    func saturated(onQueryRow: Bool) -> Bool {
        if onQueryRow { return filled }
        return roads.count >= max(0, roadCap - queryRoadFloor)
            && land.count >= landCap
            && rest.count >= restCap
    }

    mutating func add(_ feature: MapFeature, view: LatLonBounds, onQueryRow: Bool) {
        guard WayView.intersects(feature, view) else { return }
        switch WayView.rank(feature) {
        case 0:
            let cap = onQueryRow ? roadCap : max(0, roadCap - queryRoadFloor)
            guard roads.count < cap else { return }
            roads.append(feature)
        case 1:
            guard land.count < landCap else { return }
            land.append(feature)
        default:
            guard rest.count < restCap else { return }
            rest.append(feature)
        }
    }

    func features() -> [MapFeature] {
        roads + land + rest
    }
}

enum MapsforgeReader {
    static func header(of url: URL) -> MapsforgeHeader? {
        guard let reader = MapFileReader.open(url) else { return nil }
        defer { reader.close() }
        return reader.header
    }

    static func namedPlaces(url: URL, limit: Int, isCancelled: @escaping @Sendable () -> Bool = { false }) -> [IndexedPlace] {
        guard let reader = MapFileReader.open(url) else { return [] }
        defer { reader.close() }
        let scan = reader.placeScan(limit: limit)
        var rows: [IndexedPlace] = []
        while rows.count < limit {
            if isCancelled() { break }
            let batch = scan.nextBatch(min(400, limit - rows.count), isCancelled: isCancelled)
            if batch.isEmpty { break }
            rows.append(contentsOf: batch)
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
        guard let reader = MapFileReader.open(url) else { return [] }
        defer { reader.close() }
        let header = reader.header
        let queryZoom = min(max(zoom, 0), 22)
        guard let sub = chooseSubfile(header, bounds: bounds, queryZoom: queryZoom) else { return [] }
        let grid = tileGrid(header.bounds, sub.baseZoom)
        let query = queryTiles(bounds, zoom: sub.baseZoom, grid: grid)
        guard !query.isEmpty else { return [] }
        let budgets = tileBudgets(queryZoom: queryZoom, sub: sub, queryCount: query.count, limit: limit, poiLimit: poiLimit)
        var features: [MapFeature] = []
        for tile in query {
            if features.count >= budgets.cap || isCancelled() { break }
            if let decoded = readTile(
                reader: reader,
                header: header,
                sub: sub,
                grid: grid,
                tile: tile,
                queryZoom: queryZoom,
                perTile: budgets.perTile,
                poisPerTile: budgets.poisPerTile,
                view: bounds
            ) {
                features.append(contentsOf: decoded)
            }
        }
        return features
    }

    fileprivate static func tileRequests(
        header: MapsforgeHeader,
        bounds: LatLonBounds,
        focus: LatLonBounds,
        zoom: Int,
        featureLimit: Int,
        poiLimit: Int
    ) -> [MapsforgeTileRequest] {
        let queryZoom = min(max(zoom, 0), 22)
        guard let sub = chooseSubfile(header, bounds: bounds, queryZoom: queryZoom) else { return [] }
        let grid = tileGrid(header.bounds, sub.baseZoom)
        let query = Array(queryTiles(bounds, zoom: sub.baseZoom, grid: grid).prefix(tilesKeptForZoom(Int.max)))
        guard !query.isEmpty else { return [] }
        let budgets = tileBudgets(queryZoom: queryZoom, sub: sub, queryCount: query.count, limit: featureLimit, poiLimit: poiLimit)
        let focusView = WayView.expanded(focus, fraction: 0.45)
        return query.map { tile in
            let column = grid.left + tile.col
            let row = grid.top + tile.row
            let center = tileCenter(column: column, row: row, zoom: sub.baseZoom)
            let id = MapsforgeTileId(baseZoom: sub.baseZoom, column: column, row: row)
            return MapsforgeTileRequest(
                id: id,
                latitude: center.lat,
                longitude: center.lon,
                tile: tile,
                sub: sub,
                grid: grid,
                queryZoom: queryZoom,
                perTile: budgets.perTile,
                poisPerTile: budgets.poisPerTile,
                view: focusView,
                filterToView: true
            )
        }
    }

    fileprivate static func nextPlaceBatch(
        _ scan: PlaceScan,
        count: Int,
        isCancelled: () -> Bool
    ) -> [IndexedPlace] {
        var rows: [IndexedPlace] = []
        let header = scan.reader.header
        while rows.count < count, scan.produced < scan.limit, !isCancelled() {
            guard scan.subIndex < scan.subs.count else { break }
            let sub = scan.subs[scan.subIndex]
            let grid = tileGrid(header.bounds, sub.baseZoom)
            if scan.row >= grid.height {
                scan.subIndex += 1
                scan.row = 0
                scan.col = 0
                continue
            }
            if scan.col >= grid.width {
                scan.row += 1
                scan.col = 0
                continue
            }
            let row = scan.row
            let col = scan.col
            scan.col += 1
            let tile = TileRef(row: row, col: col)
            guard let decoded = readTile(
                reader: scan.reader,
                header: header,
                sub: sub,
                grid: grid,
                tile: tile,
                queryZoom: sub.maxZoom,
                perTile: 80_000,
                poisPerTile: 80_000,
                view: nil,
                isCancelled: isCancelled
            ), !isCancelled() else { continue }
            for feature in decoded {
                guard scan.produced < scan.limit, rows.count < count else { break }
                guard let place = indexedPlace(from: feature), scan.seen.insert(place.key).inserted else { continue }
                scan.produced += 1
                rows.append(place.row)
            }
        }
        return rows
    }

    fileprivate static func readTile(
        reader: MapFileReader,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        grid: TileGrid,
        tile: TileRef,
        queryZoom: Int,
        perTile: Int,
        poisPerTile: Int,
        view: LatLonBounds?,
        isCancelled: () -> Bool = { false }
    ) -> [MapFeature]? {
        let block = tile.row * grid.width + tile.col
        let entryPos = sub.indexStartAddress + Int64(block * 5)
        let last = block + 1 == grid.width * grid.height
        let indexLength = last ? 5 : 10
        guard entryPos >= 0, let index = reader.read(offset: entryPos, length: indexLength) else { return nil }
        let cursor = ByteCursor(index)
        let offset = readFive(cursor) & 0x7fffffffff
        let next: Int64
        if last {
            next = sub.subFileSize
        } else {
            next = readFive(cursor) & 0x7fffffffff
        }
        if offset <= 0 || offset >= next || offset > sub.subFileSize { return [] }
        let tileStart = sub.startAddress + offset
        let tileEnd = min(sub.startAddress + next, sub.startAddress + sub.subFileSize)
        guard tileStart < tileEnd, tileEnd <= reader.fileSize else { return nil }
        let length = Int(tileEnd - tileStart)
        let column = grid.left + tile.col
        let row = grid.top + tile.row
        let origin = tileOrigin(x: column, y: row, zoom: sub.baseZoom)
        let focus = view
        let mask = focus.map { subtileMask(column: column, row: row, zoom: sub.baseZoom, bounds: $0) } ?? 0xFFFF
        if length > maxTileReadBytes {
            return decodeLargeTile(
                reader: reader,
                header: header,
                sub: sub,
                tileStart: tileStart,
                length: length,
                queryZoom: queryZoom,
                originLat: origin.lat,
                originLon: origin.lon,
                limit: perTile,
                view: focus,
                mask: mask
            )
        }
        guard let bytes = reader.read(offset: tileStart, length: length) else { return nil }
        let tileCursor = ByteCursor(bytes)
        if header.debug { tileCursor.offset = min(32, bytes.count) }
        return decodeTile(
            tileCursor,
            end: bytes.count,
            header: header,
            sub: sub,
            queryZoom: queryZoom,
            originLat: origin.lat,
            originLon: origin.lon,
            limit: perTile,
            poiLimit: poisPerTile,
            view: focus,
            mask: mask,
            isCancelled: isCancelled
        )
    }

    static func tilesKeptForZoom(_ count: Int) -> Int {
        min(max(count, 0), OfflineTileCache.maxTiles)
    }

    private static let maxTileReadBytes = 4_000_000

    private static func decodeLargeTile(
        reader: MapFileReader,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        tileStart: Int64,
        length: Int,
        queryZoom: Int,
        originLat: Double,
        originLon: Double,
        limit: Int,
        view: LatLonBounds?,
        mask: UInt16
    ) -> [MapFeature]? {
        let probeCount = min(length, 65_536)
        guard let probe = reader.read(offset: tileStart, length: probeCount) else { return nil }
        guard let index = zoomIndex(in: probe, debug: header.debug, sub: sub), index.firstWay >= 0, index.firstWay < length else { return nil }
        let rows = sub.maxZoom - sub.minZoom + 1
        let queryRow = min(max(rows - 1, 0), max(0, queryZoom - sub.minZoom))
        if queryZoom > 11 {
            if let view {
                return streamVisibleWays(
                    reader: reader,
                    start: tileStart + Int64(index.firstWay),
                    end: tileStart + Int64(length),
                    header: header,
                    sub: sub,
                    originLat: originLat,
                    originLon: originLon,
                    wayCounts: index.wayCounts,
                    queryRow: queryRow,
                    limit: limit,
                    view: view,
                    mask: mask
                )
            }
            return streamPlannedWays(
                reader: reader,
                start: tileStart + Int64(index.firstWay),
                end: tileStart + Int64(length),
                header: header,
                sub: sub,
                originLat: originLat,
                originLon: originLon,
                wayCounts: index.wayCounts,
                queryRow: queryRow,
                limit: limit
            )
        }
        let wayLength = min(maxTileReadBytes, length - index.firstWay)
        guard wayLength > 0, let wayBytes = reader.read(offset: tileStart + Int64(index.firstWay), length: wayLength) else { return nil }
        let wayCount = max(limit, 1) * max(queryRow + 1, 1) * 8
        let cursor = ByteCursor(wayBytes)
        return decodeWays(
            cursor,
            end: wayBytes.count,
            header: header,
            sub: sub,
            originLat: originLat,
            originLon: originLon,
            wayCount: wayCount,
            limit: limit,
            spread: true
        )
    }

    private struct TileZoomIndex {
        var wayCounts: [Int]
        var firstWay: Int
    }

    private static func zoomIndex(in data: Data, debug: Bool, sub: MapsforgeSubFile) -> TileZoomIndex? {
        let cursor = ByteCursor(data)
        if debug { cursor.offset = min(32, data.count) }
        let rows = sub.maxZoom - sub.minZoom + 1
        guard rows > 0, rows < 30 else { return nil }
        var wayCounts: [Int] = []
        for _ in 0..<rows {
            _ = cursor.readVBEU()
            wayCounts.append(cursor.readVBEU())
            if cursor.offset > data.count { return nil }
        }
        let afterHeader = cursor.offset
        let firstWay = afterHeader + cursor.readVBEU()
        guard cursor.offset <= data.count, firstWay >= afterHeader else { return nil }
        return TileZoomIndex(wayCounts: wayCounts, firstWay: firstWay)
    }

    private static func streamPlannedWays(
        reader: MapFileReader,
        start: Int64,
        end: Int64,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCounts: [Int],
        queryRow: Int,
        limit: Int
    ) -> [MapFeature] {
        let plan = ZoomWayBudget.plan(counts: wayCounts, queryRow: queryRow, limit: limit, favorDetail: true)
        var features: [MapFeature] = []
        var window = WayWindow(reader: reader, end: end)
        var offset = start
        var row = 0
        var left = wayCounts.isEmpty ? 0 : wayCounts[0]
        var kept = Array(repeating: 0, count: wayCounts.count)
        while offset < end, row <= queryRow, !ZoomWayBudget.filled(kept, plan, queryRow) {
            if left == 0 {
                row += 1
                guard row <= queryRow, row < wayCounts.count else { break }
                left = wayCounts[row]
                continue
            }
            if header.debug { offset += 32 }
            guard let head = window.slice(at: offset, count: Int(min(10, end - offset))) else { break }
            let headCursor = ByteCursor(head)
            let size = headCursor.readVBEU()
            let headerLen = headCursor.offset
            let recordLen = headerLen + size
            let next = offset + Int64(recordLen)
            guard size >= 0, recordLen >= headerLen, next <= end else { break }
            if row < plan.count, kept[row] < plan[row], let record = window.slice(at: offset, count: recordLen) {
                let cursor = ByteCursor(record)
                let decoded = readWay(
                    cursor,
                    header: header,
                    originLat: originLat,
                    originLon: originLon,
                    end: record.count,
                    baseZoom: sub.baseZoom
                )
                for feature in decoded where kept[row] < plan[row] {
                    features.append(feature)
                    kept[row] += 1
                }
            }
            left -= 1
            offset = next
        }
        return features
    }

    private static func streamVisibleWays(
        reader: MapFileReader,
        start: Int64,
        end: Int64,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCounts: [Int],
        queryRow: Int,
        limit: Int,
        view: LatLonBounds,
        mask: UInt16
    ) -> [MapFeature] {
        var quota = WayQuota(limit: limit)
        var window = WayWindow(reader: reader, end: end)
        var offset = start
        var row = 0
        var left = wayCounts.isEmpty ? 0 : wayCounts[0]
        var decodedWays = 0
        let decodeCap = max(limit * 8, 2_500)
        while offset < end, row <= queryRow, !quota.filled, decodedWays < decodeCap {
            if left == 0 {
                row += 1
                guard row <= queryRow, row < wayCounts.count else { break }
                left = wayCounts[row]
                continue
            }
            if header.debug { offset += 32 }
            guard let head = window.slice(at: offset, count: Int(min(12, end - offset))) else { break }
            let headCursor = ByteCursor(head)
            let size = headCursor.readVBEU()
            let headerLen = headCursor.offset
            let recordLen = headerLen + size
            let next = offset + Int64(recordLen)
            guard size >= 0, recordLen >= headerLen, next <= end else { break }
            let onQuery = row == queryRow
            var outside = quota.saturated(onQueryRow: onQuery)
            if !outside, mask != 0xFFFF, size >= 2, headerLen + 2 <= head.count {
                let bitmap = (UInt16(head[headerLen]) << 8) | UInt16(head[headerLen + 1])
                outside = (bitmap & mask) == 0
            }
            if !outside, let record = window.slice(at: offset, count: recordLen) {
                let cursor = ByteCursor(record)
                let decoded = readWay(
                    cursor,
                    header: header,
                    originLat: originLat,
                    originLon: originLon,
                    end: record.count,
                    baseZoom: sub.baseZoom
                )
                decodedWays += 1
                for feature in decoded {
                    quota.add(feature, view: view, onQueryRow: onQuery)
                }
            }
            left -= 1
            offset = next
        }
        return quota.features()
    }

    private struct WayWindow {
        var reader: MapFileReader
        var end: Int64
        private var base: Int64 = -1
        private var data = Data()

        mutating func slice(at offset: Int64, count: Int) -> Data? {
            guard count >= 0, offset >= 0, offset + Int64(count) <= end else { return nil }
            if base < 0 || offset < base || offset + Int64(count) > base + Int64(data.count) {
                let length = min(max(count, 262_144), Int(end - offset))
                guard length >= count, let loaded = reader.read(offset: offset, length: length), loaded.count == length else { return nil }
                base = offset
                data = loaded
            }
            let start = Int(offset - base)
            return data.subdata(in: start..<(start + count))
        }
    }

    static let overviewFeatureCap = 12_000

    static func isDetail(queryZoom: Int, sub: MapsforgeSubFile) -> Bool {
        queryZoom > 11 && queryZoom <= sub.maxZoom
    }

    private static func tileBudgets(queryZoom: Int, sub: MapsforgeSubFile, queryCount: Int, limit: Int, poiLimit: Int) -> (cap: Int, perTile: Int, poisPerTile: Int) {
        guard isDetail(queryZoom: queryZoom, sub: sub) else {
            let cap = overviewFeatureCap
            let perTile = min(cap, max(cap / max(queryCount, 1), 250))
            return (cap, perTile, min(poiLimit, 6))
        }
        let perTile = queryCount <= 2 ? 4_000 : (queryCount <= 6 ? 2_500 : 1_200)
        return (max(limit, perTile * min(queryCount, 4)), perTile, poiLimit)
    }

    private static func tileCenter(column: Int, row: Int, zoom: Int) -> (lat: Double, lon: Double) {
        let northwest = tileOrigin(x: column, y: row, zoom: zoom)
        let southeast = tileOrigin(x: column + 1, y: row + 1, zoom: zoom)
        return ((northwest.lat + southeast.lat) / 2, (northwest.lon + southeast.lon) / 2)
    }

    fileprivate static func indexedPlace(from feature: MapFeature) -> (key: String, row: IndexedPlace)? {
        guard let point = searchAnchor(feature), let record = MapSearch.record(tags: feature.tags) else { return nil }
        let key = "\(record.kind.rawValue)|\(MapSearch.fold(record.displayName))|\(Int((point.0 / 0.0004).rounded()))|\(Int((point.1 / 0.0004).rounded()))"
        let row = IndexedPlace(
            name: record.displayName,
            folded: record.foldedAliases.joined(separator: " "),
            kind: record.kind.rawValue,
            latitude: point.0,
            longitude: point.1
        )
        return (key, row)
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
            if tileCount(bounds, zoom: chosen.baseZoom, grid: grid) <= tilesKeptForZoom(Int.max) { return chosen }
            guard let lower = subs.filter({ $0.baseZoom < chosen.baseZoom }).max(by: { $0.baseZoom < $1.baseZoom }) else {
                return chosen
            }
            chosen = lower
        }
        return chosen
    }

    static func subfileBaseZoom(header: MapsforgeHeader, bounds: LatLonBounds, zoom: Int) -> Int? {
        chooseSubfile(header, bounds: bounds, queryZoom: zoom)?.baseZoom
    }

    fileprivate static func parseHeader(_ data: Data) -> MapsforgeHeader? {
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
        var header = MapsforgeHeader(
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
        header.hiking = wayTags.contains { $0.contains("osmc") }
        return header
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
        poiLimit: Int,
        view: LatLonBounds?,
        mask: UInt16,
        isCancelled: () -> Bool = { false }
    ) -> [MapFeature]? {
        let rows = sub.maxZoom - sub.minZoom + 1
        guard rows > 0, rows < 30 else { return nil }
        var pois = 0
        var ways = 0
        var wayRows = Array(repeating: 0, count: rows)
        let queryRow = min(rows - 1, max(0, queryZoom - sub.minZoom))
        for row in 0..<rows {
            let poiCount = cursor.readVBEU()
            let wayCount = cursor.readVBEU()
            if cursor.offset > end { return nil }
            if row <= queryRow {
                pois += poiCount
                ways += wayCount
                wayRows[row] = wayCount
            }
        }
        let firstWayDelta = cursor.readVBEU()
        let firstWay = cursor.offset + firstWayDelta
        if firstWay > end { return nil }
        var features: [MapFeature] = []
        var keptPois = 0
        var examinedPois = 0
        let poiCap = max(1, poiLimit)
        let poiScan = view == nil ? poiCap : min(pois, max(poiCap * 50, poiCap))
        for _ in 0..<pois {
            if examinedPois >= poiScan || keptPois >= poiCap || cursor.offset >= firstWay || cursor.offset >= end { break }
            if header.debug { cursor.offset += 32 }
            examinedPois += 1
            if examinedPois & 255 == 0, isCancelled() { return nil }
            guard let feature = readPOI(cursor, header: header, originLat: originLat, originLon: originLon) else { break }
            if let view, !WayView.intersects(feature, view) { continue }
            features.append(feature)
            keptPois += 1
        }
        cursor.offset = min(firstWay, end)
        if !isDetail(queryZoom: queryZoom, sub: sub), let view {
            features.append(contentsOf: decodeOverviewWays(
                cursor,
                end: end,
                header: header,
                sub: sub,
                originLat: originLat,
                originLon: originLon,
                wayCounts: wayRows,
                queryRow: queryRow,
                limit: limit,
                view: view,
                mask: mask,
                isCancelled: isCancelled
            ))
        } else if queryZoom > 11 {
            if let view {
                features.append(contentsOf: decodeVisibleWays(
                    cursor,
                    end: end,
                    header: header,
                    sub: sub,
                    originLat: originLat,
                    originLon: originLon,
                    wayCounts: wayRows,
                    queryRow: queryRow,
                    limit: limit,
                    view: view,
                    mask: mask,
                    isCancelled: isCancelled
                ))
            } else {
                features.append(contentsOf: decodePlannedWays(
                    cursor,
                    end: end,
                    header: header,
                    sub: sub,
                    originLat: originLat,
                    originLon: originLon,
                    wayCounts: wayRows,
                    queryRow: queryRow,
                    limit: limit,
                    isCancelled: isCancelled
                ))
            }
        } else {
            features.append(contentsOf: decodeWays(
                cursor,
                end: end,
                header: header,
                sub: sub,
                originLat: originLat,
                originLon: originLon,
                wayCount: ways,
                limit: limit,
                spread: true,
                isCancelled: isCancelled
            ))
        }
        return features
    }

    private static func decodePlannedWays(
        _ cursor: ByteCursor,
        end: Int,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCounts: [Int],
        queryRow: Int,
        limit: Int,
        isCancelled: () -> Bool = { false }
    ) -> [MapFeature] {
        let plan = ZoomWayBudget.plan(counts: wayCounts, queryRow: queryRow, limit: limit, favorDetail: true)
        var features: [MapFeature] = []
        var steps = 0
        var row = 0
        var left = wayCounts.isEmpty ? 0 : wayCounts[0]
        var kept = Array(repeating: 0, count: wayCounts.count)
        while row <= queryRow, cursor.offset < end, !ZoomWayBudget.filled(kept, plan, queryRow) {
            if left == 0 {
                row += 1
                guard row <= queryRow, row < wayCounts.count else { break }
                left = wayCounts[row]
                continue
            }
            steps += 1
            if steps & 255 == 0, isCancelled() { break }
            if header.debug { cursor.offset += 32 }
            if cursor.offset >= end { break }
            let open = row < plan.count && kept[row] < plan[row]
            if !open {
                guard skipWay(cursor, end: end) else { break }
                left -= 1
                continue
            }
            let before = cursor.offset
            let decoded = readWay(
                cursor,
                header: header,
                originLat: originLat,
                originLon: originLon,
                end: end,
                baseZoom: sub.baseZoom
            )
            if cursor.offset == before { break }
            left -= 1
            for feature in decoded where row < plan.count && kept[row] < plan[row] {
                features.append(feature)
                kept[row] += 1
            }
        }
        return features
    }

    private static func decodeVisibleWays(
        _ cursor: ByteCursor,
        end: Int,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCounts: [Int],
        queryRow: Int,
        limit: Int,
        view: LatLonBounds,
        mask: UInt16,
        isCancelled: () -> Bool = { false }
    ) -> [MapFeature] {
        var quota = WayQuota(limit: limit)
        var steps = 0
        var row = 0
        var left = wayCounts.isEmpty ? 0 : wayCounts[0]
        var decodedWays = 0
        let decodeCap = max(limit * 8, 2_500)
        while row <= queryRow, cursor.offset < end, !quota.filled, decodedWays < decodeCap {
            if left == 0 {
                row += 1
                guard row <= queryRow, row < wayCounts.count else { break }
                left = wayCounts[row]
                continue
            }
            steps += 1
            if steps & 255 == 0, isCancelled() { break }
            if header.debug { cursor.offset += 32 }
            if cursor.offset >= end { break }
            let onQuery = row == queryRow
            if quota.saturated(onQueryRow: onQuery) {
                guard skipWay(cursor, end: end) else { break }
                left -= 1
                continue
            }
            if skipIfOutside(cursor, end: end, mask: mask) {
                left -= 1
                continue
            }
            let before = cursor.offset
            let decoded = readWay(
                cursor,
                header: header,
                originLat: originLat,
                originLon: originLon,
                end: end,
                baseZoom: sub.baseZoom
            )
            if cursor.offset == before { break }
            left -= 1
            decodedWays += 1
            for feature in decoded {
                quota.add(feature, view: view, onQueryRow: onQuery)
            }
        }
        return quota.features()
    }

    static func overviewRank(_ feature: MapFeature) -> Int? {
        let tags = feature.tags
        if let highway = tags["highway"] {
            switch highway {
            case "motorway", "trunk": return 0
            case "primary": return 1
            case "secondary": return 2
            case "tertiary": return 3
            case "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link": return 4
            default: return 6
            }
        }
        if tags["admin_level"] == "2" { return 0 }
        if feature.category == "water" { return 2 }
        if tags["railway"] == "rail" { return 3 }
        if feature.category == "land" || feature.category == OsmRenderOptions.catParks { return 5 }
        return nil
    }

    private static func decodeOverviewWays(
        _ cursor: ByteCursor,
        end: Int,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCounts: [Int],
        queryRow: Int,
        limit: Int,
        view: LatLonBounds,
        mask: UInt16,
        isCancelled: () -> Bool
    ) -> [MapFeature] {
        var kept: [(rank: Int, size: Double, feature: MapFeature)] = []
        var steps = 0
        var row = 0
        var left = wayCounts.isEmpty ? 0 : wayCounts[0]
        while row <= queryRow, cursor.offset < end {
            if left == 0 {
                row += 1
                guard row <= queryRow, row < wayCounts.count else { break }
                left = wayCounts[row]
                continue
            }
            steps += 1
            if steps & 255 == 0, isCancelled() { break }
            if header.debug { cursor.offset += 32 }
            if cursor.offset >= end { break }
            if skipIfOutside(cursor, end: end, mask: mask) {
                left -= 1
                continue
            }
            let before = cursor.offset
            let decoded = readWay(
                cursor,
                header: header,
                originLat: originLat,
                originLon: originLon,
                end: end,
                baseZoom: sub.baseZoom
            )
            if cursor.offset == before { break }
            left -= 1
            for feature in decoded {
                guard let rank = overviewRank(feature), let box = WayView.box(feature), WayView.overlaps(box, view) else { continue }
                let size = (box.maxLatitude - box.minLatitude) + (box.maxLongitude - box.minLongitude)
                kept.append((rank, size, feature))
            }
        }
        guard kept.count > limit else { return kept.map(\.feature) }
        kept.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.size > rhs.size
        }
        return kept.prefix(max(limit, 0)).map(\.feature)
    }

    private static func skipIfOutside(_ cursor: ByteCursor, end: Int, mask: UInt16) -> Bool {
        guard mask != 0xFFFF else { return false }
        let start = cursor.offset
        let size = cursor.readVBEU()
        let content = cursor.offset
        let next = content + size
        guard size >= 2, next >= content, next <= end else {
            cursor.offset = start
            return false
        }
        let bitmap = cursor.readUInt16()
        if (bitmap & mask) == 0 {
            cursor.offset = next
            return true
        }
        cursor.offset = start
        return false
    }

    private static func skipWay(_ cursor: ByteCursor, end: Int) -> Bool {
        let start = cursor.offset
        let size = cursor.readVBEU()
        let next = cursor.offset + size
        guard next >= cursor.offset, next <= end, cursor.offset > start || size == 0 else { return false }
        cursor.offset = next
        return true
    }

    private static func decodeWays(
        _ cursor: ByteCursor,
        end: Int,
        header: MapsforgeHeader,
        sub: MapsforgeSubFile,
        originLat: Double,
        originLon: Double,
        wayCount: Int,
        limit: Int,
        spread: Bool,
        isCancelled: () -> Bool = { false }
    ) -> [MapFeature] {
        let stride = spread && wayCount > limit && limit > 0 ? max(1, min(wayCount, limit * 8) / limit) : 1
        let scanLimit = min(wayCount, max(limit, 1) * stride)
        var features: [MapFeature] = []
        var keptWays = 0
        var seen = 0
        while seen < scanLimit, cursor.offset < end {
            if keptWays >= limit { break }
            seen += 1
            if seen & 255 == 0, isCancelled() { break }
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
            if stride > 1, (seen - 1) % stride != 0 { continue }
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
        var tags = readTags(cursor, count: tagCount, patterns: header.poiTags)
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
        var tags = readTags(cursor, count: tagCount, patterns: header.wayTags)
        if tags["natural"] == "sea" || tags["natural"] == "nosea" {
            cursor.offset = blockEnd
            return []
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
        let category = category(for: tags, hiking: header.hiking)
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

    private static func readTags(_ cursor: ByteCursor, count: Int, patterns: [String]) -> [String: String] {
        var chosen: [String] = []
        for _ in 0..<count {
            let id = cursor.readVBEU()
            chosen.append(id >= 0 && id < patterns.count ? patterns[id] : "")
        }
        var tags: [String: String] = [:]
        for pattern in chosen {
            let value = readVariable(cursor, pattern: pattern)
            let key = pattern.split(separator: "=").first.map(String.init) ?? pattern
            if !key.isEmpty { tags[key] = value.isEmpty ? "yes" : value }
        }
        return tags
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

    fileprivate struct TileRef {
        var row: Int
        var col: Int
    }

    fileprivate struct TileGrid {
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

    static func geographicBounds(_ id: MapsforgeTileId) -> LatLonBounds {
        let zoom = min(max(id.baseZoom, 0), 28)
        let northwest = tileOrigin(x: id.column, y: id.row, zoom: zoom)
        let southeast = tileOrigin(x: id.column + 1, y: id.row + 1, zoom: zoom)
        return LatLonBounds(
            minLatitude: southeast.lat,
            minLongitude: northwest.lon,
            maxLatitude: northwest.lat,
            maxLongitude: southeast.lon
        )
    }

    static func subtileMask(column: Int, row: Int, zoom: Int, bounds: LatLonBounds) -> UInt16 {
        let fine = min(max(zoom, 0), 28) + 2
        let originX = column << 2
        let originY = row << 2
        let minX = tileX(bounds.minLongitude, fine)
        let maxX = tileX(bounds.maxLongitude, fine)
        let minY = tileY(bounds.maxLatitude, fine)
        let maxY = tileY(bounds.minLatitude, fine)
        let x0 = max(minX, originX)
        let x1 = min(maxX, originX + 3)
        let y0 = max(minY, originY)
        let y1 = min(maxY, originY + 3)
        guard x0 <= x1, y0 <= y1 else { return 0xFFFF }
        var mask: UInt16 = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let bit = 15 - ((y - originY) * 4 + (x - originX))
                mask |= UInt16(1) << UInt16(bit)
            }
        }
        return mask == 0 ? 0xFFFF : mask
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
