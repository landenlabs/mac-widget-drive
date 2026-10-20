import AppKit
import SwiftUI

class DesktopWindowManager: NSObject, ObservableObject {
    private let appState: AppState
    private var window: DesktopWindow?
    private var dragOverlay: DragOverlayView?
    private var isDragModeActive = false

    @Published var isDragging: Bool = false
    private var screenObserver: NSObjectProtocol?
    private var screenChangeWork: DispatchWorkItem?

    private static let windowSize = NSSize(width: 250, height: 108)
    // Kept just above desktop icons, like the clock widget, so it stays
    // below normal app windows instead of floating over everything.
    // Windows at this level don't reliably receive mouse events from the
    // WindowServer (a documented macOS limitation, not fixable via
    // canBecomeKey/acceptsFirstMouse), so the widget is read-only at rest —
    // ignoresMouseEvents only turns off during an explicit drag.
    private let restingLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(CGWindowLevelKey(rawValue: 2)!)) + 1)

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        let view = DesktopTrafficView(appState: appState, windowManager: self)
        let hostingView = NSHostingView(rootView: view)

        let win = DesktopWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.level = restingLevel
        win.contentView = hostingView

        placeWindow(win)
        win.orderFront(nil)
        window = win

        // Re-place when displays change (also fires as externals attach after login/wake).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenChangeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let win = self.window, !self.isDragModeActive else { return }
                self.placeWindow(win)
            }
            self?.screenChangeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    func teardown() {
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
        screenChangeWork?.cancel()
        if isDragModeActive { isDragging = false }
        dragOverlay?.removeFromSuperview()
        dragOverlay = nil
        window?.close()
        window = nil
    }

    // MARK: - Position

    private func placeWindow(_ win: NSWindow) {
        let size = Self.windowSize
        var x = appState.positionX
        var y = appState.positionY // stored as TOP edge (frame.maxY)

        let hasSaved = appState.screenPositions[ScreenFingerprint.current] != nil
        if !hasSaved && x == 0 && y == 0 {
            guard let screen = NSScreen.main else { return }
            x = screen.visibleFrame.maxX - size.width - 20
            y = screen.visibleFrame.maxY - 20
            appState.updatePosition(x: x, y: y)
        } else {
            let widgetRect = NSRect(x: x, y: y - size.height, width: size.width, height: size.height)
            let screen = bestScreen(for: widgetRect) ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                x = min(max(x, vf.minX), vf.maxX - size.width)
                y = min(max(y, vf.minY + size.height), vf.maxY)
            }
        }

        win.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    /// The connected screen whose frame overlaps `rect` the most, or nil if
    /// the rect lies entirely off every screen.
    private func bestScreen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens
            .map { (screen: $0, overlap: overlapArea($0.frame, rect)) }
            .filter { $0.overlap > 0 }
            .max { $0.overlap < $1.overlap }?
            .screen
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    // MARK: - Drag mode

    func toggleDragMode() {
        isDragModeActive ? disableDragMode() : enableDragMode()
    }

    private func enableDragMode() {
        guard let win = window else { return }
        isDragModeActive = true
        isDragging = true

        win.ignoresMouseEvents = false
        win.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        win.orderFrontRegardless()
        win.makeKey()

        let overlay = DragOverlayView(frame: win.contentView?.bounds ?? .zero)
        overlay.autoresizingMask = [.width, .height]
        overlay.onMove = { [weak self] origin in
            guard let self else { return }
            let topY = origin.y + (self.window?.frame.height ?? 0)
            self.appState.updatePosition(x: origin.x, y: topY)
        }
        win.contentView?.addSubview(overlay, positioned: .above, relativeTo: nil)
        dragOverlay = overlay
        (win as? DesktopWindow)?.onDragMove = overlay.onMove
    }

    private func disableDragMode() {
        guard let win = window else { return }
        isDragModeActive = false
        isDragging = false

        dragOverlay?.removeFromSuperview()
        dragOverlay = nil
        (win as? DesktopWindow)?.onDragMove = nil

        win.level = restingLevel
        win.ignoresMouseEvents = true

        appState.updatePosition(x: win.frame.origin.x, y: win.frame.maxY)
    }
}

/// Borderless window that can take key status and handles drag-mode mouse events itself.
class DesktopWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Set while in drag mode; handles the drag before any view (incl. SwiftUI's) sees the event.
    var onDragMove: ((NSPoint) -> Void)?
    private var dragStart: NSPoint = .zero
    private var winStart:  NSPoint = .zero

    override func sendEvent(_ event: NSEvent) {
        guard onDragMove != nil else { return super.sendEvent(event) }
        switch event.type {
        case .leftMouseDown:
            dragStart = NSEvent.mouseLocation
            winStart  = frame.origin
            NSCursor.closedHand.set()
        case .leftMouseDragged:
            let loc = NSEvent.mouseLocation
            let origin = NSPoint(x: winStart.x + loc.x - dragStart.x,
                                 y: winStart.y + loc.y - dragStart.y)
            setFrameOrigin(origin)
            onDragMove?(origin)
        case .leftMouseUp:
            NSCursor.openHand.set()
            onDragMove?(frame.origin)
        default:
            super.sendEvent(event)
        }
    }
}
