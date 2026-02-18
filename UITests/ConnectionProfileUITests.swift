import XCTest

final class ConnectionProfileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConnectionCreationAndDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        let user = NSUserName()

        app.buttons["addConnectionButton"].firstMatch.click()

        app.textFields["nameField"].firstMatch.click()
        app.typeText("Test")

        app.textFields["hostField"].firstMatch.click()
        app.typeText("localhost")

        app.textFields["portField"].firstMatch.click()
        app.typeText("2248")

        app.textFields["pathField"].firstMatch.click()
        app.typeText("media")

        app.textFields["userField"].firstMatch.click()
        app.typeText(user)

        let error = app.staticTexts["Password is required"]
        XCTAssertFalse(error.exists)

        app.switches["enabledToggle"].firstMatch.click()

        XCTAssertTrue(error.waitForExistence(timeout: 2))

        app.switches["usePrivateKeyToggle"].firstMatch.click()
        app.links["Select Private Key…"].firstMatch.click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText("/tmp/id_ed25519")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let privateKeyPath = app.staticTexts["/tmp/id_ed25519"]
        XCTAssertTrue(privateKeyPath.waitForExistence(timeout: 2))

//        app.switches["enabledToggle"].firstMatch.click()
//        XCTAssertTrue(error.waitForNonExistence(timeout: 2))
//        XCTAssertTrue(app.switches["enabledToggle"].firstMatch.isEnabled)

        let link = app.buttons["connectionLink_\(user)@localhost:2248:media"]
        XCTAssertTrue(link.waitForExistence(timeout: 2))
        app.buttons["deleteConnectionButton"].firstMatch.click()

        XCTAssertTrue(link.waitForNonExistence(timeout: 2))
    }
}
