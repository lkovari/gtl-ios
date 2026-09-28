import Foundation
import Network

enum DownloadSize {
    static func contentLength(of url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
            if http.expectedContentLength > 0 { return http.expectedContentLength }
            if let raw = http.value(forHTTPHeaderField: "Content-Length"), let value = Int64(raw), value > 0 {
                return value
            }
            return nil
        } catch {
            return nil
        }
    }
}

enum CellularAccess {
    static func usesCellular() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                let cellular = path.status == .satisfied && (path.usesInterfaceType(.cellular) || path.isExpensive)
                continuation.resume(returning: cellular)
            }
            monitor.start(queue: DispatchQueue(label: "gtl.cellular"))
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

@MainActor
enum DownloadEvents {
    static var completion: (() -> Void)?

    static func finish() {
        let handler = completion
        completion = nil
        handler?()
    }
}

@MainActor
final class MapDownloader: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((String, Double) -> Void)?
    var onFinished: ((String, URL) -> Void)?
    var onFailed: ((String, String) -> Void)?
    private let budgets = DownloadBudgets()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.lkovari.mobile.apps.gtl.maps")
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func start(_ url: URL, id: String, byteBudget: Int64) {
        budgets.set(id, budget: byteBudget)
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        task.resume()
    }

    func cancel(_ id: String) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == id { task.cancel() }
        }
    }

    nonisolated static func freeSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        let cap = id == OsmCatalog.tuhuId ? DownloadBudget.maxTuhuDownloadBytes : DownloadBudget.maxOsmBytes
        let budget = budgets.budget(id) ?? cap
        let free = MapDownloader.freeSpace()
        if totalBytesWritten > cap {
            downloadTask.cancel()
            return
        }
        if totalBytesWritten > budget || free < DownloadBudget.reserveBytes {
            budgets.markSpaceStop(id)
            downloadTask.cancel()
            return
        }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.onProgress?(id, fraction) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: temp.path) {
                try FileManager.default.removeItem(at: temp)
            }
            try FileManager.default.moveItem(at: location, to: temp)
            Task { @MainActor in self.onFinished?(id, temp) }
        } catch {
            Task { @MainActor in self.onFailed?(id, error.localizedDescription) }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadEvents.finish()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        if budgets.takeSpaceStop(id) {
            let message = L10n.text("Not enough free space", "Nincs elég szabad hely")
            Task { @MainActor in self.onFailed?(id, message) }
            return
        }
        guard let error else { return }
        if error.localizedDescription.localizedCaseInsensitiveContains("cancel") { return }
        Task { @MainActor in self.onFailed?(id, error.localizedDescription) }
    }
}

private final class DownloadBudgets: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int64] = [:]
    private var spaceStops: Set<String> = []

    func set(_ id: String, budget: Int64) {
        lock.lock()
        values[id] = budget
        spaceStops.remove(id)
        lock.unlock()
    }

    func budget(_ id: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return values[id]
    }

    func markSpaceStop(_ id: String) {
        lock.lock()
        spaceStops.insert(id)
        lock.unlock()
    }

    func takeSpaceStop(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let stopped = spaceStops.contains(id)
        spaceStops.remove(id)
        return stopped
    }
}
