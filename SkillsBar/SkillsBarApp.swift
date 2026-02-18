import SwiftUI
import AppKit
import Carbon.HIToolbox

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store: SkillStore
    private let usageTracker: UsageTracker

    override init() {
        let tracker = UsageTracker()
        self.usageTracker = tracker
        self.store = SkillStore(usageTracker: tracker)
        super.init()
    }
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent Settings window from appearing on launch
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            store.start()
            usageTracker.refresh()
            usageTracker.startAutoRefresh()
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 650)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(store: store, usageTracker: usageTracker)
        )

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.create()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Global hotkey (Cmd+Shift+K)
        registerGlobalHotkey()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyNotification),
            name: NSNotification.Name("ToggleSkillsBarPopover"),
            object: nil
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func handleHotkeyNotification() {
        togglePopover(nil)
    }

    private func registerGlobalHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                NotificationCenter.default.post(
                    name: NSNotification.Name("ToggleSkillsBarPopover"),
                    object: nil
                )
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        eventHandler = handlerRef

        let hotKeyID = EventHotKeyID(signature: OSType(0x534B4252), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}

enum MenuBarIcon {
    static func create() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let cx = size / 2
        let cy = size / 2

        let slashPath = NSBezierPath()
        slashPath.lineWidth = 2.0
        slashPath.lineCapStyle = .round
        slashPath.move(to: NSPoint(x: cx - 2.5, y: cy - 5.5))
        slashPath.line(to: NSPoint(x: cx + 2.5, y: cy + 5.5))
        NSColor.black.setStroke()
        slashPath.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
