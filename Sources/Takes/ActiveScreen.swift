import AppKit

/// Which display Takes's windows open on: the one you're on. A window made at the origin sits on the built-in
/// display, so `center()` alone opened Settings, About and setup there whatever display you clicked on.
extension ScreenChoice {
    /// The display under the pointer: where you just clicked the menu bar icon, Finder, Spotlight or the Dock.
    @MainActor static var active: NSScreen {
        let screens = NSScreen.screens
        return index(containing: NSEvent.mouseLocation, in: screens.map(\.frame)).map { screens[$0] } ?? NSScreen.main ?? screens[0]
    }

    /// The display holding `point`, else the nearest one. The pointer's top row (in the menu bar) is at the
    /// display's maxY, which `CGRect.contains` leaves out.
    static func index(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        if let hit = frames.firstIndex(where: { point.x >= $0.minX && point.x < $0.maxX && point.y > $0.minY && point.y <= $0.maxY }) {
            return hit
        }
        func distance(_ frame: CGRect) -> CGFloat {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) }
    }

    /// Where a window of `size` goes on a display's visible frame: centred across, a little above the middle like
    /// `NSWindow.center()`, and never past the top.
    static func centred(_ size: CGSize, in visible: CGRect) -> CGPoint {
        let x = visible.midX - size.width / 2
        let y = size.height >= visible.height ? visible.maxY - size.height : visible.minY + (visible.height - size.height) * 2 / 3
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

extension NSWindow {
    /// Brings the window to the display you're on, centred, unless it's already there (where it keeps the place
    /// it has or you gave it). Call before ordering it front.
    @MainActor func moveToActiveScreen() {
        let screen = ScreenChoice.active
        let frames = NSScreen.screens.map(\.frame)
        if let current = ScreenChoice.index(for: frame, in: frames), NSScreen.screens[current] == screen { return }
        setFrameOrigin(ScreenChoice.centred(frame.size, in: screen.visibleFrame))
    }
}
