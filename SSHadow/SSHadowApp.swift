import OSLog
import SSHadowShared
import SwiftData
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "SSHadowApp"
)

@main
struct SSHadowApp: App {
    var body: some Scene {
        WindowGroup {
            if isUnitTesting {
                Text("Unit Testing")
            } else {
                ConnectionProfileListView()
            }
        }
        .modelContainer(
            for: ConnectionProfile.self,
            inMemory: isUITesting || isUnitTesting
        )
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    private var isUnitTesting: Bool {
        let result =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
            != nil
        logger.debug("isUnitTesting: \(result)")
        return result
    }
}
