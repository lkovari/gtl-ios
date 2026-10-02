import Foundation

struct MapsforgeTileId: Hashable, Sendable {
    var baseZoom: Int
    var column: Int
    var row: Int
}

struct CachedMapTile: Sendable {
    var id: MapsforgeTileId
    var features: [MapFeature]
    var bytes: Int
    var latitude: Double
    var longitude: Double
    var queryZoom: Int = 0
    var perTile: Int = 0
    var covered: LatLonBounds? = nil
}

struct OfflineTileCache {
    static let maxTiles = 48
    static let maxBytes = 64 * 1024 * 1024

    private(set) var tiles: [MapsforgeTileId: CachedMapTile] = [:]

    var ids: Set<MapsforgeTileId> { Set(tiles.keys) }

    func needsRefresh(id: MapsforgeTileId, queryZoom: Int, bounds: LatLonBounds) -> Bool {
        guard let tile = tiles[id], let covered = tile.covered else { return true }
        if queryZoom > tile.queryZoom { return true }
        guard let visible = WayView.intersection(bounds, MapsforgeReader.geographicBounds(id)) else { return false }
        return !WayView.contains(covered, visible)
    }

    mutating func update(
        visibleIds: Set<MapsforgeTileId>,
        decoded: [CachedMapTile],
        travelDegrees: Double?,
        centerLatitude: Double,
        centerLongitude: Double,
        pinnedIds: Set<MapsforgeTileId> = []
    ) -> Bool {
        let before = Set(tiles.keys)
        var replaced = false
        for tile in decoded {
            if let existing = tiles[tile.id] {
                if existing.queryZoom != tile.queryZoom || existing.covered != tile.covered {
                    replaced = true
                }
            } else {
                replaced = true
            }
            tiles[tile.id] = tile
        }
        var ranked: [(id: MapsforgeTileId, visible: Bool, behind: Int, distance: Double)] = []
        for (id, tile) in tiles {
            ranked.append((
                id,
                visibleIds.contains(id),
                Self.behind(
                    latitude: tile.latitude,
                    longitude: tile.longitude,
                    travelDegrees: travelDegrees,
                    centerLatitude: centerLatitude,
                    centerLongitude: centerLongitude
                ),
                hypot(tile.latitude - centerLatitude, tile.longitude - centerLongitude)
            ))
        }
        ranked.sort { lhs, rhs in
            if lhs.visible != rhs.visible { return lhs.visible && !rhs.visible }
            if lhs.behind != rhs.behind { return lhs.behind < rhs.behind }
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.id.column != rhs.id.column { return lhs.id.column < rhs.id.column }
            return lhs.id.row < rhs.id.row
        }
        var kept: [MapsforgeTileId: CachedMapTile] = [:]
        var count = 0
        var bytes = 0
        for item in ranked where item.visible {
            guard let tile = tiles[item.id] else { continue }
            if count >= Self.maxTiles { break }
            if bytes + tile.bytes > Self.maxBytes {
                if count == 0 { continue }
                break
            }
            kept[item.id] = tile
            count += 1
            bytes += tile.bytes
        }
        for id in pinnedIds where visibleIds.contains(id) {
            guard kept[id] == nil, let tile = tiles[id] else { continue }
            kept[id] = tile
        }
        let changed = replaced || Set(kept.keys) != before
        tiles = kept
        return changed
    }

    mutating func keep(_ decoded: [CachedMapTile]) {
        for tile in decoded {
            tiles[tile.id] = tile
        }
    }

    func features() -> [MapFeature] {
        tiles.values
            .sorted { lhs, rhs in
                if lhs.id.baseZoom != rhs.id.baseZoom { return lhs.id.baseZoom < rhs.id.baseZoom }
                if lhs.id.column != rhs.id.column { return lhs.id.column < rhs.id.column }
                return lhs.id.row < rhs.id.row
            }
            .flatMap(\.features)
    }

    mutating func removeAll() {
        tiles.removeAll()
    }

    static func estimatedBytes(_ features: [MapFeature]) -> Int {
        var bytes = 0
        for feature in features {
            bytes += 256
            bytes += feature.name?.utf8.count ?? 0
            for (key, value) in feature.tags {
                bytes += key.utf8.count + value.utf8.count + 32
            }
            switch feature.geometry {
            case .point:
                bytes += 32
            case .line(let line):
                bytes += line.count * 32
            }
        }
        return max(bytes, 1)
    }

    private static func behind(
        latitude: Double,
        longitude: Double,
        travelDegrees: Double?,
        centerLatitude: Double,
        centerLongitude: Double
    ) -> Int {
        guard let travelDegrees else { return 0 }
        let rad = travelDegrees * .pi / 180
        let north = cos(rad)
        let east = sin(rad)
        let dot = east * (longitude - centerLongitude) + north * (latitude - centerLatitude)
        return dot < 0 ? 1 : 0
    }
}

enum PlaceIndexPolicy {
    static func shouldStart(logging: Bool, mapVisible: Bool) -> Bool {
        mapVisible && !logging
    }
}
