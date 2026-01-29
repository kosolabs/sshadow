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
        
        status = .testing
        
        Task {
            status = await tester.test(config: config.snapshot())
        }
    }
}
