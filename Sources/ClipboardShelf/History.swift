import AppKit
import ImageIO

/// Pasteboard data for one clip: one dictionary per pasteboard item, type name to bytes.
typealias Reps = [[String: Data]]

/// The clipboard history, newest first, kept in ~/Library/Application Support/ClipboardShelf:
/// history.json lists the clips, blobs/<id>.plist holds each one's pasteboard data and
/// blobs/<id>.png an image's thumbnail.
final class History: ObservableObject {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClipboardShelf")
    private static let listURL = dir.appendingPathComponent("history.json")
    private static let blobs = dir.appendingPathComponent("blobs")

    static let sizes = [50, 100, 200, 500, 1000]
    /// How many unpinned clips to keep (Settings › History). Pinned ones are never dropped.
    static var maxItems: Int {
        let n = UserDefaults.standard.integer(forKey: "maxItems")
        return n > 0 ? n : 200
    }

    @Published private(set) var clips: [Clip] = []
    private let io = DispatchQueue(label: "ClipboardShelf.history")
    private let thumbs = NSCache<NSUUID, NSImage>()

    init() {
        try? FileManager.default.createDirectory(at: Self.blobs, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: Self.listURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([Clip].self, from: data) {
            clips = list
        } else {
            // Keep the unreadable file for a look later rather than overwriting it.
            try? FileManager.default.moveItem(at: Self.listURL, to: Self.dir.appendingPathComponent("history-unreadable.json"))
        }
    }

    /// Adds a new copy at the top. The same content copied again moves up instead, keeping its pin.
    func add(_ clip: Clip, reps: Reps) {
        var clip = clip
        if let i = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            let old = clips.remove(at: i)
            removeFiles(old.id)
            thumbs.removeObject(forKey: old.id as NSUUID)
            clip.pinned = old.pinned
            clip.copyCount = old.copyCount + 1
        }
        clips.insert(clip, at: 0)
        let id = clip.id
        let isImage = clip.kind == .image
        io.async {
            if let data = try? PropertyListEncoder().encode(reps) {
                try? data.write(to: Self.blobURL(id), options: .atomic)
            }
            if isImage, let png = reps.first.flatMap(Self.imageData), let thumb = Self.thumbnail(png) {
                try? thumb.write(to: Self.thumbURL(id), options: .atomic)
                DispatchQueue.main.async { self.objectWillChange.send() }
            }
        }
        prune()
    }

    /// Moves a clip to the top after it was pasted.
    func touch(_ id: UUID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: i)
        clip.copiedAt = Date()
        clips.insert(clip, at: 0)
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].pinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        removeFiles(id)
        save()
    }

    /// Removes everything except the pinned clips.
    func clearUnpinned() {
        for c in clips where !c.pinned { removeFiles(c.id) }
        clips.removeAll { !$0.pinned }
        save()
    }

    /// Drops the oldest unpinned clips over the limit, then saves.
    func prune() {
        var kept = 0
        var dropped: [UUID] = []
        clips.removeAll { c in
            guard !c.pinned else { return false }
            kept += 1
            if kept > Self.maxItems { dropped.append(c.id); return true }
            return false
        }
        dropped.forEach(removeFiles)
        save()
    }

    func reps(for id: UUID) -> Reps? {
        io.sync {
            guard let data = try? Data(contentsOf: Self.blobURL(id)) else { return nil }
            return try? PropertyListDecoder().decode(Reps.self, from: data)
        }
    }

    func thumbnail(_ id: UUID) -> NSImage? {
        if let img = thumbs.object(forKey: id as NSUUID) { return img }
        guard let img = NSImage(contentsOf: Self.thumbURL(id)) else { return nil }
        thumbs.setObject(img, forKey: id as NSUUID)
        return img
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(clips) else { return }
        io.async { try? data.write(to: Self.listURL, options: .atomic) }
    }

    private func removeFiles(_ id: UUID) {
        io.async {
            try? FileManager.default.removeItem(at: Self.blobURL(id))
            try? FileManager.default.removeItem(at: Self.thumbURL(id))
        }
    }

    private static func blobURL(_ id: UUID) -> URL { blobs.appendingPathComponent("\(id.uuidString).plist") }
    private static func thumbURL(_ id: UUID) -> URL { blobs.appendingPathComponent("\(id.uuidString).png") }

    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]

    static func imageData(_ item: [String: Data]) -> Data? {
        imageTypes.lazy.compactMap { item[$0] }.first
    }

    /// A PNG at most 640 px on its longest side.
    static func thumbnail(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 640,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
