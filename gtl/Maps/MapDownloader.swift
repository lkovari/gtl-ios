import Foundation

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
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.lkovari.mobile.apps.gtl.maps")
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func downloadOsm(_ region: OsmRegion) {
        guard DownloadBudget.canStart(contentLength: 0, usableSpace: freeSpace(), cap: DownloadBudget.maxOsmBytes) else {
            onFailed?(region.id, "Not enough free space")
            return
        }
        start(region.url, id: region.id)
    }

    func downloadTuhu() {
        let url = OsmCatalog.tuhuURL
        guard DownloadBudget.tuhuURLAllowed(url) else {
            onFailed?(OsmCatalog.tuhuId, "Download address is not allowed")
            return
        }
        start(url, id: OsmCatalog.tuhuId)
    }

    func cancel(_ id: String) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == id { task.cancel() }
        }
    }

    private func start(_ url: URL, id: String) {
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        task.resume()
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
        if totalBytesWritten > cap {
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
        guard let error, let id = task.taskDescription else { return }
        if error.localizedDescription.localizedCaseInsensitiveContains("cancel") { return }
        Task { @MainActor in self.onFailed?(id, error.localizedDescription) }
    }

    private func freeSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }
}
