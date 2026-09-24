import CoreGraphics
import Foundation
import Testing
@testable import AsterCore

@Suite("Placement geometry")
struct PlacementTests {
    let landscape = CGSize(width: 6000, height: 4000)
    let portrait = CGSize(width: 4000, height: 6000)

    @Test func bottomTrailingRespectsMargins() {
        let p = Placement(anchor: .bottomTrailing, marginX: 0.05, marginY: 0.05, width: 0.25)
        let r = p.rect(in: landscape, watermarkAspect: 2)
        // Short edge 4000 → width 1000, height 500, margins 200.
        #expect(r == CGRect(x: 6000 - 200 - 1000, y: 4000 - 200 - 500, width: 1000, height: 500))
    }

    @Test func sameVisualSizeOnPortraitAndLandscape() {
        let p = Placement(anchor: .topLeading, width: 0.3)
        #expect(p.rect(in: landscape, watermarkAspect: 3).size == p.rect(in: portrait, watermarkAspect: 3).size)
    }

    @Test func centreAnchorIsCentred() {
        let p = Placement(anchor: .center, marginX: 0, marginY: 0, width: 0.5)
        let r = p.rect(in: landscape, watermarkAspect: 1)
        #expect(r.midX == landscape.width / 2)
        #expect(r.midY == landscape.height / 2)
    }

    @Test(arguments: Anchor.allCases)
    func roundTripThroughPixelRect(anchor: Anchor) {
        let original = Placement(anchor: anchor, marginX: 0.07, marginY: -0.03, width: 0.18,
                                 rotation: 0.2, opacity: 0.6)
        let rect = original.rect(in: portrait, watermarkAspect: 1.6)
        let back = Placement.from(rect: rect, in: portrait, anchor: anchor,
                                  rotation: original.rotation, opacity: original.opacity)
        #expect(abs(back.marginX - original.marginX) < 1e-9)
        #expect(abs(back.marginY - original.marginY) < 1e-9)
        #expect(abs(back.width - original.width) < 1e-9)
        #expect(back.anchor == anchor)
    }

    @Test func keypadDigitsMapToAnchors() {
        #expect(Anchor(keypadDigit: 7) == .topLeading)
        #expect(Anchor(keypadDigit: 5) == .center)
        #expect(Anchor(keypadDigit: 3) == .bottomTrailing)
        #expect(Anchor(keypadDigit: 0) == nil)
    }
}

@Suite("NormalizedRect")
struct NormalizedRectTests {
    @Test func centredPortraitCropInLandscape() {
        // 3:4 crop out of a 3:2 photo → full height, width = (3/4)/(3/2) = 0.5.
        let r = NormalizedRect.centered(aspect: 3.0 / 4.0, in: 3.0 / 2.0)
        #expect(r == NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    @Test func centredLandscapeCropInPortrait() {
        let r = NormalizedRect.centered(aspect: 1.91, in: 2.0 / 3.0)
        #expect(abs(r.height - (2.0 / 3.0) / 1.91) < 1e-12)
        #expect(r.width == 1)
        #expect(abs(r.y - (1 - r.height) / 2) < 1e-12)
    }

    @Test func clampKeepsRectInside() {
        let r = NormalizedRect(x: 0.8, y: -0.1, width: 0.5, height: 0.5).clampedToUnit()
        #expect(r == NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    @Test func denormalize() {
        let r = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
            .denormalized(in: CGSize(width: 400, height: 200))
        #expect(r == CGRect(x: 100, y: 100, width: 200, height: 50))
    }
}

@Suite("Size presets")
struct SizePresetTests {
    @Test func builtInIDsAreUnique() {
        let ids = SizePreset.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func pixelSizesMatchAspect() {
        for preset in SizePreset.builtIn {
            guard let aspect = preset.aspect, let w = preset.pixelWidth, let h = preset.pixelHeight else { continue }
            #expect(abs(Double(w) / Double(h) - aspect) < 0.01, "\(preset.id)")
        }
    }

    @Test func userPresetsOverrideAndExtend() {
        let user = [
            SizePreset(id: "ig-4x5", platform: .instagram, name: "Custom 4:5",
                       aspectWidth: 4, aspectHeight: 5, pixelWidth: 1440, pixelHeight: 1800),
            SizePreset(id: "client-web", platform: .generic, name: "Client web", longEdge: 3000),
        ]
        let merged = SizePreset.merged(user: user)
        #expect(merged.count == SizePreset.builtIn.count + 1)
        #expect(merged.first { $0.id == "ig-4x5" }?.pixelWidth == 1440)
        #expect(merged.last?.id == "client-web")
    }

    @Test func presetsRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(SizePreset.builtIn)
        let decoded = try JSONDecoder().decode([SizePreset].self, from: data)
        #expect(decoded == SizePreset.builtIn)
    }
}
