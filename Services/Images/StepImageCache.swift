import CryptoKit
import UIKit

/// Identity of one step picture: recipe title + step index, guarded by a fingerprint of what the picture
/// depends on (image prompt, time in the video, which video), so an edited step or a different video
/// under the same title never shows a stale picture.
nonisolated struct StepImageKey: Hashable, Sendable {
    var recipeTitle: String
    var stepIndex: Int?
    var fingerprint: String

    init(request: StepImageRequest) {
        recipeTitle = request.recipeTitle
        stepIndex = request.stepIndex
        let material = [request.step.imagePrompt, String(request.step.startSecond),
                        Self.videoIdentity(request.videoURL)].joined(separator: "|")
        fingerprint = SHA256.hash(data: Data(material.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Files sharing this prefix are the same slot (same recipe, same step) and replace each other.
    var slotPrefix: String { "\(Self.slug(recipeTitle))-s\(stepIndex.map(String.init) ?? "x")-" }
    /// e.g. "garlic-butter-shrimp-pasta-s3-9f1c0a2b7e1d"
    var stem: String { slotPrefix + fingerprint }

    /// Lowercase ASCII letters and digits joined by single dashes, at most 40 characters.
    static func slug(_ text: String) -> String {
        var out = ""
        var pendingDash = false
        for scalar in text.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !out.isEmpty { out += "-" }
                out.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
            if out.count >= 40 { break }
        }
        return out.isEmpty ? "recipe" : out
    }

    /// The file's size stands in for its identity: a picked video gets a fresh temp name on every pick.
    static func videoIdentity(_ url: URL?) -> String {
        guard let url else { return "no-video" }
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
            return "bytes:\(size.int64Value)"
        }
        return url.absoluteString
    }
}

/// Memory + disk cache for step pictures. Disk lives in Caches/StepImages, so the system may purge it.
/// `tier` records which provider tier made the picture (0 = video frame, 1 = AI image, …) so
/// `StepImageLoader` knows whether a cached picture can still be upgraded.
actor StepImageCache {
    static let shared = StepImageCache()

    nonisolated final class Entry: Sendable {
        let image: UIImage
        let tier: Int
        init(image: UIImage, tier: Int) {
            self.image = image
            self.tier = tier
        }
    }

    static let maxTier = 4
    private let memory = NSCache<NSString, Entry>()
    private let directory: URL?
    private var pruned = false
    /// Above `maxFiles` on disk, the oldest are removed until `keepFiles` remain (checked once per launch).
    var maxFiles = 400
    var keepFiles = 250

    init(directoryName: String = "StepImages", memoryLimit: Int = 40) {
        memory.countLimit = memoryLimit
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = base?.appending(path: directoryName)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func entry(for key: StepImageKey) -> Entry? {
        if let hit = memory.object(forKey: key.stem as NSString) { return hit }
        guard let directory else { return nil }
        for tier in stride(from: Self.maxTier, through: 0, by: -1) {
            let url = Self.fileURL(for: key, tier: tier, in: directory)
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { continue }
            let entry = Entry(image: image, tier: tier)
            memory.setObject(entry, forKey: key.stem as NSString)
            return entry
        }
        return nil
    }

    func store(_ image: UIImage, tier: Int, for key: StepImageKey) {
        let tier = min(max(tier, 0), Self.maxTier)
        memory.setObject(Entry(image: image, tier: tier), forKey: key.stem as NSString)
        guard let directory, let data = image.jpegData(compressionQuality: 0.85) else { return }
        pruneIfNeeded(in: directory)
        removeFiles(withPrefix: key.slotPrefix, in: directory)      // one file per slot
        try? data.write(to: Self.fileURL(for: key, tier: tier, in: directory), options: .atomic)
    }

    func removeAll() {
        memory.removeAllObjects()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated static func fileURL(for key: StepImageKey, tier: Int, in directory: URL) -> URL {
        directory.appending(path: "\(key.stem).t\(tier).jpg")
    }

    private func removeFiles(withPrefix prefix: String, in directory: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? fm.removeItem(at: directory.appending(path: name))
        }
    }

    private func pruneIfNeeded(in directory: URL) {
        guard !pruned else { return }
        pruned = true
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              urls.count > maxFiles else { return }
        let dated = urls
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 < $1.1 }
        for (url, _) in dated.prefix(max(0, urls.count - keepFiles)) {
            try? fm.removeItem(at: url)
        }
    }
}
