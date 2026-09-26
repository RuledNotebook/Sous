import CryptoKit
import UIKit

/// Identity of one step picture: the YouTube video ID (else a slug of the title) + step index, guarded by a
/// fingerprint of the image prompt so a re-analysed step never shows a stale picture.
nonisolated struct StepImageKey: Hashable, Sendable {
    var recipeKey: String
    var stepIndex: Int?
    var fingerprint: String

    init(recipe: Recipe, step: RecipeStep) {
        recipeKey = recipe.videoID ?? Self.slug(recipe.title)
        stepIndex = recipe.steps.firstIndex { $0.id == step.id }
        let material = step.imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        fingerprint = SHA256.hash(data: Data(material.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Files sharing this prefix are the same slot (same video, same step) and replace each other.
    var slotPrefix: String { "\(recipeKey)-s\(stepIndex.map(String.init) ?? "x")-" }
    /// e.g. "Y7r6Ah0LQfA-s3-9f1c0a2b7e1d"
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
}

/// Memory + disk cache for step pictures. Disk lives in Caches/StepImages, so the system may purge it.
actor StepImageCache {
    static let shared = StepImageCache()

    private let memory = NSCache<NSString, UIImage>()
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

    func image(for key: StepImageKey) -> UIImage? {
        if let hit = memory.object(forKey: key.stem as NSString) { return hit }
        guard let directory, let data = try? Data(contentsOf: Self.fileURL(for: key, in: directory)),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key.stem as NSString)
        return image
    }

    func store(_ image: UIImage, for key: StepImageKey) {
        memory.setObject(image, forKey: key.stem as NSString)
        guard let directory, let data = image.jpegData(compressionQuality: 0.85) else { return }
        pruneIfNeeded(in: directory)
        removeFiles(withPrefix: key.slotPrefix, in: directory)      // one file per slot
        try? data.write(to: Self.fileURL(for: key, in: directory), options: .atomic)
    }

    func removeAll() {
        memory.removeAllObjects()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated static func fileURL(for key: StepImageKey, in directory: URL) -> URL {
        directory.appending(path: "\(key.stem).jpg")
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
