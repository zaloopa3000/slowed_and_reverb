import Foundation

/// Fetches random anime GIFs from the GIPHY API.
///
/// Uses search (not the `random` endpoint, whose tag matching is loose) so results stay
/// strictly anime: a random anime query, a random page of results, a random GIF from it.
nonisolated enum GiphyService {
    enum Failure: Error {
        case badResponse
        case noGIF
        case undecodable
        case missingAPIKey
    }

    /// Read from `MyApp/Secrets.plist` (git-ignored; template in `Secrets.example.plist`),
    /// so the key never lands in the repository.
    private static let apiKey: String? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["GiphyAPIKey"] as? String,
              !key.isEmpty
        else { return nil }
        return key
    }()
    private static let endpoint = URL(string: "https://api.giphy.com/v1/gifs/search")!

    /// All anime; varied so consecutive GIFs don't feel repetitive.
    private static let queries = [
        "anime", "anime aesthetic", "lofi anime", "90s anime", "anime night",
        "anime rain", "anime city", "studio ghibli", "anime scenery", "anime music"
    ]
    private static let pageSize = 25
    /// Random page offset range; small enough that every page is well stocked.
    private static let maxOffset = 100

    /// Downloads and decodes a random anime GIF, off the main actor.
    @concurrent
    static func randomGIF(maxPixelSize: Int = 400) async throws -> AnimatedGIF {
        // No key → the screen shows "No signal" instead of failing requests.
        guard let apiKey else { throw Failure.missingAPIKey }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "q", value: queries.randomElement()),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(Int.random(in: 0...maxOffset))),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "lang", value: "en")
        ]
        guard let requestURL = components?.url else { throw Failure.badResponse }

        let (json, response) = try await URLSession.shared.data(from: requestURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }

        guard let result = try? JSONDecoder().decode(SearchResponse.self, from: json),
              let pick = result.data.shuffled().first(where: { $0.images.bestURL != nil }),
              let gifURL = pick.images.bestURL
        else { throw Failure.noGIF }

        let (gifData, _) = try await URLSession.shared.data(from: gifURL)
        guard let gif = AnimatedGIF(data: gifData, maxPixelSize: maxPixelSize) else { throw Failure.undecodable }
        return gif
    }

    // MARK: Response model (only the fields we use)

    private struct SearchResponse: Decodable {
        let data: [GIFObject]
    }

    private struct GIFObject: Decodable {
        let images: Images
    }

    private struct Images: Decodable {
        let downsized: Rendition?
        let fixedHeight: Rendition?

        /// "downsized" (≤ 2 MB, full width) looks clean full-screen; "fixed_height" is the fallback.
        var bestURL: URL? { downsized?.url ?? fixedHeight?.url }

        enum CodingKeys: String, CodingKey {
            case downsized
            case fixedHeight = "fixed_height"
        }
    }

    private struct Rendition: Decodable {
        let url: URL
    }
}
