import Foundation
import SwiftData
import SwiftRussh
import TestKit
import Testing

@testable import CoreKit

let unrelatedHostKey = SSHHostKey(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALP5YSWXJpkjStnmSGSkkeXGkyryGvYLszMja86gYhe"
)!

let otherHostKey = SSHHostKey(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJPMbVowdKZSDAn56iKjZksoOz6TBE3rlxKsgKkWjWp/"
)!

struct HostKeyTrustTests {
    @Test func trustedHostKeyIsEffective() {
        let model = ConnectionConfigModel(host: "example.com", port: 2222)

        model.trustHostKey(unrelatedHostKey)

        #expect(model.effectiveHostKey == unrelatedHostKey)
    }

    @Test func hostKeyTrustedForAnotherPortIsIgnored() {
        let model = ConnectionConfigModel(host: "example.com", port: 2222)
        model.trustHostKey(unrelatedHostKey)

        model.port = 2223

        #expect(model.effectiveHostKey == nil)
    }

    @Test func hostKeyTrustedForAnotherHostIsIgnored() {
        let model = ConnectionConfigModel(host: "example.com")
        model.trustHostKey(unrelatedHostKey)

        model.host = "example.org"

        #expect(model.effectiveHostKey == nil)
    }

    @Test(arguments: ["example.com", "example.com ssh-ed25519 not*base64"])
    func malformedHostKeyIsIgnored(_ hostKey: String) {
        let model = ConnectionConfigModel(host: "example.com")
        model.hostKey = hostKey

        #expect(model.effectiveHostKey == nil)
    }

    @MainActor
    @Test func trustingAHostKeyLogsItsFingerprint() async {
        let name = UUID().uuidString
        let model = ConnectionConfigModel(name: name, host: "example.com")

        model.trustHostKey(unrelatedHostKey)

        await expect(eventually: {
            trustNotice(for: name)?.detail
                == "\(unrelatedHostKey.fingerprint) for example.com"
        })
    }

    @MainActor
    @Test func replacingAHostKeyLogsTheOldFingerprint() async {
        let name = UUID().uuidString
        let model = ConnectionConfigModel(name: name, host: "example.com")
        model.trustHostKey(otherHostKey)

        model.trustHostKey(unrelatedHostKey)

        await expect(eventually: {
            trustNotice(for: name)?.detail
                == "\(unrelatedHostKey.fingerprint) for example.com, replacing \(otherHostKey.fingerprint)"
        })
    }

    @Test func configRequiresATrustedHostKey() {
        let model = ConnectionConfigModel(host: "example.com")

        #expect(throws: ConnectionConfig.ValidationError.hostKeyUnknown) {
            try ConnectionConfig(
                from: model,
                settings: SettingsModel(),
                authMethod: .none
            )
        }
    }

    @Test func configCarriesTheTrustedHostKey() throws {
        let model = ConnectionConfigModel(host: "example.com")
        model.trustHostKey(unrelatedHostKey)

        let config = try ConnectionConfig(
            from: model,
            settings: SettingsModel(),
            authMethod: .none
        )

        #expect(config.hostKey == unrelatedHostKey)
    }

    @Test func resolveHostKeyTrustsTheServersKey() async throws {
        let sandbox = TestSandbox()
        let model = ConnectionConfigModel(host: sandbox.host, port: sandbox.port)

        try await withConnectRetries {
            () async throws(ConnectionError) in
            try await model.resolveHostKey()
        }

        #expect(model.effectiveHostKey == (try sandbox.serverHostKey))
    }

    @Test func resolveHostKeyForRefusedPortTrustsNothing() async throws {
        let model = ConnectionConfigModel(host: "localhost", port: 2223)

        await #expect(throws: ConnectionError.connectionRefused) {
            try await model.resolveHostKey()
        }
        #expect(model.hostKey == nil)
    }
}

@MainActor
private let sharedEventStore: ModelContainer = {
    let store = try! makeEventStore()
    Events.shared.persist(in: store)
    return store
}()

@MainActor
private func trustNotice(for name: String) -> Event? {
    sharedEventStore.savedEvents.last {
        $0.source?.name == name && $0.message == "Trusted host key for \(name)"
    }
}
