import CoreLocation
import Foundation

enum BackgroundLogging {
    static func isActive(recording: Bool, authorization: CLAuthorizationStatus) -> Bool {
        recording && (authorization == .authorizedWhenInUse || authorization == .authorizedAlways)
    }
}

enum LocationBlock: Equatable {
    case denied
    case preciseRequired
}

enum LocationPrompt: Equatable {
    case requestWhenInUse
    case beginRecording
    case blocked(LocationBlock)
}

enum LocationStart {
    static func decide(authorization: CLAuthorizationStatus) -> LocationPrompt {
        switch authorization {
        case .notDetermined: return .requestWhenInUse
        case .authorizedWhenInUse, .authorizedAlways: return .beginRecording
        case .denied, .restricted: return .blocked(.denied)
        @unknown default: return .blocked(.denied)
        }
    }

    static func resumeAfterGrant(pendingStart: Bool, authorization: CLAuthorizationStatus) -> LocationPrompt? {
        guard pendingStart else { return nil }
        let prompt = decide(authorization: authorization)
        return prompt == .requestWhenInUse ? nil : prompt
    }
}

enum LoggingStart {
    static func admit(databaseAvailable: Bool, sessionId: Int64?) -> Bool {
        databaseAvailable && sessionId != nil
    }
}

@MainActor
final class LocationSession: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var recording = false
    private var backgroundActivity: CLBackgroundActivitySession?
    var onFix: ((RecordedFix) -> Void)?
    var onHeading: ((RecordedHeading) -> Void)?
    var onAuthorization: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .otherNavigation
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    var accuracyAuthorization: CLAccuracyAuthorization { manager.accuracyAuthorization }

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
              let location = manager.location else { return nil }
        return location.coordinate
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func ensurePreciseRoute() async -> Bool {
        if manager.accuracyAuthorization == .fullAccuracy { return true }
        return await withCheckedContinuation { continuation in
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseRoute") { error in
                Task { @MainActor in
                    let granted = error == nil && self.manager.accuracyAuthorization == .fullAccuracy
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startLogging(activity: CLActivityType) {
        recording = true
        manager.activityType = activity
        manager.pausesLocationUpdatesAutomatically = false
        syncBackgroundLogging()
        manager.startUpdatingLocation()
    }

    func stopLogging() {
        recording = false
        manager.stopUpdatingLocation()
        syncBackgroundLogging()
    }

    private func syncBackgroundLogging() {
        if BackgroundLogging.isActive(recording: recording, authorization: manager.authorizationStatus) {
            if backgroundActivity == nil {
                backgroundActivity = CLBackgroundActivitySession()
            }
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = false
            return
        }
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        if !recording {
            manager.pausesLocationUpdatesAutomatically = true
        }
    }

    func startWatching() {
        if recording { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.startUpdatingLocation()
    }

    func stopWatching() {
        if recording { return }
        manager.stopUpdatingLocation()
    }

    func requestOneFix() { manager.requestLocation() }

    func startHeading() {
        manager.headingFilter = 2
        manager.startUpdatingHeading()
    }

    func stopHeading() { manager.stopUpdatingHeading() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            RecordedFix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                altitude: location.altitude,
                ellipsoidalAltitude: location.ellipsoidalAltitude,
                speed: location.speed,
                speedAccuracy: location.speedAccuracy,
                course: location.course,
                timestamp: location.timestamp
            )
        }
        Task { @MainActor in fixes.forEach { self.onFix?($0) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = RecordedHeading(
            trueHeading: newHeading.trueHeading,
            magneticHeading: newHeading.magneticHeading,
            headingAccuracy: newHeading.headingAccuracy
        )
        Task { @MainActor in self.onHeading?(heading) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.syncBackgroundLogging()
            self.onAuthorization?(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct RecordedFix: Sendable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var altitude: Double
    var ellipsoidalAltitude: Double
    var speed: Double
    var speedAccuracy: Double
    var course: Double
    var timestamp: Date
}

struct RecordedHeading: Sendable {
    var trueHeading: Double
    var magneticHeading: Double
    var headingAccuracy: Double
}
