import SwiftUI
import UIKit

@main
struct GtlApp: App {
    @UIApplicationDelegateAdaptor(GtlAppDelegate.self) private var appDelegate
    @State private var model = TrackerModel()

    init() {
        ErrorLogStore.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(nil)
        }
    }
}

final class GtlAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadEvents.completion = completionHandler
    }
}

struct RootView: View {
    @Bindable var model: TrackerModel

    var body: some View {
        Group {
            if model.settings.disclaimerAccepted {
                TrackerScreen(model: model)
            } else {
                DisclaimerScreen(model: model)
            }
        }
        .tint(GtlColor.hudTeal)
    }
}

struct DisclaimerScreen: View {
    @Bindable var model: TrackerModel
    @Environment(\.colorScheme) private var scheme
    @State private var refused = false

    var body: some View {
        ZStack {
            GtlBackground()
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text("Drive safely", "Vezess biztonságosan"))
                    .font(.title.bold())
                    .foregroundStyle(GtlColor.titleMagenta)
                Text(L10n.text(
                    "GTL records your route on this phone. The logged track is not uploaded to our server. The map, search, a route, and an address send Apple the coordinate needed for that request. Do not interact with the app while driving. You use it at your own risk. While logging, iOS shows the location indicator.",
                    "A GTL ezen a telefonon rögzíti az útvonalat. A naplózott track nem kerül a szerverünkre. A térkép, a keresés, az útvonal és a cím az Apple-nek küldi az ehhez szükséges koordinátát. Vezetés közben ne használd az appot. Saját felelősségre használod. Naplózás közben az iOS helyjelzője látható."
                ))
                .foregroundStyle(scheme == .dark ? GtlColor.moonCream : GtlColor.nightInk)
                Link(L10n.text("Privacy policy", "Adatvédelmi nyilatkozat"), destination: AppLinks.privacyPolicy)
                    .foregroundStyle(GtlColor.titleMagenta)
                if refused {
                    Text(L10n.text(
                        "Recording stays off until you accept.",
                        "A rögzítés addig nem indul, amíg el nem fogadod."
                    ))
                    .foregroundStyle(scheme == .dark ? GtlColor.moonCream : GtlColor.nightInk)
                }
                Spacer()
                Button(L10n.text("Accept", "Elfogadom")) { model.acceptDisclaimer() }
                    .buttonStyle(GtlPrimaryButton(color: GtlColor.startBlue))
                    .accessibilityIdentifier("acceptDisclaimer")
                Button(L10n.text("Refuse", "Elutasítom")) { refused = true }
                    .buttonStyle(GtlPrimaryButton(color: GtlColor.trackingOrange))
            }
            .padding(24)
        }
    }
}

struct GtlPrimaryButton: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
