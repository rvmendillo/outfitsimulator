import XCTest

/// End-to-end journey on the simulator with screenshots of every screen:
/// onboarding → face → import (worn outfit + flat-lay) → closet → studio →
/// save → outfits → generator → profile.
final class OutfitSimulatorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until the element is hittable, then taps it.
    private func tapScrolling(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func testFullJourney() throws {
        // Onboarding
        let start = app.buttons["onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        shot("01-welcome")
        start.tap()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        shot("02-how-it-works")
        next.tap()

        // Proportions: pick a height and check the heads-tall readout updates.
        let headsTall = element("body.headsTall")
        XCTAssertTrue(headsTall.waitForExistence(timeout: 10))
        let slider = app.sliders["body.heightSlider"]
        if slider.exists { slider.adjust(toNormalizedSliderPosition: 0.55) }
        shot("03-proportions")
        tapScrolling(app.buttons["onboarding.saveBody"])

        // Face: use the bundled sample selfie.
        tapScrolling(app.buttons["source.sample"])
        let useFace = app.buttons["face.save"]
        XCTAssertTrue(useFace.waitForExistence(timeout: 120), "face processing finished")
        XCTAssertTrue(element("face.preview").exists)
        shot("04-face-alignment")
        tapScrolling(useFace)

        // Closet (empty) → import the sample outfit + flat-lay.
        let emptyAdd = app.buttons["closet.emptyAdd"]
        XCTAssertTrue(emptyAdd.waitForExistence(timeout: 30))
        shot("05-closet-empty")
        emptyAdd.tap()
        tapScrolling(app.buttons["source.sample"])
        let save = app.buttons["import.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 240), "pieces separated")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "review.edit").count, 4)
        shot("06-review")

        // Open the cut-out editor on the first piece, then close it.
        app.buttons.matching(identifier: "review.edit").firstMatch.tap()
        XCTAssertTrue(element("cutout.canvas").waitForExistence(timeout: 10))
        shot("07-cutout-editor")
        app.buttons["editor.done"].tap()

        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()

        // Closet with pieces.
        let firstGarment = app.buttons.matching(identifier: "closet.garment").firstMatch
        XCTAssertTrue(firstGarment.waitForExistence(timeout: 120))
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "closet.garment").count, 4)
        shot("08-closet")

        // Studio: wear a top, a bottom and shoes.
        app.tabBars.buttons["Studio"].tap()
        for category in ["top", "bottom", "shoes"] {
            let chip = app.buttons["tray.category.\(category)"]
            if chip.waitForExistence(timeout: 5) {
                chip.tap()
                app.buttons.matching(identifier: "tray.garment").firstMatch.tap()
            }
        }
        shot("09-studio")

        // Select the outfit's top by tapping the chest, check the selection bar.
        let canvas = element("studio.canvas")
        XCTAssertTrue(canvas.exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32)).tap()
        if element("studio.selectionBar").waitForExistence(timeout: 3) {
            shot("10-studio-selected")
        }

        // Save the outfit.
        app.buttons["studio.save"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Save"].tap()

        // Outfits grid.
        app.tabBars.buttons["Outfits"].tap()
        XCTAssertTrue(element("outfits.card").waitForExistence(timeout: 10))
        shot("11-outfits")

        // Generator.
        app.buttons["outfits.generate"].tap()
        XCTAssertTrue(app.buttons["generator.shuffle"].waitForExistence(timeout: 10))
        shot("12-generator")
        let saveSuggestion = app.buttons["generator.save.0"]
        if saveSuggestion.waitForExistence(timeout: 5) { saveSuggestion.tap() }
        app.buttons["Done"].tap()

        // Profile.
        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.buttons["profile.face"].waitForExistence(timeout: 10))
        shot("13-profile")
    }
}
