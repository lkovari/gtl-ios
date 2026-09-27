import CoreMotion
import Foundation

@MainActor
final class MotionSession {
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    var onMotion: ((CMDeviceMotion) -> Void)?
    var onPressure: ((CMAltitudeData) -> Void)?

    var altimeterAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func startLoggingSensors() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.onMotion?(data)
            }
        }
        guard altimeterAvailable else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            self?.onPressure?(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}
