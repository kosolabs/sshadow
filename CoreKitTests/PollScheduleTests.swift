import Testing

@testable import CoreKit

struct PollScheduleTests {
    let now = ContinuousClock.now

    private func schedule() -> PollSchedule {
        return PollSchedule(
            begin: now,
            settings: PollSettings(
                interval: .seconds(30),
                idleThreshold: .seconds(600),
                watchedInterval: .seconds(10),
                watchedIdleThreshold: .seconds(120)
            )
        )
    }

    @Test func firstPollIsDelayedByOneInterval() {
        let schedule = schedule()
        #expect(schedule.next(now: now, userIdle: .zero) == .wait)
    }

    @Test func requestedPollAllWaitsForTheQuietPeriod() {
        let schedule = schedule()
        schedule.requestPollAll(at: now)

        #expect(schedule.next(now: now, userIdle: .zero) == .wait)
        #expect(
            schedule.next(
                now: now + PollSchedule.requestQuietPeriod,
                userIdle: .seconds(3600)
            ) == .pollAll
        )
    }

    @Test func anotherRequestRestartsTheQuietPeriod() {
        let schedule = schedule()
        schedule.requestPollAll(at: now)
        let later = now + .milliseconds(800)
        schedule.requestPollAll(at: later)

        #expect(
            schedule.next(
                now: now + PollSchedule.requestQuietPeriod,
                userIdle: .zero
            ) == .wait
        )
        #expect(
            schedule.next(
                now: later + PollSchedule.requestQuietPeriod,
                userIdle: .zero
            ) == .pollAll
        )
    }

    @Test func recordedPollAllClearsTheRequest() {
        let schedule = schedule()
        schedule.requestPollAll(at: now)
        let polled = now + PollSchedule.requestQuietPeriod
        schedule.recordPollAll(at: polled)

        #expect(schedule.next(now: polled, userIdle: .zero) == .wait)
    }

    @Test func manualScheduleOnlyPollsOnRequest() {
        let schedule = PollSchedule(begin: now, settings: nil)
        let muchLater = now + .seconds(86_400)

        #expect(schedule.next(now: muchLater, userIdle: .zero) == .wait)

        schedule.requestPollAll(at: muchLater)
        #expect(
            schedule.next(
                now: muchLater + PollSchedule.requestQuietPeriod,
                userIdle: .zero
            ) == .pollAll
        )
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

    @Test func updatedSettingsApplyToTheNextDecision() {
        let schedule = schedule()
        schedule.update(
            settings: PollSettings(
                interval: .seconds(10),
                idleThreshold: .seconds(600),
                watchedInterval: .seconds(10),
                watchedIdleThreshold: .seconds(120)
            )
        )
        #expect(
            schedule.next(
                now: now.advanced(by: .seconds(10)),
                userIdle: .zero
            ) == .pollAll
        )
    }
}
