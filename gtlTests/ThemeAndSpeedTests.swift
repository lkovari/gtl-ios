import UIKit
import XCTest
@testable import gtl

final class ThemeAndSpeedTests: XCTestCase {
    func testSpeedGateShowsDashWithoutSpeed() {
        var gate = StationarySpeedGate()
        XCTAssertNil(gate.update(speed: -1, speedAccuracy: 0.5, displacement: 0, horizontalAccuracy: 5))
    }

    func testSpeedGateKeepsZeroWhenSpeedIsWithinItsAccuracy() {
        var gate = StationarySpeedGate()
        for _ in 0..<5 {
            XCTAssertEqual(gate.update(speed: 1.4, speedAccuracy: 1.6, displacement: 3, horizontalAccuracy: 10), 0)
        }
    }

    func testSpeedGateUsesDisplacementWhenSpeedAccuracyIsMissing() {
        var gate = StationarySpeedGate()
        XCTAssertEqual(gate.update(speed: 1.4, speedAccuracy: -1, displacement: 4, horizontalAccuracy: 10), 0)
        XCTAssertEqual(gate.update(speed: 1.4, speedAccuracy: -1, displacement: 4, horizontalAccuracy: 10), 0)
        XCTAssertEqual(gate.update(speed: 1.4, speedAccuracy: -1, displacement: nil, horizontalAccuracy: 10), 0)
    }

    func testSpeedGateLeavesZeroAfterTwoSignificantSamples() {
        var gate = StationarySpeedGate()
        XCTAssertEqual(gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5), 0)
        XCTAssertEqual(gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5), 3)
        XCTAssertEqual(gate.update(speed: 3.2, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5), 3.2)
    }

    func testSpeedGateDoesNotFlickerOnOneNoisySample() {
        var gate = StationarySpeedGate()
        _ = gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5)
        _ = gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5)
        XCTAssertEqual(gate.update(speed: 0.3, speedAccuracy: 0.5, displacement: 0, horizontalAccuracy: 5), 0.3)
        XCTAssertEqual(gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5), 3)
        XCTAssertEqual(gate.update(speed: 0.3, speedAccuracy: 0.5, displacement: 0, horizontalAccuracy: 5), 0.3)
        XCTAssertEqual(gate.update(speed: 0.2, speedAccuracy: 0.5, displacement: 0, horizontalAccuracy: 5), 0)
    }

    func testSpeedGateResetStartsAtZero() {
        var gate = StationarySpeedGate()
        _ = gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5)
        _ = gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5)
        gate.reset()
        XCTAssertEqual(gate.update(speed: 3, speedAccuracy: 0.5, displacement: 3, horizontalAccuracy: 5), 0)
    }

    func testSolarElevationAtBudapestSummerNoon() throws {
        let noon = try XCTUnwrap(date("2026-06-21T10:46:00Z"))
        XCTAssertEqual(SolarDaylight.elevationDegrees(date: noon, latitude: 47.4979, longitude: 19.0402), 65.9, accuracy: 0.6)
    }

    func testDaylightFollowsCivilTwilight() throws {
        XCTAssertTrue(SolarDaylight.isDaylight(date: try XCTUnwrap(date("2026-06-21T10:00:00Z")), latitude: 47.4979, longitude: 19.0402))
        XCTAssertFalse(SolarDaylight.isDaylight(date: try XCTUnwrap(date("2026-06-21T23:00:00Z")), latitude: 47.4979, longitude: 19.0402))
        XCTAssertTrue(SolarDaylight.isDaylight(date: try XCTUnwrap(date("2026-06-21T23:00:00Z")), latitude: 69.6492, longitude: 18.9553))
        XCTAssertFalse(SolarDaylight.isDaylight(date: try XCTUnwrap(date("2026-12-21T10:00:00Z")), latitude: 78.2232, longitude: 15.6267))
    }

    func testCivilTwilightTimesBracketTheDay() throws {
        let budapest = try XCTUnwrap(TimeZone(identifier: "Europe/Budapest"))
        let day = try XCTUnwrap(date("2026-06-21T10:00:00Z"))
        let times = SolarDaylight.civilTwilight(on: day, latitude: 47.4979, longitude: 19.0402, timeZone: budapest)
        let dawn = try XCTUnwrap(times.dawn)
        let dusk = try XCTUnwrap(times.dusk)
        XCTAssertEqual(SolarDaylight.elevationDegrees(date: dawn, latitude: 47.4979, longitude: 19.0402), -6, accuracy: 0.2)
        XCTAssertEqual(SolarDaylight.elevationDegrees(date: dusk, latitude: 47.4979, longitude: 19.0402), -6, accuracy: 0.2)
        let hours = dusk.timeIntervalSince(dawn) / 3600
        XCTAssertGreaterThan(hours, 16.5)
        XCTAssertLessThan(hours, 18)
    }

    func testCivilTwilightIsEmptyUnderMidnightSun() throws {
        let tromso = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let times = SolarDaylight.civilTwilight(on: try XCTUnwrap(date("2026-06-21T10:00:00Z")), latitude: 69.6492, longitude: 18.9553, timeZone: tromso)
        XCTAssertNil(times.dawn)
        XCTAssertNil(times.dusk)
    }

    func testThemeResolver() {
        XCTAssertEqual(ThemeResolver.choice(autoTheme: true, manual: .dark, daylight: true), .light)
        XCTAssertEqual(ThemeResolver.choice(autoTheme: true, manual: .light, daylight: false), .dark)
        XCTAssertNil(ThemeResolver.choice(autoTheme: true, manual: .dark, daylight: nil))
        XCTAssertEqual(ThemeResolver.choice(autoTheme: false, manual: .dark, daylight: true), .dark)
        XCTAssertEqual(ThemeResolver.choice(autoTheme: false, manual: .light, daylight: false), .light)
    }

    @MainActor
    func testThemeSettingsRoundTripAndDefaults() throws {
        let suite = "gtl.theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var settings = store.load()
        XCTAssertTrue(settings.autoTheme)
        XCTAssertEqual(settings.manualTheme, .light)
        settings.autoTheme = false
        settings.manualTheme = .dark
        store.save(settings)
        let loaded = store.load()
        XCTAssertFalse(loaded.autoTheme)
        XCTAssertEqual(loaded.manualTheme, .dark)
    }

    func testDarkOfflinePaletteIsDarkAndKeepsTheTrackVisible() {
        let light = OfflineMapPalette.palette(dark: false)
        let dark = OfflineMapPalette.palette(dark: true)
        XCTAssertGreaterThan(OfflineMapPalette.luminance(light.background), 0.7)
        XCTAssertLessThan(OfflineMapPalette.luminance(dark.background), 0.05)
        XCTAssertGreaterThan(OfflineMapPalette.contrast(dark.labelInk, dark.background), 7)
        XCTAssertGreaterThan(OfflineMapPalette.contrast(dark.trackCasing, dark.background), 3)
        XCTAssertEqual(light.trackCasing.cgColor.alpha, 0)
    }

    private func date(_ iso: String) -> Date? {
        ISO8601DateFormatter().date(from: iso)
    }
}
