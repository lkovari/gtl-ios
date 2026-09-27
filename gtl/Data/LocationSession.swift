import CoreLocation
import Foundation

@MainActor
final class LocationSession: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var recording = false
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

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func requestAlways() { manager.requestAlwaysAuthorization() }

    func startLogging(activity: CLActivityType) {
        recording = true
        manager.activityType = activity
        manager.pausesLocationUpdatesAutomatically = false
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
    }

    func stopLogging() {
        recording = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
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
        Task { @MainActor in self.onAuthorization?(status) }
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
    var course: Double
    var timestamp: Date
}

struct RecordedHeading: Sendable {
    var trueHeading: Double
    var magneticHeading: Double
    var headingAccuracy: Double
}
