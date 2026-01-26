import SwiftUI

@Observable class ConnectionTestViewModel {
    private let tester: ConnectionTester

    var status: ConnectionTestStatus = .notStarted

    init(tester: ConnectionTester = DefaultConnectionTester()) {
        self.tester = tester
    }

    func test(_ config: ConnectionConfig) {
        guard status != .testing else {
            return
        }

        guard let password = config.password else {
            status = .invalidConfig("Password is required")
            return
        }

        status = .testing

        Task {
            status = await tester.test(
                host: config.host,
                port: config.effectivePort,
                user: config.effectiveUser,
                password: password,
                path: config.path ?? "."
            )
        }
    }
}
