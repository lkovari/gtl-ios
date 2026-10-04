import Foundation

struct StationarySpeedGate {
    private(set) var stationary = true
    private var streak = 0

    mutating func reset() {
        stationary = true
        streak = 0
    }

    mutating func update(speed: Double, speedAccuracy: Double, displacement: Double?, horizontalAccuracy: Double) -> Float? {
        guard speed >= 0, speed.isFinite else { return nil }
        let significant: Bool
        if speedAccuracy >= 0 {
            significant = speed > speedAccuracy
        } else if let displacement, horizontalAccuracy >= 0 {
            significant = displacement > horizontalAccuracy
        } else {
            significant = false
        }
        if significant == stationary {
            streak += 1
            if streak >= 2 {
                stationary.toggle()
                streak = 0
            }
        } else {
            streak = 0
        }
        return stationary ? 0 : Float(speed)
    }
}

enum ThemeChoice: String, CaseIterable {
    case light
    case dark
}

enum ThemeResolver {
    static func choice(autoTheme: Bool, manual: ThemeChoice, daylight: Bool?) -> ThemeChoice? {
        guard autoTheme else { return manual }
        guard let daylight else { return nil }
        return daylight ? .light : .dark
    }
}

enum SolarDaylight {
    static let civilTwilightDegrees = -6.0

    static func elevationDegrees(date: Date, latitude: Double, longitude: Double) -> Double {
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let meanLongitude = normalized(280.460 + 0.9856474 * days)
        let anomaly = radians(normalized(357.528 + 0.9856003 * days))
        let eclipticLongitude = radians(meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly))
        let obliquity = radians(23.439 - 0.0000004 * days)
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealHours = (18.697374558 + 24.06570982441908 * days).truncatingRemainder(dividingBy: 24)
        let hourAngle = radians(siderealHours * 15 + longitude) - rightAscension
        let lat = radians(latitude)
        let value = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        return degrees(asin(max(-1, min(1, value))))
    }

    static func isDaylight(date: Date, latitude: Double, longitude: Double) -> Bool {
        elevationDegrees(date: date, latitude: latitude, longitude: longitude) > civilTwilightDegrees
    }

    static func civilTwilight(on day: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> (dawn: Date?, dusk: Date?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day)
        let step: TimeInterval = 600
        func above(_ date: Date) -> Bool { isDaylight(date: date, latitude: latitude, longitude: longitude) }
        var dawn: Date?
        var dusk: Date?
        var previous = start
        var previousAbove = above(start)
        var offset = step
        while offset <= 86_400 {
            let current = start.addingTimeInterval(offset)
            let currentAbove = above(current)
            if currentAbove != previousAbove {
                let crossing = refine(previous, current, risingTo: currentAbove, latitude: latitude, longitude: longitude)
                if currentAbove, dawn == nil {
                    dawn = crossing
                } else if !currentAbove, dusk == nil {
                    dusk = crossing
                }
            }
            previous = current
            previousAbove = currentAbove
            offset += step
        }
        return (dawn, dusk)
    }

    private static func refine(_ low: Date, _ high: Date, risingTo rising: Bool, latitude: Double, longitude: Double) -> Date {
        var a = low
        var b = high
        for _ in 0..<20 {
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            if isDaylight(date: mid, latitude: latitude, longitude: longitude) == rising {
                b = mid
            } else {
                a = mid
            }
        }
        return b
    }

    private static func normalized(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func radians(_ value: Double) -> Double { value * .pi / 180 }

    private static func degrees(_ value: Double) -> Double { value * 180 / .pi }
}
