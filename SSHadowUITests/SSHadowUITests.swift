import XCTest

final class SSHadowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConnectionCreationAndDeletion() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        app.buttons["addConnectionButton"].firstMatch.click()

        app.textFields["nameField"].firstMatch.click()
        app.typeText("Test")

        app.textFields["hostField"].firstMatch.click()
        app.typeText("localhost")

        app.textFields["portField"].firstMatch.click()
        app.typeText("2222")

        app.textFields["pathField"].firstMatch.click()
        app.typeText("/tmp")

        app.textFields["userField"].firstMatch.click()
        app.typeText("myuser")

        let error = app.staticTexts["Password is required"]
        XCTAssertFalse(error.exists)

        app.switches["enabledToggle"].firstMatch.click()

        XCTAssertTrue(error.waitForExistence(timeout: 2))

        app.secureTextFields["passwordField"].firstMatch.click()
        app.typeText("mypass")

        let link = app.buttons["connectionLink_myuser@localhost:2222:/tmp"]
        XCTAssertTrue(link.waitForExistence(timeout: 2))

        app.buttons["deleteConnectionButton"].firstMatch.click()

        XCTAssertTrue(link.waitForNonExistence(timeout: 2))
    }
}
