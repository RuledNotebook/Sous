import AVFoundation
import UIKit

/// Zero-setup default: sample a handful of frames from the start of the step and keep the sharpest,
/// best-lit one that isn't a talking head. Nothing here touches the network.
struct VideoFrameImageProvider: StepImageProvider {
    /// Skip the first moments of a step; that's usually the cut or a transition.
    var leadIn: Double = 0.5
    /// Look at this share of the step, bounded by `minimumWindow` and `maximumWindow`.
    var windowFraction: Double = 0.6
    var minimumWindow: Double = 3
    var maximumWindow: Double = 20
    /// How far to look when the step's end is unknown (no recipe context).
    var defaultWindow: Double = 12
    var sampling = FrameSampler.Options()

    func image(for step: RecipeStep, videoURL: URL?) async -> UIImage? {
        await image(for: StepImageRequest(step: step, videoURL: videoURL))
    }

    func image(for request: StepImageRequest) async -> UIImage? {
        guard let frame = await bestFrame(for: request) else { return nil }
        return UIImage(cgImage: frame.image)
    }

    /// The winning frame with its scores; `RemoteImageProvider` uses it as a reference picture.
    func bestFrame(for request: StepImageRequest) async -> SampledFrame? {
        guard let url = request.videoURL, !Task.isCancelled else { return nil }
        let (start, end) = window(for: request)
        return await FrameSampler.bestFrame(in: url, from: start, to: end, options: sampling)
    }

    /// The slice of the video to sample: the first part of the step, after the cut.
    func window(for request: StepImageRequest) -> (start: Double, end: Double) {
        let begin = request.step.videoStart
        let span: Double
        if let stepEnd = request.stepEnd, stepEnd > begin {
            span = min(max((stepEnd - begin) * windowFraction, minimumWindow), maximumWindow)
        } else {
            span = defaultWindow
        }
        return (begin + leadIn, begin + span)
    }
}
