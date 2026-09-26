import CoreGraphics
import Foundation

/// Gives every step picture the same framing, whether it came out of the video or an image model:
/// centre-cropped to the step card's aspect ratio and downscaled to a size the card can't tell apart.
nonisolated enum ImageFinisher {
    nonisolated struct Options: Sendable {
        /// The step card in `AIPanelView` is 16:10.
        var aspectRatio: CGFloat = 16.0 / 10.0
        var maxWidth = 1024

        static let card = Options()
    }

    static func finish(_ image: CGImage, options: Options = .card) -> CGImage {
        let cropped = centerCrop(image, aspectRatio: options.aspectRatio) ?? image
        return resized(cropped, maxWidth: options.maxWidth) ?? cropped
    }

    static func centerCrop(_ image: CGImage, aspectRatio: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0, aspectRatio > 0 else { return nil }
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        if w / h > aspectRatio {            // too wide: trim the sides
            rect.size.width = (h * aspectRatio).rounded(.down)
            rect.origin.x = ((w - rect.width) / 2).rounded(.down)
        } else {                             // too tall: trim top and bottom
            rect.size.height = (w / aspectRatio).rounded(.down)
            rect.origin.y = ((h - rect.height) / 2).rounded(.down)
        }
        if rect.width == w, rect.height == h { return image }
        return image.cropping(to: rect)
    }

    static func resized(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth, maxWidth > 0 else { return image }
        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let w = maxWidth
        let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
