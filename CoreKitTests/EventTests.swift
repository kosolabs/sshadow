import Common
import Foundation
import Testing

@testable import CoreKit

struct EventTests {
    private let source = Event.Source(
        name: "test",
        url: "user@host"
    )

    // MARK: - Level

    @Test func levelLabels() {
        #expect(Event.Level.info.label == "INFO")
        #expect(Event.Level.notice.label == "NOTICE")
        #expect(Event.Level.warning.label == "WARNING")
        #expect(Event.Level.error.label == "ERROR")
    }

    @Test func levelOrdersBySeverity() {
        #expect(Event.Level.info < .notice)
        #expect(Event.Level.notice < .warning)
        #expect(Event.Level.warning < .error)
    }

    // MARK: - logLine

    @Test func logLineWithDetail() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let event = Event(
            timestamp: timestamp,
            source: source,
            level: .info,
            category: .file,
            message: "Upload /f",
            detail: "42 KB"
        )
        #expect(
            event.logLine
                == "\(timestamp.formatted(.iso8601))  INFO  test  user@host  Upload /f  42 KB"
        )
    }

    @Test func logLineWithoutDetail() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let event = Event(
            timestamp: timestamp,
            source: source,
            level: .notice,
            category: .connection,
            message: "Connected to Server"
        )
        #expect(
            event.logLine
                == "\(timestamp.formatted(.iso8601))  NOTICE  test  user@host  Connected to Server"
        )
    }

    @Test func logLineError() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let event = Event(
            timestamp: timestamp,
            source: source,
            level: .error,
            category: .connection,
            message: "Lost connection to Server"
        )
        #expect(
            event.logLine
                == "\(timestamp.formatted(.iso8601))  ERROR  test  user@host  "
                + "Lost connection to Server"
        )
    }

    // MARK: - Identity

    @Test func distinctEventsHaveDistinctIDs() {
        let a = Event(
            timestamp: .now,
            source: source,
            level: .info,
            category: .file,
            message: "Upload /f"
        )
        let b = Event(
            timestamp: .now,
            source: source,
            level: .info,
            category: .file,
            message: "Upload /f"
        )
        #expect(a.id != b.id)
    }

    // MARK: - Codable round-trip

    @Test func eventWithDetailRoundTripsThroughJSON() throws {
        let event = Event(
            timestamp: Date.now,
            source: source,
            level: .warning,
            category: .sync,
            message: "Reconnecting to Server",
            detail: "Next attempt at 3:45 PM"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded == event)
    }

    @Test func eventWithoutDetailRoundTripsThroughJSON() throws {
        let event = Event(
            timestamp: Date.now,
            source: source,
            level: .info,
            category: .diagnostic,
            message: "Extension started"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(Event.self, from: data)

        #expect(decoded == event)
        #expect(decoded.detail == nil)
    }
}
