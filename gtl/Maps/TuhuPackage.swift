import Foundation
import Compression

enum TuhuPackage {
    static func install(zip: URL, destination: URL, usableSpace: Int64?) throws {
        let entries = try ZipArchive.entries(zip)
        if entries.count > DownloadBudget.maxTuhuEntries {
            throw PackageError.tooManyEntries
        }
        let total = entries.reduce(Int64(0)) { $0 + $1.uncompressed }
        if total > DownloadBudget.maxTuhuUnzipBytes {
            throw PackageError.tooLarge
        }
        if !DownloadBudget.canUnpack(uncompressedBytes: total, usableSpace: usableSpace) {
            throw PackageError.notEnoughSpace
        }
        let folder = destination.deletingLastPathComponent().appendingPathComponent("tuhu-unpack", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var mapURL: URL?
        for entry in entries {
            if entry.name.contains("..") || entry.name.hasPrefix("/") { continue }
            let out = folder.appendingPathComponent(entry.name)
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try ZipArchive.extract(entry, from: zip)
            try bytes.write(to: out)
            if out.pathExtension == "map" { mapURL = out }
        }
        guard let mapURL else { throw PackageError.missingMap }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: mapURL, to: destination)
        try? FileManager.default.removeItem(at: folder)
    }

    enum PackageError: LocalizedError {
        case tooManyEntries
        case tooLarge
        case missingMap
        case badZip
        case notEnoughSpace
        var errorDescription: String? {
            switch self {
            case .tooManyEntries: return "Archive has too many files"
            case .tooLarge: return "Archive is too large"
            case .missingMap: return "Archive has no map"
            case .badZip: return "Archive could not be read"
            case .notEnoughSpace: return L10n.text("Not enough free space", "Nincs elég szabad hely")
            }
        }
    }
}

enum ZipArchive {
    struct Entry {
        var name: String
        var method: UInt16
        var compressed: Int64
        var uncompressed: Int64
        var localOffset: Int64
    }

    static func entries(_ url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        guard data.count > 22 else { throw TuhuPackage.PackageError.badZip }
        var eocd = -1
        let start = max(0, data.count - 66_000)
        var index = data.count - 22
        while index >= start {
            if data[index] == 0x50 && data[index + 1] == 0x4b && data[index + 2] == 0x05 && data[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw TuhuPackage.PackageError.badZip }
        let count = Int(uint16(data, eocd + 10))
        let centralSize = Int(uint32(data, eocd + 12))
        let centralOffset = Int(uint32(data, eocd + 16))
        guard centralOffset + centralSize <= data.count else { throw TuhuPackage.PackageError.badZip }
        var cursor = centralOffset
        var entries: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= data.count, data[cursor] == 0x50, data[cursor + 1] == 0x4b else { break }
            let method = uint16(data, cursor + 10)
            let compressed = Int64(uint32(data, cursor + 20))
            let uncompressed = Int64(uint32(data, cursor + 24))
            let nameLen = Int(uint16(data, cursor + 28))
            let extraLen = Int(uint16(data, cursor + 30))
            let commentLen = Int(uint16(data, cursor + 32))
            let local = Int64(uint32(data, cursor + 42))
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            entries.append(Entry(name: name, method: method, compressed: compressed, uncompressed: uncompressed, localOffset: local))
            cursor += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    static func extract(_ entry: Entry, from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        let local = Int(entry.localOffset)
        guard local + 30 <= data.count else { throw TuhuPackage.PackageError.badZip }
        let nameLen = Int(uint16(data, local + 26))
        let extraLen = Int(uint16(data, local + 28))
        let start = local + 30 + nameLen + extraLen
        let end = start + Int(entry.compressed)
        guard end <= data.count else { throw TuhuPackage.PackageError.badZip }
        let payload = data.subdata(in: start..<end)
        if entry.method == 0 { return payload }
        if entry.method == 8, let inflated = inflate(payload, expected: Int(entry.uncompressed)) { return inflated }
        throw TuhuPackage.PackageError.badZip
    }

    private static func inflate(_ source: Data, expected: Int) -> Data? {
        let capacity = max(expected, source.count * 4, 64)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let size = source.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, capacity, base, source.count, nil, COMPRESSION_ZLIB)
        }
        guard size > 0 else { return nil }
        return Data(bytes: destination, count: size)
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
