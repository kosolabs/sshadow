import Testing

@testable import CoreKit

struct PollScheduleTests {
    let now = ContinuousClock.now

    private func schedule() -> PollSchedule {
        return PollSchedule(
            begin: now,
            allInterval: .seconds(30),
            allIdleThreshold: .seconds(600),
            watchedInterval: .seconds(10),
            watchedIdleThreshold: .seconds(120)
        )
    }

    @Test func firstPollIsDelayedByOneInterval() {
        let schedule = schedule()
        #expect(schedule.next(now: now, userIdle: .zero) == .wait)
    }

    @Test func pollAllBecomesDueAfterInterval() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(30)),
                userIdle: .zero
            ) == .pollAll
        )
    }

    @Test func pollAllSurvivesBriefIdle() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(30)),
                userIdle: .seconds(120)
            ) == .pollAll
        )
    }

    @Test func pollAllIsSuppressedWhenIdlePastThreshold() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(30)),
                userIdle: .seconds(600)
            ) == .wait
        )
    }

    @Test func pollAllFiresImmediatelyOnReturn() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(600)),
                userIdle: .seconds(600)
            ) == .wait
        )
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(601)),
                userIdle: .zero
            ) == .pollAll
        )
    }

    @Test func pollWatchedIsDueAfterInterval() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(10)),
                userIdle: .zero
            ) == .pollWatched
        )
    }

    @Test func pollWatchedIsNotDueBeforeInterval() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(9)),
                userIdle: .zero
            ) == .wait
        )
    }

    @Test func pollWatchedIsSuppressedWhileIdle() {
        let schedule = schedule()
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(10)),
                userIdle: .seconds(120)
            ) == .wait
        )
    }

    @Test func pollWatchedPollsAtFixedInterval() {
        let schedule = schedule()
        schedule.recordPollWatched(at: now.advanced(by: .seconds(10)))
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(15)),
                userIdle: .zero
            ) == .wait
        )
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(20)),
                userIdle: .zero
            ) == .pollWatched
        )
    }

    @Test func recordWatchStartedMakesPollWatchedDueImmediately() {
        let schedule = schedule()
        schedule.recordWatchStarted()
        #expect(schedule.next(now: now, userIdle: .zero) == .pollWatched)
    }

    @Test func pollAllRefreshesWatchedCadence() {
        let schedule = schedule()
        schedule.recordPollAll(at: now)

        #expect(schedule.next(now: now, userIdle: .zero) == .wait)
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(10)),
                userIdle: .zero
            ) == .pollWatched
        )
    }
}
