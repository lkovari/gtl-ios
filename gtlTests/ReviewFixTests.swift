import CoreLocation
import XCTest
@testable import gtl

final class ReviewFixTests: XCTestCase {
    func testStartDecisionForEachAuthorization() {
        XCTAssertEqual(LocationStart.decide(authorization: .notDetermined), .requestWhenInUse)
        XCTAssertEqual(LocationStart.decide(authorization: .authorizedWhenInUse), .beginRecording)
        XCTAssertEqual(LocationStart.decide(authorization: .authorizedAlways), .beginRecording)
        XCTAssertEqual(LocationStart.decide(authorization: .denied), .blocked(.denied))
        XCTAssertEqual(LocationStart.decide(authorization: .restricted), .blocked(.denied))
        XCTAssertNotEqual(LocationStart.decide(authorization: .denied), .beginRecording)
    }

    func testPendingStartResumesAfterGrant() {
        XCTAssertNil(LocationStart.resumeAfterGrant(pendingStart: false, authorization: .authorizedWhenInUse))
        XCTAssertNil(LocationStart.resumeAfterGrant(pendingStart: true, authorization: .notDetermined))
        XCTAssertEqual(LocationStart.resumeAfterGrant(pendingStart: true, authorization: .authorizedWhenInUse), .beginRecording)
        XCTAssertEqual(LocationStart.resumeAfterGrant(pendingStart: true, authorization: .authorizedAlways), .beginRecording)
        XCTAssertEqual(LocationStart.resumeAfterGrant(pendingStart: true, authorization: .denied), .blocked(.denied))
    }

    func testLoggingStartsOnlyWithAnOpenDatabaseAndASession() {
        XCTAssertFalse(LoggingStart.admit(databaseAvailable: false, sessionId: nil))
        XCTAssertFalse(LoggingStart.admit(databaseAvailable: true, sessionId: nil))
        XCTAssertTrue(LoggingStart.admit(databaseAvailable: true, sessionId: 3))
    }

    func testDownloadAcceptsOnlySuccessStatus() {
        XCTAssertTrue(DownloadResponse.accept(statusCode: 200))
        XCTAssertTrue(DownloadResponse.accept(statusCode: 204))
        XCTAssertFalse(DownloadResponse.accept(statusCode: 404))
        XCTAssertFalse(DownloadResponse.accept(statusCode: 503))
        XCTAssertFalse(DownloadResponse.accept(statusCode: 0))
    }

    func testPoorGpsNoticeShowsOnlyWhileLogging() {
        XCTAssertTrue(MapGpsNotice.visible(logging: true, poorGps: true))
        XCTAssertFalse(MapGpsNotice.visible(logging: false, poorGps: true))
        XCTAssertFalse(MapGpsNotice.visible(logging: true, poorGps: false))
    }

    func testMapAttributionIsEmptyOnlineAndNamesTheOfflineSource() {
        XCTAssertNil(MapAttribution.text(effectiveOffline: false, selectedMapId: "eu-hungary"))
        XCTAssertNil(MapAttribution.text(effectiveOffline: false, selectedMapId: OsmCatalog.tuhuId))
        XCTAssertEqual(MapAttribution.text(effectiveOffline: true, selectedMapId: "eu-hungary"), "© OpenStreetMap contributors")
        XCTAssertEqual(MapAttribution.text(effectiveOffline: true, selectedMapId: OsmCatalog.tuhuId), "© Turistautak.hu")
    }

    func testCatalogUsesTheHttpsMirrorAndNoEuPrefix() {
        for region in OsmCatalog.regions {
            XCTAssertEqual(region.url.scheme, "https", region.id)
            XCTAssertEqual(region.url.host, "ftp-stud.hs-esslingen.de", region.id)
            XCTAssertTrue(region.url.path.hasPrefix("/Mirrors/download.mapsforge.org/maps/v5/"), region.id)
            XCTAssertFalse(region.label.hasPrefix("EU "), region.id)
        }
        XCTAssertEqual(OsmCatalog.tuhuURL.host, "turistautak.elte.hu")
    }

    func testCatalogTitlesKeepSubnationalRegionsApart() {
        let english = Locale(identifier: "en_US")
        func title(_ id: String) -> String {
            let region = OsmCatalog.regions.first { $0.id == id }
            XCTAssertNotNil(region, id)
            return region.map { OsmCatalog.localizedTitle($0, hungarian: false, locale: english) } ?? ""
        }
        let britain = Set([title("eu-england"), title("eu-scotland"), title("eu-wales")])
        XCTAssertEqual(britain, ["England", "Scotland", "Wales"])
        XCTAssertNotEqual(title("us-california"), title("us-texas"))
        XCTAssertEqual(title("eu-germany"), "Germany")
        XCTAssertFalse(title("eu-germany").hasPrefix("EU "))
        let hungarian = OsmCatalog.regions.first { $0.id == "eu-england" }.map { OsmCatalog.localizedTitle($0, hungarian: true, locale: Locale(identifier: "hu_HU")) }
        XCTAssertEqual(hungarian, "Anglia")
    }

    func testCatalogGroupsFollowTheRegionOrder() {
        let groups = OsmCatalog.groups(hungarian: false)
        XCTAssertEqual(groups.map(\.title), ["Europe", "Asia", "North America", "South America", "Australia and Oceania"])
        XCTAssertEqual(groups.flatMap(\.regions).map(\.id), OsmCatalog.regions.map(\.id))
        XCTAssertEqual(OsmCatalog.groups(hungarian: true).first?.title, "Európa")
    }

    func testDownloadDoesNotStartWhenFreeSpaceIsUnknown() {
        XCTAssertFalse(DownloadBudget.canStart(contentLength: 10, usableSpace: nil, cap: DownloadBudget.maxOsmBytes))
        XCTAssertTrue(DownloadBudget.canStart(contentLength: 10, usableSpace: DownloadBudget.reserveBytes + 100, cap: DownloadBudget.maxOsmBytes))
    }

    func testUnpackNeedsRoomForTheExtractedFilesAndTheReserve() {
        let reserve = DownloadBudget.reserveBytes
        XCTAssertFalse(DownloadBudget.canUnpack(uncompressedBytes: 500, usableSpace: nil))
        XCTAssertFalse(DownloadBudget.canUnpack(uncompressedBytes: 500, usableSpace: reserve + 499))
        XCTAssertTrue(DownloadBudget.canUnpack(uncompressedBytes: 500, usableSpace: reserve + 500))
    }
}
