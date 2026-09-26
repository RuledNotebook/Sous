import Testing
@testable import CookAlong

struct TimestampClamperTests {
    @Test func clampsIntoTheVideoAndKeepsStrictlyIncreasing() {
        let out = TimestampClamper.clamp([-5, 10, 10, 8, 500], videoDuration: 200)
        #expect(out == [0, 10, 11, 12, 199])
    }

    @Test func doesNotPushStepsPastTheEndOfTheVideo() {
        // Three steps all reported at the last second: they must fit before the end, in order.
        let out = TimestampClamper.clamp([199, 199, 199], videoDuration: 200)
        #expect(out == [197, 198, 199])
        #expect(zip(out, out.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func shrinksTheGapWhenThereAreMoreStepsThanSeconds() {
        let out = TimestampClamper.clamp(Array(repeating: 0, count: 6), videoDuration: 3)
        #expect(out.first == 0)
        #expect(out.last! <= 2)
        #expect(zip(out, out.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func unknownDurationOnlyFloorsAtZeroAndOrders() {
        let out = TimestampClamper.clamp([-1, 30, 20, 3_600], videoDuration: 0)
        #expect(out == [0, 30, 31, 3_600])
    }

    @Test func leavesGoodTimestampsAlone() {
        let starts: [Double] = [0, 15, 40, 75, 110, 150, 190]
        #expect(TimestampClamper.clamp(starts, videoDuration: 205) == starts)
    }

    @Test func handlesEmptyAndSingle() {
        #expect(TimestampClamper.clamp([], videoDuration: 10).isEmpty)
        #expect(TimestampClamper.clamp([42], videoDuration: 10) == [9])
        #expect(TimestampClamper.clamp([.nan], videoDuration: 10) == [0])
    }
}
