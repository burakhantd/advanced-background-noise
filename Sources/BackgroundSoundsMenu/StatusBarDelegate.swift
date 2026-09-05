import AppKit
import Combine
import SwiftUI

/// Owns the status item so left and right clicks have distinct, native behavior.
@MainActor
final class StatusBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var store: BackgroundSoundsStore?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var resizeObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let store = Self.store else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        resizeObservation = NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)
            .sink { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      window === self.popover.contentViewController?.view.window else { return }
                self.positionPopover()
            }
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store))
        updateIcon()
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
                let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
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
        let image = NSImage(systemSymbolName: store.menuBarSymbol, accessibilityDescription: "Advanced Background Noise")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "Advanced Background Noise"
    }

    @objc private func handleClick() {
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if let hostingView = popover.contentViewController?.view {
                hostingView.layoutSubtreeIfNeeded()
                popover.contentSize = hostingView.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            positionPopover()
            focusPopover()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        positionPopover()
        focusPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if popover.isShown { focusPopover() }
    }

    func applicationDidResignActive(_ notification: Notification) {
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
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = MenuPanelPlacement.origin(
            size: window.frame.size, anchor: anchor, visibleFrame: screen.visibleFrame
        )
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

    @objc private func quitApp() { Self.store?.quit() }
}
