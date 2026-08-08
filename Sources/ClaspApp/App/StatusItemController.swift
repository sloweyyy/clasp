import AppKit
import ClaspCore
import SwiftUI

/// Owns Clasp's menu-bar status item. A left click toggles a popover with the
/// task library anchored to the menu bar; a right click or Control-click
/// shows the full menu.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let onCapture: () -> Void
    private let onOpenMain: () -> Void
    private let onPresentationMode: (ClaspPresentationMode) -> Void
    private let onSettings: () -> Void

    private var statusItem: NSStatusItem?
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: LibraryView(model: model)
        )
        return popover
    }()

    init(
        model: AppModel,
        onCapture: @escaping () -> Void,
        onOpenMain: @escaping () -> Void,
        onPresentationMode: @escaping (ClaspPresentationMode) -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.model = model
        self.onCapture = onCapture
        self.onOpenMain = onOpenMain
        self.onPresentationMode = onPresentationMode
        self.onSettings = onSettings
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = item.button {
            button.image = ClaspBrand.menuBarIcon
            button.toolTip = "Clasp — click to open, right-click for menu"
            button.setAccessibilityLabel("Clasp")
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else if model.destinations == nil {
            onSettings()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        let visibleHeight = (button.window?.screen ?? NSScreen.main)?
            .visibleFrame.height ?? 720
        popover.contentSize = NSSize(
            width: 460,
            height: min(720, visibleHeight - 24)
        )
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.loadLibrary() }
    }

    private func showMenu() {
        guard let statusItem else { return }
        if popover.isShown {
            popover.performClose(nil)
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(actionItem(
            "Capture Selection",
            key: "c",
            action: #selector(capture)
        ))
        menu.addItem(actionItem(
            "Open Clasp",
            key: "o",
            action: #selector(openMain)
        ))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Window Mode"))
        for mode in ClaspPresentationMode.allCases {
            let modeItem = NSMenuItem(
                title: "\(mode.title) — \(mode.helpText)",
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = mode
            modeItem.state = model.presentationMode == mode ? .on : .off
            menu.addItem(modeItem)
        }

        let pendingCount = model.captures.filter {
            $0.delivery == .pending || $0.delivery == .failed
        }.count
        if pendingCount > 0 {
            let info = NSMenuItem(
                title: "\(pendingCount) capture\(pendingCount == 1 ? "" : "s") need attention",
                action: nil,
                keyEquivalent: ""
            )
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(
            "Settings…",
            key: ",",
            action: #selector(openSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(
            "Quit Clasp",
            key: "q",
            action: #selector(quit)
        ))
        return menu
    }

    private func actionItem(
        _ title: String,
        key: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func capture() {
        onCapture()
    }

    @objc private func openMain() {
        onOpenMain()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? ClaspPresentationMode else {
            return
        }
        onPresentationMode(mode)
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
