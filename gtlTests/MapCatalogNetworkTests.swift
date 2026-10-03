import XCTest
@testable import gtl

// Hálózatot igényel, ezért alapból kimarad. Beküldés előtt kézzel:
// TEST_RUNNER_GTL_NETWORK_TESTS=1 xcodebuild test -scheme gtl -destination '…' -only-testing:gtlTests/MapCatalogNetworkTests
final class MapCatalogNetworkTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GTL_NETWORK_TESTS"] == "1",
            "Set GTL_NETWORK_TESTS=1 to check the live download catalog."
        )
    }

    func testEveryOsmRegionIsDownloadableWithinCap() async {
        for region in OsmCatalog.regions {
            let length = await headLength(region.url)
            XCTAssertNotNil(length, "\(region.id): \(region.url) is not reachable")
            if let length {
                XCTAssertLessThanOrEqual(length, DownloadBudget.maxOsmBytes, "\(region.id) is \(length) bytes, above maxOsmBytes")
            }
        }
    }

    func testTuhuIsDownloadableWithinCap() async {
        let length = await headLength(OsmCatalog.tuhuURL)
        XCTAssertNotNil(length, "\(OsmCatalog.tuhuURL) is not reachable")
        if let length {
            XCTAssertLessThanOrEqual(length, DownloadBudget.maxTuhuDownloadBytes)
        }
    }

    private func headLength(_ url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return http.expectedContentLength > 0 ? http.expectedContentLength : nil
    }
}
