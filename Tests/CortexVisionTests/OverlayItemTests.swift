import Testing
import CoreGraphics
@testable import CortexVision

@Suite("OverlayItem — Model")
struct OverlayItemModelTests {

    @Test("Unique identifiers", .tags(.core))
    func uniqueIds() {
        let a = OverlayItem(bounds: .zero, kind: .text)
        let b = OverlayItem(bounds: .zero, kind: .text)
        #expect(a.id != b.id)
    }

    @Test("Default selection state is false", .tags(.core))
    func defaultNotSelected() {
        let item = OverlayItem(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), kind: .figure)
        #expect(item.isSelected == false)
    }

    @Test("Select overlay via isSelected", .tags(.core))
    func selectOverlay() {
        var item = OverlayItem(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), kind: .figure)
        item.isSelected = true
        #expect(item.isSelected == true)
        item.isSelected = false
        #expect(item.isSelected == false)
    }

    // TC-5a.2: Move overlay
    @Test("Move overlay shifts bounds correctly", .tags(.core))
    func moveOverlay() {
        var item = OverlayItem(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), kind: .figure)
        item.move(dx: 0.05, dy: 0.1)
        #expect(abs(item.bounds.origin.x - 0.15) < 0.001)
        #expect(abs(item.bounds.origin.y - 0.30) < 0.001)
        #expect(abs(item.bounds.width - 0.3) < 0.001)
        #expect(abs(item.bounds.height - 0.4) < 0.001)
    }

    // TC-5a.6: Move overlay outside image bounds → clamped
    @Test("Move overlay beyond edge is clamped to 0..1", .tags(.core))
    func moveClampsBounds() {
        var item = OverlayItem(bounds: CGRect(x: 0.8, y: 0.8, width: 0.3, height: 0.3), kind: .figure)
        item.move(dx: 0.5, dy: 0.5)
        #expect(item.bounds.origin.x >= 0)
        #expect(item.bounds.origin.y >= 0)
        #expect(item.bounds.maxX <= 1.0 + 0.001)
        #expect(item.bounds.maxY <= 1.0 + 0.001)
    }

    // TC-5a.3: Resize overlay
    @Test("Resize overlay changes width and height", .tags(.core))
    func resizeOverlay() {
        var item = OverlayItem(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), kind: .figure)
        item.resize(to: CGRect(x: 0.05, y: 0.15, width: 0.5, height: 0.6))
        #expect(abs(item.bounds.width - 0.5) < 0.001)
        #expect(abs(item.bounds.height - 0.6) < 0.001)
    }

    // TC-5a.4: Delete overlay from collection
    @Test("Remove overlay from array reduces count", .tags(.core))
    func removeOverlay() {
        var items = [
            OverlayItem(bounds: .zero, kind: .text),
            OverlayItem(bounds: .zero, kind: .figure),
            OverlayItem(bounds: .zero, kind: .text),
        ]
        let removeId = items[1].id
        items.removeAll { $0.id == removeId }
        #expect(items.count == 2)
    }

    // TC-5a.5: Add new overlay
    @Test("Add new overlay increases array count", .tags(.core))
    func addOverlay() {
        var items: [OverlayItem] = []
        let newItem = OverlayItem(
            bounds: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2),
            kind: .figure,
            isManual: true
        )
        items.append(newItem)
        #expect(items.count == 1)
        #expect(items[0].isManual == true)
        #expect(items[0].kind == .figure)
    }

    @Test("Pixel rect conversion is correct", .tags(.core))
    func pixelRectConversion() {
        let item = OverlayItem(bounds: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), kind: .figure)
        let pixelRect = item.pixelRect(for: CGSize(width: 1000, height: 800))
        #expect(abs(pixelRect.origin.x - 250) < 0.1)
        #expect(abs(pixelRect.origin.y - 400) < 0.1)
        #expect(abs(pixelRect.width - 500) < 0.1)
        #expect(abs(pixelRect.height - 200) < 0.1)
    }

    @Test("Manual overlay is flagged correctly", .tags(.core))
    func manualFlag() {
        let auto = OverlayItem(bounds: .zero, kind: .figure)
        let manual = OverlayItem(bounds: .zero, kind: .figure, isManual: true)
        #expect(auto.isManual == false)
        #expect(manual.isManual == true)
    }
}
