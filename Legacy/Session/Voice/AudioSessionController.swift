import AVFoundation
import os

/// One place that decides how the app's audio session is configured.
/// Playback-only while you just watch; play-and-record while the mic is on.
enum AudioSessionController {
    private static let log = Logger(subsystem: "com.cookalong.CookAlong", category: "audio")

    /// Video plays through the speaker even with the ring switch on silent.
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            log.error("playback session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mic on, video still through the speaker (or AirPods), not the earpiece.
    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true)
    }
}
