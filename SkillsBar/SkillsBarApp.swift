import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct SkillsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = SkillStore()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            store.start()
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 650)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(store: store)
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

        // Draw a forward slash (the way you invoke skills)
        let slashPath = NSBezierPath()
        slashPath.lineWidth = 2.0
        slashPath.lineCapStyle = .round
        slashPath.move(to: NSPoint(x: cx - 2.5, y: cy - 5.5))
        slashPath.line(to: NSPoint(x: cx + 2.5, y: cy + 5.5))
        NSColor.black.setStroke()
        slashPath.stroke()

        // Draw a 4-point sparkle (AI) at top-right
        let sx: CGFloat = cx + 5.5
        let sy: CGFloat = cy + 4.0
        let sparkleSize: CGFloat = 2.8

        let sparklePath = NSBezierPath()
        // Vertical
        sparklePath.move(to: NSPoint(x: sx, y: sy - sparkleSize))
        sparklePath.line(to: NSPoint(x: sx, y: sy + sparkleSize))
        // Horizontal
        sparklePath.move(to: NSPoint(x: sx - sparkleSize, y: sy))
        sparklePath.line(to: NSPoint(x: sx + sparkleSize, y: sy))

        sparklePath.lineWidth = 1.0
        sparklePath.lineCapStyle = .round
        sparklePath.stroke()

        // Small dot at sparkle center
        let dotRect = NSRect(x: sx - 0.6, y: sy - 0.6, width: 1.2, height: 1.2)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
