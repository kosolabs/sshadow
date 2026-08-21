import Foundation

class PollSchedule {
    enum Operation: Equatable {
        case pollAll
        case pollWatched
        case wait
    }

    private let allInterval: Duration
    private let allIdleThreshold: Duration
    private var lastPollAll: ContinuousClock.Instant

    private let watchedInterval: Duration
    private let watchedIdleThreshold: Duration
    private var lastPollWatched: ContinuousClock.Instant?

    init(
        begin now: ContinuousClock.Instant,
        allInterval: Duration,
        allIdleThreshold: Duration = .seconds(600),
        watchedInterval: Duration = .seconds(10),
        watchedIdleThreshold: Duration = .seconds(120)
    ) {
        self.allInterval = allInterval
        self.allIdleThreshold = allIdleThreshold
        self.watchedInterval = watchedInterval
        self.watchedIdleThreshold = watchedIdleThreshold

        lastPollAll = now
        lastPollWatched = now
    }

    func next(
        now: ContinuousClock.Instant,
        userIdle: Duration
    ) -> Operation {
        if isDue(
            now,
            since: lastPollAll,
            interval: allInterval,
            userIdle: userIdle,
            idleThreshold: allIdleThreshold
        ) {
            return .pollAll
        }
        if isDue(
            now,
            since: lastPollWatched,
            interval: watchedInterval,
            userIdle: userIdle,
            idleThreshold: watchedIdleThreshold
        ) {
            return .pollWatched
        }
        return .wait
    }

    func recordPollAll(at now: ContinuousClock.Instant) {
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
