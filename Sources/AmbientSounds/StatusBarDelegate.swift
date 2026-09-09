import AppKit
import Combine
import SwiftUI

private final class StablePopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Owns the status item so left and right clicks have distinct, native behavior.
@MainActor
final class StatusBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var store: BackgroundSoundsStore?
    nonisolated(unsafe) static var suppressPopoverDismiss = false
    static weak var shared: StatusBarDelegate?

    static func beginSuppressingDismiss() {
        suppressPopoverDismiss = true
        shared?.popover.behavior = .applicationDefined
    }

    static func endSuppressingDismiss() {
        suppressPopoverDismiss = false
        shared?.popover.behavior = .transient
        shared?.focusPopover()
    }
    private var presentationAnchor: CGRect?
    private var presentationOrigin: CGPoint?
    private var popoverClosedTimestamp: TimeInterval = 0
    private var statusItem: NSStatusItem?
    private let popoverAnchorView = StablePopoverAnchorView(
        frame: CGRect(x: -8, y: -6, width: 48, height: 36)
    )
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        guard let store = Self.store else { return }
        let item = NSStatusBar.system.statusItem(withLength: 32)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = item.button, let superview = button.superview {
            // Keep the popover attached to a stable, oversized invisible
            // rectangle rather than to the changing SF Symbol bounds.
            popoverAnchorView.alphaValue = 0.001
            popoverAnchorView.autoresizingMask = []
            popoverAnchorView.frame = button.frame.insetBy(dx: -8, dy: -6)
            superview.addSubview(popoverAnchorView, positioned: .below, relativeTo: button)
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store))
        updateIcon()
        _ = AppUpdater.shared
        if CommandLine.arguments.contains("--show-panel") || CommandLine.arguments.contains("--verify-panel-position") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                if !popover.isShown { handleClick() }
            }
        }
        if CommandLine.arguments.contains("--verify-panel-position") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                guard let button = statusItem?.button,
                      let anchorWindow = button.window,
                      let panelWindow = popover.contentViewController?.view.window,
                      let screen = anchorWindow.screen else {
                    print("POSITION FAIL: button=\(statusItem?.button != nil) anchor=\(String(describing: statusItem?.button?.window?.frame)) panel=\(String(describing: popover.contentViewController?.view.window?.frame)) shown=\(popover.isShown)")
                    Foundation.exit(1)
                }
                let anchor = anchorWindow.convertToScreen(
                    popoverAnchorView.convert(popoverAnchorView.bounds, to: nil)
                )
                let panel = panelWindow.frame
                let safeTop = min(anchor.minY, screen.visibleFrame.maxY)
                let passed = panel.maxY <= safeTop + 1 && panel.minY >= screen.visibleFrame.minY && panelWindow.isKeyWindow && button.isHighlighted
                print("POSITION \(passed ? "PASS" : "FAIL") anchor=\(anchor) panel=\(panel) visible=\(screen.visibleFrame) key=\(panelWindow.isKeyWindow) active=\(NSApp.isActive) selected=\(button.isHighlighted)")
                guard passed else { Foundation.exit(1) }
                applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                    let closed = !popover.isShown && statusItem?.button?.isHighlighted == false
                    print("DISMISS \(closed ? "PASS" : "FAIL")")
                    Foundation.exit(closed ? 0 : 1)
                }
            }
        }
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
    }

    private func updateIcon() {
        guard let store = Self.store else { return }
        let image = NSImage(systemSymbolName: store.menuBarSymbol, accessibilityDescription: "Ambient Sounds")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "Ambient Sounds"
    }

   @objc private func handleClick() {
       guard let button = statusItem?.button else { return }
       if NSApp.currentEvent?.type == .rightMouseUp {
           popover.performClose(nil)
           showQuickMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - popoverClosedTimestamp < 0.28 {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if let hostingView = popover.contentViewController?.view {
            hostingView.layoutSubtreeIfNeeded()
            popover.contentSize = hostingView.fittingSize
        }
        presentationAnchor = button.window.map {
            $0.convertToScreen(popoverAnchorView.convert(popoverAnchorView.bounds, to: nil))
        }
        presentationOrigin = nil
        popover.show(
            relativeTo: popoverAnchorView.bounds,
            of: popoverAnchorView,
            preferredEdge: .minY
        )
        positionPopover()
        focusPopover()
    }

   func popoverDidShow(_ notification: Notification) {
       positionPopover()
       focusPopover()
       Self.store?.notifyMenuOpened()
   }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        !Self.suppressPopoverDismiss
    }

   func popoverDidClose(_ notification: Notification) {
       popoverClosedTimestamp = ProcessInfo.processInfo.systemUptime
       presentationAnchor = nil
       presentationOrigin = nil
       statusItem?.button?.highlight(false)
   }

    func applicationDidBecomeActive(_ notification: Notification) {
        if popover.isShown { focusPopover() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if Self.suppressPopoverDismiss { return }
        popover.performClose(nil)
    }

    private func focusPopover() {
        guard popover.isShown else { return }
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        statusItem?.button?.highlight(true)
    }

    private func positionPopover() {
        guard popover.isShown, let button = statusItem?.button,
              let anchorWindow = button.window, let screen = anchorWindow.screen,
              let window = popover.contentViewController?.view.window else { return }
        let anchor = presentationAnchor ?? anchorWindow.convertToScreen(
            popoverAnchorView.convert(popoverAnchorView.bounds, to: nil)
        )
        let origin = MenuPanelPlacement.origin(
            size: window.frame.size,
            anchor: anchor,
            visibleFrame: screen.visibleFrame,
            lockedOrigin: presentationOrigin
        )
        if presentationOrigin == nil { presentationOrigin = origin }
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
    }

    private func showQuickMenu() {
        guard let store = Self.store, let statusItem else { return }
        let menu = NSMenu()
        for (index, reference) in store.shortcuts.prefix(5).enumerated() {
            let item = NSMenuItem(title: store.title(for: reference), action: #selector(activateShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = NSImage(systemSymbolName: store.symbol(for: reference), accessibilityDescription: nil)
            item.state = store.isSelected(reference) && store.isEnabled ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func activateShortcut(_ sender: NSMenuItem) {
        guard let store = Self.store, store.shortcuts.indices.contains(sender.tag) else { return }
        store.activatePrimary(store.shortcuts[sender.tag])
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    @objc private func quitApp() { Self.store?.quit() }
}
