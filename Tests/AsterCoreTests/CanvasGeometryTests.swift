import CoreGraphics
import Foundation
import Testing
@testable import AsterCore

@Suite("Canvas geometry")
struct CanvasGeometryTests {
    let photo = CGSize(width: 6000, height: 4000)
    let bounds = CGSize(width: 1048, height: 748)

    @Test func fitCentresWithPadding() {
        let rect = CanvasGeometry.imageRect(content: photo, in: bounds, zoom: .fit)
        // Available 1000×700 → width-limited at 1000/6000.
        #expect(rect.width == 1000)
        #expect(abs(rect.height - 666.67) < 0.01)
        #expect(rect.minX == 24)
        #expect(rect.midY.rounded() == (bounds.height / 2).rounded())
    }

    @Test func explicitScaleAndPan() {
        let rect = CanvasGeometry.imageRect(content: photo, in: bounds, zoom: .scale(1), pan: CGPoint(x: 100, y: -50))
        #expect(rect.size == photo)
        #expect(rect.minX == ((bounds.width - 6000) / 2 + 100).rounded())
    }

    @Test func zoomToCursorKeepsPointFixed() {
        let old = CanvasGeometry.imageRect(content: photo, in: bounds, zoom: .fit)
        let cursor = CGPoint(x: old.minX + old.width * 0.8, y: old.minY + old.height * 0.3)
        let newSize = CGSize(width: 6000, height: 4000)
        let pan = CanvasGeometry.panKeeping(anchor: cursor, oldRect: old, newSize: newSize, bounds: bounds)
        let new = CanvasGeometry.imageRect(content: photo, in: bounds, zoom: .scale(1), pan: pan)
        #expect(abs((cursor.x - new.minX) / new.width - 0.8) < 0.001)
        #expect(abs((cursor.y - new.minY) / new.height - 0.3) < 0.001)
    }

    @Test func panIsClamped() {
        let pan = CanvasGeometry.clampPan(CGPoint(x: 99999, y: -99999), imageSize: photo, in: bounds)
        #expect(pan.x == (6000 - bounds.width) / 2 + CanvasGeometry.padding)
        #expect(pan.y == -((4000 - bounds.height) / 2 + CanvasGeometry.padding))
        #expect(CanvasGeometry.clampPan(CGPoint(x: 50, y: 50), imageSize: CGSize(width: 10, height: 10), in: bounds) == .zero)
    }
}

@Suite("Rotated rect")
struct RotatedRectTests {
    @Test func hitTestingFollowsRotation() {
        let r = RotatedRect(center: CGPoint(x: 100, y: 100), size: CGSize(width: 100, height: 20), rotation: .pi / 2)
        #expect(r.contains(CGPoint(x: 100, y: 140)))   // along the rotated long axis
        #expect(!r.contains(CGPoint(x: 140, y: 100)))  // where the unrotated rect would be
    }

    @Test func clockwisePositive() {
        // A 90° clockwise turn (y-down) moves the top-left corner to the top-right.
        let r = RotatedRect(center: .zero, size: CGSize(width: 20, height: 10), rotation: .pi / 2)
        let topLeft = r.corners[0]
        #expect(abs(topLeft.x - 5) < 1e-9 && abs(topLeft.y - -10) < 1e-9)
    }

    @Test func localWorldRoundTrip() {
        let r = RotatedRect(center: CGPoint(x: 30, y: -12), size: CGSize(width: 50, height: 10), rotation: 0.7)
        let p = CGPoint(x: 17, y: 44)
        let back = r.worldPoint(r.localPoint(p))
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    }

    @Test func boundingBoxOfRotatedSquare() {
        let r = RotatedRect(center: .zero, size: CGSize(width: 10, height: 10), rotation: .pi / 4)
        #expect(abs(r.boundingBox.width - 10 * 2.0.squareRoot()) < 1e-9)
    }
}

@Suite("Snapping & anchoring")
struct SnapTests {
    let frame = CGSize(width: 1000, height: 600)

    @Test func snapsToCentreLines() {
        let rect = CGRect(x: 447, y: 100, width: 100, height: 50) // midX 497 → 500
        let result = SnapEngine.snap(rect, in: frame, threshold: 6)
        #expect(result.rect.midX == 500)
        #expect(result.guides.contains(SnapGuide(axis: .vertical, position: 500)))
    }

    @Test func snapsToMarginGuide() {
        // Margin 4% of 600 = 24 → right guide at 976.
        let rect = CGRect(x: 873, y: 520, width: 100, height: 50)
        let result = SnapEngine.snap(rect, in: frame, threshold: 6)
        #expect(result.rect.maxX == 976)
        #expect(result.rect.maxY == 576)
    }

    @Test func noSnapBeyondThreshold() {
        let rect = CGRect(x: 300, y: 200, width: 100, height: 50)
        let result = SnapEngine.snap(rect, in: frame, threshold: 6)
        #expect(result.rect == rect)
        #expect(!result.didSnap)
    }

    @Test func snapsToOtherLayers() {
        let other = CGRect(x: 600, y: 300, width: 80, height: 40)
        let rect = CGRect(x: 603, y: 150, width: 100, height: 50)
        #expect(SnapEngine.snap(rect, in: frame, others: [other], threshold: 6).rect.minX == 600)
    }

    @Test func angleSnapping() {
        #expect(SnapEngine.snapAngle(0.03, stepped: false) == 0)
        #expect(SnapEngine.snapAngle(0.3, stepped: false) == 0.3)
        let stepped = SnapEngine.snapAngle(0.3, stepped: true)
        #expect(abs(stepped - .pi / 12) < 1e-12)
    }

    @Test func nearestAnchorByThirds() {
        #expect(Anchor.nearest(to: CGPoint(x: 950, y: 580), in: frame) == .bottomTrailing)
        #expect(Anchor.nearest(to: CGPoint(x: 500, y: 300), in: frame) == .center)
        #expect(Anchor.nearest(to: CGPoint(x: 10, y: 10), in: frame) == .topLeading)
        #expect(Anchor.nearest(to: CGPoint(x: 500, y: 590), in: frame) == .bottom)
    }

    @Test func reanchoredPlacementKeepsRect() {
        let rect = CGRect(x: 40, y: 30, width: 120, height: 60)
        let placement = Placement.reanchored(rect: rect, in: frame, rotation: 0.1, opacity: 0.6)
        #expect(placement.anchor == .topLeading)
        let back = placement.rect(in: frame, watermarkAspect: 2)
        #expect(abs(back.minX - 40) < 1e-9 && abs(back.minY - 30) < 1e-9)
        #expect(placement.rotation == 0.1 && placement.opacity == 0.6)
    }
}

@Suite("Resize & rotate handles")
struct HandleMathTests {
    @Test func bottomRightDragKeepsTopLeftFixed() {
        let start = RotatedRect(rect: CGRect(x: 100, y: 100, width: 200, height: 100), rotation: 0)
        let rect = start.resized(corner: 2, to: CGPoint(x: 500, y: 250), aspect: 2, fromCenter: false)
        #expect(rect.origin == CGPoint(x: 100, y: 100))
        #expect(rect.width == 400 && rect.height == 200)
    }

    @Test func topLeftDragKeepsBottomRightFixed() {
        let start = RotatedRect(rect: CGRect(x: 100, y: 100, width: 200, height: 100), rotation: 0)
        let rect = start.resized(corner: 0, to: CGPoint(x: 200, y: 150), aspect: 2, fromCenter: false)
        #expect(rect.maxX == 300 && rect.maxY == 200)
        #expect(rect.width == 100 && rect.height == 50)
    }

    @Test func optionResizesAroundCentre() {
        let start = RotatedRect(rect: CGRect(x: 100, y: 100, width: 200, height: 100), rotation: 0)
        let rect = start.resized(corner: 2, to: CGPoint(x: 400, y: 150), aspect: 2, fromCenter: true)
        #expect(rect.midX == 200 && rect.midY == 150)
        #expect(rect.width == 400)
    }

    @Test func rotatedResizeKeepsOppositeCornerInPlace() {
        let start = RotatedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 50), rotation: .pi / 6)
        let fixed = start.corners[0]
        let dragTo = start.worldPoint(CGPoint(x: 100, y: 50)) // well beyond the bottom-right corner
        let rect = start.resized(corner: 2, to: dragTo, aspect: 2, fromCenter: false)
        let after = RotatedRect(rect: rect, rotation: start.rotation).corners[0]
        #expect(abs(after.x - fixed.x) < 1e-9 && abs(after.y - fixed.y) < 1e-9)
    }

    @Test func minimumSize() {
        let start = RotatedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 50), rotation: 0)
        #expect(start.resized(corner: 2, to: CGPoint(x: -500, y: -500), aspect: 2, fromCenter: false).width == 8)
    }

    @Test func angleNormalisation() {
        #expect(abs(RotatedRect.normalizedAngle(3 * .pi) - .pi) < 1e-9)
        #expect(abs(RotatedRect.normalizedAngle(-3 * .pi / 2) - .pi / 2) < 1e-9)
    }
}
