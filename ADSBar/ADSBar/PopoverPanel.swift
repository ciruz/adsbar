import AppKit

@MainActor
final class PopoverPanel: NSPanel {
    var onClose: (() -> Void)?
    private(set) var lastCloseTime = Date.distantPast
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isClosing = false
    private var isResizing = false
    private weak var anchorButton: NSStatusBarButton?
    private var sizeObservation: NSKeyValueObservation?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func resignKey() {
        super.resignKey()
        if !isClosing, !isResizing { close() }
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        removeMonitors()
        lastCloseTime = Date()
        orderOut(nil)
        onClose?()
        isClosing = false
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        guard let vc = contentViewController else { return }

        vc.view.layoutSubtreeIfNeeded()
        positionAndResize(vc.preferredContentSize, relativeTo: button)

        makeKeyAndOrderFront(nil)
        installMonitors()

        sizeObservation = vc.observe(\.preferredContentSize) { [weak self] vc, _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.anchorButton else { return }
                let newSize = vc.preferredContentSize
                let currentSize = self.frame.size
                let dh = abs(newSize.height - currentSize.height)
                guard dh > 10 else { return }
                self.positionAndResize(newSize, relativeTo: button)
            }
        }
    }

    private func positionAndResize(_ size: CGSize, relativeTo button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        let bRect = bw.convertToScreen(button.convert(button.bounds, to: nil))
        var x = bRect.midX - size.width / 2
        let y = bRect.minY - size.height - 4

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            x = max(sf.minX + 4, min(x, sf.maxX - size.width - 4))
        }

        isResizing = true
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isResizing = false
            if isVisible, !isKeyWindow {
                makeKeyAndOrderFront(nil)
            }
        }
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self {
                close()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor { NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        sizeObservation?.invalidate()
        sizeObservation = nil
    }
}
