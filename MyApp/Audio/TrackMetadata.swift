import AVFoundation

/// Title / artist info read from an audio file's embedded metadata.
struct TrackMetadata: Equatable {
    var title: String
    var artist: String

    static let empty = TrackMetadata(title: "No Tape", artist: "Insert a track")

    /// Loads common metadata, falling back to the file name when tags are missing.
    static func load(from url: URL) async -> TrackMetadata {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let fallback = TrackMetadata(title: fallbackTitle, artist: "Unknown Artist")

        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return fallback }

        let title = await stringValue(for: .commonIdentifierTitle, in: items)
        let artist = await stringValue(for: .commonIdentifierArtist, in: items)

        return TrackMetadata(
            title: title ?? fallback.title,
            artist: artist ?? fallback.artist
        )
    }

    private static func stringValue(
        for identifier: AVMetadataIdentifier,
        in items: [AVMetadataItem]
    ) async -> String? {
        let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
        guard let item = matches.first,
              let value = try? await item.load(.stringValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}
