import Foundation
import SwiftData

@Model
public class SettingsModel {
    public var ignoreFilenames: [String]?
    public var pollsAutomatically: Bool?
    public var pollIntervalSeconds: Int?
    public var pollIdleThresholdSeconds: Int?
    public var watchedPollIntervalSeconds: Int?
    public var watchedPollIdleThresholdSeconds: Int?
    public var connectTimeoutSeconds: Int?
    public var maxReconnectDelaySeconds: Int?

    public init() {}
}

// MARK: - Defaults

extension SettingsModel {
    public static let defaultIgnoreFilenames = [".sshadowignore"]
    public static let defaultPollsAutomatically = true
    public static let defaultPollInterval: Duration = .seconds(300)
    public static let defaultPollIdleThreshold: Duration = .seconds(600)
    public static let defaultWatchedPollInterval: Duration = .seconds(10)
    public static let defaultWatchedPollIdleThreshold: Duration = .seconds(120)
    public static let defaultConnectTimeout: Duration = .seconds(60)
    public static let defaultMaxReconnectDelay: Duration = .seconds(60)
}

// MARK: - Effective Values

extension SettingsModel {
    public var effectiveIgnoreFilenames: [String] {
        ignoreFilenames ?? Self.defaultIgnoreFilenames
    }

    public var effectivePollsAutomatically: Bool {
        pollsAutomatically ?? Self.defaultPollsAutomatically
    }

    public var effectivePollInterval: Duration {
        duration(pollIntervalSeconds) ?? Self.defaultPollInterval
    }

    public var effectivePollIdleThreshold: Duration {
        duration(pollIdleThresholdSeconds) ?? Self.defaultPollIdleThreshold
    }

    public var effectiveWatchedPollInterval: Duration {
        duration(watchedPollIntervalSeconds) ?? Self.defaultWatchedPollInterval
    }

    public var effectiveWatchedPollIdleThreshold: Duration {
        duration(watchedPollIdleThresholdSeconds)
            ?? Self.defaultWatchedPollIdleThreshold
    }

    public var effectiveConnectTimeout: Duration {
        duration(connectTimeoutSeconds) ?? Self.defaultConnectTimeout
    }

    public var effectiveMaxReconnectDelay: Duration {
        duration(maxReconnectDelaySeconds) ?? Self.defaultMaxReconnectDelay
    }

    public var effectivePoll: PollSettings? {
        guard effectivePollsAutomatically else { return nil }
        return PollSettings(
            interval: effectivePollInterval,
            idleThreshold: effectivePollIdleThreshold,
            watchedInterval: effectiveWatchedPollInterval,
            watchedIdleThreshold: effectiveWatchedPollIdleThreshold
        )
    }

    private func duration(_ seconds: Int?) -> Duration? {
        seconds.map { .seconds($0) }
    }
}

// MARK: - Ignore Files

extension SettingsModel {
    public var customizesIgnoreFiles: Bool {
        get { ignoreFilenames != nil }
        set { ignoreFilenames = newValue ? effectiveIgnoreFilenames : nil }
    }
}

// MARK: - Poll Frequency

extension SettingsModel {
    public enum PollFrequency: Hashable, Sendable {
        case automatic(intervalSeconds: Int?)
        case manual
    }

    public var pollFrequency: PollFrequency {
        get {
            effectivePollsAutomatically
                ? .automatic(intervalSeconds: pollIntervalSeconds)
                : .manual
        }
        set {
            switch newValue {
            case .automatic(let intervalSeconds):
                pollsAutomatically = nil
                pollIntervalSeconds = intervalSeconds
            case .manual:
                pollsAutomatically = false
                pollIntervalSeconds = nil
            }
        }
    }
}

// MARK: - Validation

extension SettingsModel {
    public func validate() throws(ConnectionConfig.ValidationError) {
        try ConnectionConfig.validate(ignoreFilenames: effectiveIgnoreFilenames)
    }
}

// MARK: - Storage

extension ModelContext {
    public func settings() throws -> SettingsModel {
        if let settings = try fetch(FetchDescriptor<SettingsModel>()).first {
            return settings
        }
        let settings = SettingsModel()
        insert(settings)
        return settings
    }
}
