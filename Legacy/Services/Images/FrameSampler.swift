import AVFoundation
import CoreGraphics

/// One decoded candidate frame and how it scored.
nonisolated struct SampledFrame: Sendable {
    let image: CGImage
    let seconds: Double
    var score: FrameScore
}

/// Pulls a handful of frames out of a time window and keeps the one that will look best as a still.
nonisolated enum FrameSampler {
    nonisolated struct Options: Sendable {
        var sampleCount = 5
        /// Decode size cap. 1280 so a 720p video still yields a full 1024x640 card picture after cropping.
        var maximumSize = CGSize(width: 1280, height: 1280)
        /// Frames whose detected faces cover more than this share of the picture are skipped.
        var maximumFaceCoverage = 0.05
        /// Seek slack, in seconds. A little slack decodes faster; duplicates are dropped anyway.
        var toleranceSeconds = 0.25
        /// Crop/resize applied to the winner, so it's ready to show. nil keeps the raw frame.
        var finish: ImageFinisher.Options? = .card
    }

    /// Decodes `sampleCount` frames evenly spread over `start…end`, scores them and returns the best one
    /// that isn't mostly a face. nil if the video can't be read. Runs off the main actor.
    @concurrent
    static func bestFrame(in url: URL, from start: Double, to end: Double, options: Options = Options(),
                          faceCoverage: @Sendable (CGImage) -> Double = { FrameScorer.faceCoverage(of: $0) }) async -> SampledFrame? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return nil }
        let times = sampleTimes(from: start, to: end, duration: duration, count: options.sampleCount)
        guard !times.isEmpty else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = options.maximumSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: options.toleranceSeconds, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: options.toleranceSeconds, preferredTimescale: 600)

        var candidates: [SampledFrame] = []
        var seen = Set<Int>()
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            if Task.isCancelled { return nil }
            guard let image = try? result.image else { continue }
            let seconds = (try? result.actualTime.seconds) ?? result.requestedTime.seconds
            // With seek slack two requests can land on the same frame; score each frame once.
            guard seen.insert(Int((seconds * 20).rounded())).inserted else { continue }
            candidates.append(SampledFrame(image: image, seconds: seconds, score: FrameScorer.score(image)))
        }

        guard var best = select(candidates, maximumFaceCoverage: options.maximumFaceCoverage, faceCoverage: faceCoverage)
        else { return nil }
        if let finish = options.finish { best = SampledFrame(image: ImageFinisher.finish(best.image, options: finish),
                                                             seconds: best.seconds, score: best.score) }
        return best
    }

    /// `count` evenly spaced times inside the video, or a single one if the window is tiny.
    static func sampleTimes(from start: Double, to end: Double, duration: Double, count: Int) -> [Double] {
        let last = max(0, duration - 0.1)
        let s = min(max(0, start), last)
        let e = min(max(s, end), last)
        guard count > 1, e - s >= 0.2 else { return [s] }
        let step = (e - s) / Double(count - 1)
        return (0..<count).map { s + Double($0) * step }
    }

    /// Ranks by `quality`, then walks down the ranking until a frame passes the face check, so the
    /// face detector usually runs once. If every frame is a face, the one with the least face wins.
    static func select(_ candidates: [SampledFrame], maximumFaceCoverage: Double,
                       faceCoverage: (CGImage) -> Double) -> SampledFrame? {
        var ranked = candidates.sorted { $0.score.quality > $1.score.quality }
        for i in ranked.indices {
            let coverage = faceCoverage(ranked[i].image)
            ranked[i].score.faceCoverage = coverage
            if coverage <= maximumFaceCoverage { return ranked[i] }
        }
        return ranked.min { ($0.score.faceCoverage ?? 0) < ($1.score.faceCoverage ?? 0) }
    }
}
