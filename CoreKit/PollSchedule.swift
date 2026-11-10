import Common
import Foundation

public struct PollSettings: Message {
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
}

class PollSchedule {
    enum Operation: Equatable {
        case pollAll
        case pollWatched
        case wait
    }

    private let settings: PollSettings
    private var lastPollAll: ContinuousClock.Instant
    private var lastPollWatched: ContinuousClock.Instant?
    private var pollAllRequested = false

    init(begin now: ContinuousClock.Instant, settings: PollSettings) {
        self.settings = settings
        lastPollAll = now
        lastPollWatched = now
    }

    func next(
        now: ContinuousClock.Instant,
        userIdle: Duration
    ) -> Operation {
        if pollAllRequested {
            return .pollAll
        }
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

    func requestPollAll() {
        pollAllRequested = true
    }

    func recordPollAll(at now: ContinuousClock.Instant) {
        pollAllRequested = false
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
