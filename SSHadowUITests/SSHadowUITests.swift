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
        app.typeText("Media")

        app.textFields["hostField"].firstMatch.click()
        app.typeText("localhost")

        app.textFields["portField"].firstMatch.click()
        app.typeText("2222")

        app.textFields["pathField"].firstMatch.click()
        app.typeText("/tmp")

        app.textFields["userField"].firstMatch.click()
        app.typeText("myuser")

        app.secureTextFields["passwordField"].firstMatch.click()
        app.typeText("mypass")

        let link = app.buttons["connectionLink_myuser@localhost:2222:/tmp"]

        XCTAssertTrue(link.waitForExistence(timeout: 2))

        app.buttons["deleteConnectionButton"].firstMatch.click()

        XCTAssertTrue(link.waitForNonExistence(timeout: 2))
    }
}
