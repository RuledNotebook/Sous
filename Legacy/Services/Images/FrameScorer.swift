import CoreGraphics
import Foundation
import Vision

/// How good a video frame is as a still picture.
/// `sharpness` is only meaningful relative to other frames of the same video; the rest are 0…1.
nonisolated struct FrameScore: Sendable, Equatable {
    /// Variance of the Laplacian of the downscaled luma. Crisp edges score high, motion blur low.
    var sharpness: Double
    /// Mean luma: 0 = black, 1 = white.
    var brightness: Double
    /// Standard deviation of luma.
    var contrast: Double
    /// Fraction of pixels crushed to black or blown to white.
    var clipped: Double
    /// Fraction of the picture covered by detected faces, once measured (it's the expensive part).
    var faceCoverage: Double?

    /// 1 for mid-tone frames, tapering towards very dark or very bright ones.
    var exposure: Double {
        let d = (brightness - 0.5) / 0.22
        return exp(-d * d)
    }

    /// Single number to rank candidates by: crisp first, but a well-lit frame beats a crisp dark one,
    /// and a blown-out frame loses most of its credit.
    var quality: Double {
        sharpness * (0.3 + 0.7 * exposure) * (1 - min(clipped, 0.5) * 1.5)
    }
}

/// Cheap image statistics on a small grayscale copy of a frame, plus a Vision face check.
nonisolated enum FrameScorer {
    /// Sharpness and exposure from a ~256 px wide grayscale copy (a few tens of thousands of pixels).
    static func score(_ image: CGImage, analysisWidth: Int = 256) -> FrameScore {
        guard let gray = luma(of: image, width: analysisWidth), gray.width > 2, gray.height > 2 else {
            return FrameScore(sharpness: 0, brightness: 0, contrast: 0, clipped: 1)
        }
        let w = gray.width, h = gray.height, p = gray.pixels
        let n = Double(p.count)

        var sum = 0.0, sumSq = 0.0, clipped = 0
        for v in p {
            let x = Double(v) / 255
            sum += x
            sumSq += x * x
            if v < 8 || v > 247 { clipped += 1 }
        }
        let mean = sum / n
        let variance = max(0, sumSq / n - mean * mean)

        // Variance of the 4-neighbour Laplacian over the interior: the classic focus measure.
        var lSum = 0.0, lSumSq = 0.0, count = 0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let l = 4 * Int(p[i]) - Int(p[i - 1]) - Int(p[i + 1]) - Int(p[i - w]) - Int(p[i + w])
                let d = Double(l) / 255
                lSum += d
                lSumSq += d * d
                count += 1
            }
        }
        let lMean = lSum / Double(count)
        let lVar = max(0, lSumSq / Double(count) - lMean * lMean)

        return FrameScore(sharpness: lVar, brightness: mean, contrast: variance.squareRoot(),
                          clipped: Double(clipped) / n)
    }

    /// Fraction of the picture area covered by faces. 0 when Vision finds none or can't run.
    static func faceCoverage(of image: CGImage) -> Double {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return 0 }
        let faces = request.results ?? []
        let area = faces.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        return min(1, max(0, area))
    }

    nonisolated struct Luma: Sendable {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    /// Draws the image into a small 8-bit grayscale bitmap.
    static func luma(of image: CGImage, width: Int) -> Luma? {
        guard image.width > 0, image.height > 0 else { return nil }
        let w = max(2, min(width, image.width))
        let h = max(2, Int((Double(image.height) * Double(w) / Double(image.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? Luma(pixels: pixels, width: w, height: h) : nil
    }
}
