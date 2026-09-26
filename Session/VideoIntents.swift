import Foundation

/// A relative move in the video asked from outside the player (voice, a button). The serial makes
/// every ask distinct, so two "skip ahead"s in a row both happen.
nonisolated struct VideoSkip: Equatable, Sendable {
    var serial: Int
    var seconds: Int
}

/// Play or pause asked from outside the video header.
nonisolated struct VideoPlaybackRequest: Equatable, Sendable {
    var serial: Int
    var play: Bool
}
