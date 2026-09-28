import SwiftUI

/// Optional overlay effect for the GIF, cycled with the effect button (Metal shaders in GifShaders.metal).
enum GifEffect: String, CaseIterable {
    case none, pixel, crt, vhs, neon

    var title: String {
        switch self {
        case .none: "No effect"
        case .pixel: "Pixel"
        case .crt: "CRT"
        case .vhs: "VHS"
        case .neon: "Neon"
        }
    }

    var next: GifEffect {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

extension View {
    /// Applies `effect` to the view's rendered pixels on the GPU. `time` drives animated effects (VHS).
    func gifEffect(_ effect: GifEffect, time: Double, pixelSize: CGFloat) -> some View {
        visualEffect { content, proxy in
            let size = proxy.size
            return content
                .layerEffect(
                    ShaderLibrary.gifPixelate(.float(pixelSize)),
                    maxSampleOffset: CGSize(width: pixelSize, height: pixelSize),
                    isEnabled: effect == .pixel
                )
                .colorEffect(
                    ShaderLibrary.gifCRT(.float2(size)),
                    isEnabled: effect == .crt
                )
                .layerEffect(
                    ShaderLibrary.gifVHS(.float(time), .float2(size)),
                    maxSampleOffset: CGSize(width: 6, height: 0),
                    isEnabled: effect == .vhs
                )
                .colorEffect(
                    ShaderLibrary.gifNeon(),
                    isEnabled: effect == .neon
                )
        }
    }
}
