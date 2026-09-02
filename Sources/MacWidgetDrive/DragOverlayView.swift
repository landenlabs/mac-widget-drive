import AppKit

/// Transparent NSView that captures mouse events for window dragging.
/// Added/removed as a subview of the desktop window's content view while
/// drag mode is active.
class DragOverlayView: NSView {
    var onMove: ((NSPoint) -> Void)?

    private var dragStart: NSPoint = .zero
    private var winStart: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        winStart = window?.frame.origin ?? .zero
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: winStart.x + loc.x - dragStart.x,
            y: winStart.y + loc.y - dragStart.y
        )
        window?.setFrameOrigin(newOrigin)
        onMove?(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
