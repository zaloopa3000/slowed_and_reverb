import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Shared fixtures for the unit tests: small generated audio files and GIFs.
enum TestFixtures {
    /// Writes a sine-wave `.caf` file to a unique temp location and returns its URL.
    nonisolated static func makeAudioFile(
        name: String = "Test Tone",
        duration: TimeInterval = 1,
        sampleRate: Double = 44_100,
        channels: AVAudioChannelCount = 2
    ) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "TestAudio-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).caf")

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let channelData = try #require(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frameCount) {
                channelData[channel][frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
            }
        }

        // Scoped so the file is closed (flushed) before the caller reads it.
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
        }
        return url
    }

    /// Encodes a GIF with one solid 8×8 frame per entry in `delays`.
    nonisolated static func makeGIFData(delays: [Double]) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, delays.count, nil)
        )
        for (index, delay) in delays.enumerated() {
            let image = try makeImage(gray: CGFloat(index) / CGFloat(max(delays.count, 1)))
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private nonisolated static func makeImage(gray: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
}
