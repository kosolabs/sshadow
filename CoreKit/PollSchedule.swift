import Common
import Foundation

public struct PollSettings: Message, CustomStringConvertible {
    public let interval: Duration
    public let idleThreshold: Duration
    public let watchedInterval: Duration
    public let watchedIdleThreshold: Duration

    public init(
        interval: Duration,
        idleThreshold: Duration,
        watchedInterval: Duration,
        watchedIdleThreshold: Duration
    ) {
        self.interval = interval
        self.idleThreshold = idleThreshold
        self.watchedInterval = watchedInterval
        self.watchedIdleThreshold = watchedIdleThreshold
    }

    public var description: String {
        "PollSettings(interval: \(interval), idleThreshold: \(idleThreshold), "
            + "watchedInterval: \(watchedInterval), "
            + "watchedIdleThreshold: \(watchedIdleThreshold))"
    }
}

class PollSchedule {
    static let requestQuietPeriod: Duration = .seconds(1)

    enum Operation: Equatable {
        case pollAll
        case pollWatched
        case wait
    }

    private(set) var settings: PollSettings?
    private var lastPollAll: ContinuousClock.Instant
    private var lastPollWatched: ContinuousClock.Instant?
    private var pollAllRequestedAt: ContinuousClock.Instant?

    init(begin now: ContinuousClock.Instant, settings: PollSettings?) {
        self.settings = settings
        lastPollAll = now
        lastPollWatched = now
    }

    func next(
        now: ContinuousClock.Instant,
        userIdle: Duration
    ) -> Operation {
        if let pollAllRequestedAt,
            now - pollAllRequestedAt >= Self.requestQuietPeriod
        {
            return .pollAll
        }
        guard let settings else { return .wait }
        if isDue(
            now,
            since: lastPollAll,
            interval: settings.interval,
            userIdle: userIdle,
            idleThreshold: settings.idleThreshold
        ) {
            return .pollAll
        }
        if isDue(
            now,
            since: lastPollWatched,
            interval: settings.watchedInterval,
            userIdle: userIdle,
            idleThreshold: settings.watchedIdleThreshold
        ) {
            return .pollWatched
        }
        return .wait
    }

    func update(settings: PollSettings?) {
        self.settings = settings
    }

    func requestPollAll(at now: ContinuousClock.Instant) {
        pollAllRequestedAt = now
    }

    func recordPollAll(at now: ContinuousClock.Instant) {
        pollAllRequestedAt = nil
        lastPollAll = now
        lastPollWatched = now
    }

    func recordPollWatched(at now: ContinuousClock.Instant) {
        lastPollWatched = now
    }

    func recordWatchStarted() {
        lastPollWatched = nil
    }

    private func isDue(
        _ now: ContinuousClock.Instant,
        since last: ContinuousClock.Instant?,
        interval: Duration,
        userIdle: Duration,
        idleThreshold: Duration
    ) -> Bool {
        guard userIdle < idleThreshold else { return false }
        guard let last else { return true }
        return now - last >= interval
    }
}
