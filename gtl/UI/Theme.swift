import SwiftUI

enum GtlColor {
    static let chartSage = Color(red: 0xD8 / 255, green: 0xE4 / 255, blue: 0xD4 / 255)
    static let paper = Color(red: 0xF4 / 255, green: 0xF7 / 255, blue: 0xF1 / 255)
    static let nightInk = Color(red: 0x10 / 255, green: 0x20 / 255, blue: 0x27 / 255)
    static let hudTeal = Color(red: 0x1F / 255, green: 0x8A / 255, blue: 0x80 / 255)
    static let carmine = Color(red: 0xC1 / 255, green: 0x3B / 255, blue: 0x2E / 255)
    static let startBlue = Color(red: 0x15 / 255, green: 0x65 / 255, blue: 0xC0 / 255)
    static let trackingOrange = Color(red: 0xEF / 255, green: 0x6C / 255, blue: 0x00 / 255)
    static let titleMagenta = Color(red: 0xC2 / 255, green: 0x18 / 255, blue: 0x5B / 255)
    static let cockpit = Color(red: 0x07 / 255, green: 0x14 / 255, blue: 0x1C / 255)
    static let cockpitPanel = Color(red: 0x10 / 255, green: 0x25 / 255, blue: 0x30 / 255)
    static let hudCyan = Color(red: 0x3E / 255, green: 0xCF / 255, blue: 0xCF / 255)
    static let moonCream = Color(red: 0xE7 / 255, green: 0xF0 / 255, blue: 0xEA / 255)
    static let amber = Color(red: 0xE8 / 255, green: 0xA8 / 255, blue: 0x38 / 255)
}

enum L10n {
    static var hungarian: Bool {
        Locale.current.language.languageCode?.identifier == "hu"
    }

    static func text(_ en: String, _ hu: String) -> String { hungarian ? hu : en }
}

enum AppLinks {
    static let privacyPolicy = URL(string: "https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html")!
    static let supportMail = URL(string: "mailto:laszlo.kovary@gmail.com")!
    static let turistautakTerms = URL(string: "https://www.turistautak.hu/wiki/Turistautak.hu:Jogi_nyilatkozat")!
}

struct GtlBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(
            colors: scheme == .dark ? [GtlColor.cockpit, GtlColor.cockpitPanel] : [GtlColor.chartSage, GtlColor.paper],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
