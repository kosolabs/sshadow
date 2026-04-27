import AgentKit
import Common
import SwiftData
import SwiftUI

private let logger = Logger(category: "SSHadowApp")

private class AppXPCService {
    static let shared = AppXPCService()

    private let delegate = AgentListenerDelegate()
    private let listener: NSXPCListener

    private init() {
        listener = NSXPCListener(machServiceName: SSHadow.appServiceName)
        listener.delegate = delegate
        listener.resume()
        logger.info("App XPC: listening on \(SSHadow.appServiceName)")
    }
}

@main
struct SSHadowApp: App {
    init() {
        _ = AppXPCService.shared
    }

    var body: some Scene {
        WindowGroup {
            ConnectionProfileListView()
        }
        .modelContainer(
            try! AppDB.getModelContainer(
                config: ModelConfiguration(
                    isStoredInMemoryOnly: ProcessInfo.processInfo.arguments
                        .contains("-uiTesting")
                )
            )
        )
    }
}
