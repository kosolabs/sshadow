import Common
import Foundation
import Testing

@testable import CoreKit

struct EventTests {
    // MARK: - Operation.description

    @Test func createSymlinkDescription() {
        let operation = Event.Operation.createSymlink(
            path: "/link",
            target: "/target"
        )
        #expect(operation.description == "create symlink from /link to /target")
    }

    @Test func createDirectoryDescription() {
        let operation = Event.Operation.createDirectory(path: "/dir")
        #expect(operation.description == "create directory at /dir")
    }

    @Test func moveDescription() {
        let operation = Event.Operation.move(from: "/a", to: "/b")
        #expect(operation.description == "move /a to /b")
    }

    @Test func removeDescription() {
        let kind = Item.Kind.file
        let operation = Event.Operation.remove(path: "/f", kind: kind)
        #expect(operation.description == "remove \(kind) /f")
    }

    @Test func uploadDescription() {
        #expect(Event.Operation.upload(path: "/f").description == "upload /f")
    }

    @Test func downloadDescription() {
        #expect(Event.Operation.download(path: "/f").description == "download /f")
    }

    @Test func setAttributesWithOnlyFlags() {
        let flags = Item.Flags.rw
        let operation = Event.Operation.setAttributes(
            path: "/f",
            flags: flags,
            accessTime: nil,
            modifyTime: nil
        )
        #expect(
            operation.description == "set attributes of /f to permissions: \(flags)"
        )
    }

    @Test func setAttributesWithNoChanges() {
        let operation = Event.Operation.setAttributes(
            path: "/f",
            flags: nil,
            accessTime: nil,
            modifyTime: nil
        )
        #expect(operation.description == "set attributes of /f to ")
    }

    @Test func setAttributesWithAllChanges() {
        let flags = Item.Flags.all
        let accessTime = Date(timeIntervalSince1970: 1_000)
        let modifyTime = Date(timeIntervalSince1970: 2_000)
        let operation = Event.Operation.setAttributes(
            path: "/f",
            flags: flags,
            accessTime: accessTime,
            modifyTime: modifyTime
        )
        #expect(
            operation.description == "set attributes of /f to "
                + "permissions: \(flags), accessTime: \(accessTime), "
                + "modifyTime: \(modifyTime)"
        )
    }

    // MARK: - Codable round-trip

    @Test func eventRoundTripsThroughJSON() throws {
        let event = Event(
            timestamp: Date.now,
            operation: .setAttributes(
                path: "/f",
                flags: .rw,
                accessTime: Date(timeIntervalSince1970: 1_000),
                modifyTime: nil
            ),
            outcome: .succeeded(detail: "done")
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded == event)
    }

    @Test(arguments: [
        Event.Outcome.succeeded(detail: nil),
        Event.Outcome.succeeded(detail: "detail"),
        Event.Outcome.failed(reason: "boom"),
        Event.Outcome.cancelled,
    ])
    func outcomeRoundTripsThroughJSON(outcome: Event.Outcome) throws {
        let event = Event(
            timestamp: Date.now,
            operation: .upload(path: "/f"),
            outcome: outcome
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded == event)
    }
}
