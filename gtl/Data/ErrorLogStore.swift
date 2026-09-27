import Foundation

enum ErrorLogStore {
    private static let maxBytes = 256 * 1024

    static func fileURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("errors.log")
    }

    static func record(action: String, error: Error) {
        let line = "\(GpxExporter.utcWhen(Int64(Date().timeIntervalSince1970 * 1000))) \(action) \(error.localizedDescription)\n"
        guard let data = line.data(using: .utf8), let url = try? fileURL() else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            if size > maxBytes {
                try? handle.close()
                let rotated = url.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: url, to: rotated)
                FileManager.default.createFile(atPath: url.path, contents: data)
                return
            }
            try? handle.write(contentsOf: data)
        }
    }

    static func text() -> String {
        guard let url = try? fileURL(), let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func clear() {
        guard let url = try? fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("1"))
    }

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let error = NSError(domain: "gtl", code: 1, userInfo: [NSLocalizedDescriptionKey: exception.reason ?? exception.name.rawValue])
            ErrorLogStore.record(action: "uncaught", error: error)
        }
    }
}
