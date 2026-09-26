import Foundation

/// One picture's worth of inputs, already prompted and prepared. An adapter turns this into bytes on the wire.
nonisolated struct ImageGenerationJob: Sendable {
    var prompt: String
    /// JPEG bytes of the best video frame, when the provider decided to send one.
    var referenceJPEG: Data?
    /// Per-recipe seed, when the provider is configured to send one. Adapters may ignore it.
    var seed: Int?
    var timeout: TimeInterval
}

/// What an endpoint answered with.
nonisolated enum ImageGenerationResult: Sendable {
    /// Encoded image bytes (PNG, JPEG, WebP…).
    case image(Data)
    /// Fetch this to get the bytes.
    case url(URL)
    /// No image in the response.
    case none
}

/// The wire format of one image endpoint: build the request, pull the picture out of the response.
/// Implement this to add a provider; `RemoteImageProvider` does everything else (the series prompt,
/// reference frames, timeouts, framing, logging, silent failure). See `OpenAIImagesAPI` and `GeminiImageAPI`.
nonisolated protocol ImageGenerationAPI: Sendable {
    /// Short name for logs.
    var name: String { get }
    /// True when the request can carry a reference picture; the provider only grabs a frame if it can.
    var acceptsReferenceImage: Bool { get }
    func makeRequest(_ job: ImageGenerationJob) -> URLRequest?
    func result(from body: Data) -> ImageGenerationResult
}
