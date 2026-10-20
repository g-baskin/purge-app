import AppKit
import SwiftUI
import Testing
@testable import Purge

@Suite("Free storage color")
@MainActor
struct StorageFreeColorTests {
    private func resolve(_ color: Color, appearance: NSAppearance.Name) throws -> NSColor {
        var resolved: NSColor?
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return try #require(resolved)
    }

    private func luminance(_ color: NSColor) -> Double {
        func linear(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    @Test func darkModeIsNeonGreen() throws {
        let color = try resolve(AppColors.storageFreeText, appearance: .darkAqua)
        #expect(abs(Double(color.redComponent) - 57.0 / 255) < 0.001)
        #expect(abs(Double(color.greenComponent) - 1) < 0.001)
        #expect(abs(Double(color.blueComponent) - 20.0 / 255) < 0.001)
    }

    @Test func bothThemesKeepReadableContrast() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let foreground = luminance(try resolve(AppColors.storageFreeText, appearance: appearance))
            for surface in [AppColors.surfaceBase, AppColors.surfaceCard] {
                let background = luminance(try resolve(surface, appearance: appearance))
                let ratio = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                #expect(ratio >= 4.5)
            }
        }
    }
}
