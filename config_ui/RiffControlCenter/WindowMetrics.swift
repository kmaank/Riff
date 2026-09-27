import AppKit

/// Screen-aware size for the Riff window so first launch is never a clipped postcard.
enum WindowMetrics {
    static let minWidth: CGFloat = 840
    static let minHeight: CGFloat = 640
    static let preferredWidth: CGFloat = 1000
    static let preferredHeight: CGFloat = 780
    static let maxWidth: CGFloat = 1220
    static let maxHeight: CGFloat = 920

    static func targetFrame(on screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        let margin: CGFloat = 56
        let maxW = max(vis.width - margin, 640)
        let maxH = max(vis.height - margin, 500)

        let scale = min(max(vis.width / 1512.0, 0.88), 1.18)
        var width = preferredWidth * scale
        var height = preferredHeight * scale

        width = min(min(max(width, minWidth), maxWidth), maxW)
        height = min(min(max(height, minHeight), maxHeight), maxH)
        if maxW < minWidth { width = maxW }
        if maxH < minHeight { height = maxH }

        return NSRect(
            x: vis.midX - width / 2,
            y: vis.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func minSize(on screen: NSScreen) -> NSSize {
        let vis = screen.visibleFrame
        return NSSize(
            width: min(minWidth, max(vis.width - 32, 640)),
            height: min(minHeight, max(vis.height - 32, 500))
        )
    }
}

final class WindowConfigurator: NSObject {
    static let shared = WindowConfigurator()
    private var sizedWindows = Set<ObjectIdentifier>()
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func windowBecameKey(_ note: Notification) {
        guard let window = note.object as? NSWindow, shouldManage(window) else { return }
        apply(to: window, force: false)
    }

    @objc private func screensChanged() {
        for window in NSApp.windows where shouldManage(window) {
            apply(to: window, force: false)
        }
    }

    func apply(to window: NSWindow, force: Bool) {
        guard shouldManage(window) else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let target = WindowMetrics.targetFrame(on: screen)
        window.minSize = WindowMetrics.minSize(on: screen)
        window.isRestorable = true
        window.appearance = NSApp.appearance
        window.backgroundColor = RiffTheme.nsWindow
        window.titlebarAppearsTransparent = true

        let id = ObjectIdentifier(window)
        let first = !sizedWindows.contains(id)
        let overflows = window.frame.width > screen.visibleFrame.width + 1
            || window.frame.height > screen.visibleFrame.height + 1
        let belowMin = window.frame.width + 1 < window.minSize.width
            || window.frame.height + 1 < window.minSize.height

        sizedWindows.insert(id)
        if first || force || overflows || belowMin {
            window.setFrame(target, display: true)
        }
    }

    private func shouldManage(_ window: NSWindow) -> Bool {
        if window.level != .normal { return false }
        if window.styleMask.contains(.nonactivatingPanel) { return false }
        if window.styleMask.contains(.borderless) && !window.styleMask.contains(.titled) { return false }
        return window.contentView != nil
    }
}
