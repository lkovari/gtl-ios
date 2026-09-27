import XCTest

final class GtlUITests: XCTestCase {
    func testDisclaimerLeadsToTracker() {
        let app = XCUIApplication()
        app.launchArguments = ["-disclaimer", "0"]
        app.launch()
        let accept = app.buttons["acceptDisclaimer"]
        if accept.waitForExistence(timeout: 5) {
            accept.tap()
        }
        XCTAssertTrue(app.staticTexts["brandTitle"].waitForExistence(timeout: 5))
        app.buttons["tab.map"].tap()
        XCTAssertTrue(app.buttons["locateMe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["clearTrack"].exists)
        XCTAssertTrue(app.buttons["mapLayers"].exists)
        app.buttons["tab.gps"].tap()
        XCTAssertTrue(app.staticTexts["Latitude"].waitForExistence(timeout: 5) || app.staticTexts["Szélesség"].waitForExistence(timeout: 5))
        app.buttons["tab.compass"].tap()
        app.buttons["mainMenu"].tap()
        let settings = app.buttons["Settings"]
        let hungarian = app.buttons["Beállítások"]
        if settings.waitForExistence(timeout: 3) {
            settings.tap()
        } else {
            hungarian.tap()
        }
        XCTAssertTrue(app.staticTexts["Usage"].waitForExistence(timeout: 5) || app.staticTexts["Használat"].waitForExistence(timeout: 5))
    }

    func testMapHudAboutHelpAndCompass() {
        let app = XCUIApplication()
        app.launchArguments = ["-disclaimer", "0"]
        app.launch()
        let accept = app.buttons["acceptDisclaimer"]
        if accept.waitForExistence(timeout: 5) {
            accept.tap()
        }
        app.buttons["tab.map"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mapHud"].waitForExistence(timeout: 5))
        app.buttons["tab.compass"].tap()
        XCTAssertTrue(app.buttons["compass.MAG"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["compass.TRUE"].exists)
        app.buttons["mainMenu"].tap()
        let about = app.buttons["About"]
        let aboutHu = app.buttons["Névjegy"]
        if about.waitForExistence(timeout: 3) {
            about.tap()
        } else {
            aboutHu.tap()
        }
        let osm = app.buttons["OSM. OpenStreetMap"]
        XCTAssertTrue(osm.waitForExistence(timeout: 5))
        osm.tap()
        XCTAssertTrue(app.links["OpenStreetMap website"].waitForExistence(timeout: 3) || app.links["OpenStreetMap weboldal"].exists)
        XCTAssertTrue(app.buttons["TUHU. Turistautak.hu"].exists)
        let repo = app.buttons["Original repository"]
        let repoHu = app.buttons["Eredeti tároló"]
        if repo.exists {
            repo.tap()
        } else {
            repoHu.tap()
        }
        XCTAssertTrue(app.links["https://bitbucket.org/laszlokovary/gtl-e/src/master/"].waitForExistence(timeout: 3))
        let copyright = app.buttons["Copyright"]
        let copyrightHu = app.buttons["Szerzői jog"]
        app.swipeUp()
        if copyright.waitForExistence(timeout: 2) {
            copyright.tap()
        } else {
            copyrightHu.tap()
        }
        let author = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "2014")).firstMatch
        if !author.waitForExistence(timeout: 3) {
            let lines = app.debugDescription.split(separator: "\n").filter {
                $0.contains("opyright") || $0.contains("2014") || $0.contains("Szerző") || $0.contains("Kő") || $0.contains("bitbucket")
            }
            XCTFail(lines.joined(separator: "\n"))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["mainMenu"].tap()
        let help = app.buttons["Help"]
        let helpHu = app.buttons["Súgó"]
        if help.waitForExistence(timeout: 3) {
            help.tap()
        } else {
            helpHu.tap()
        }
        XCTAssertTrue(app.buttons["OSM map options"].waitForExistence(timeout: 5) || app.buttons["OSM térkép opciók"].exists)
        app.swipeUp()
        let point = app.buttons["A stored trackpoint"]
        let pointHu = app.buttons["Egy tárolt pont"]
        if point.waitForExistence(timeout: 2) {
            point.tap()
        } else {
            pointHu.tap()
        }
        let kind = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "eventKind")).firstMatch
        if !kind.waitForExistence(timeout: 3) {
            let lines = app.debugDescription.split(separator: "\n").filter { $0.contains("event") || $0.contains("trackpoint") || $0.contains("tárolt") }
            XCTFail(lines.joined(separator: "\n"))
        }
    }
}
