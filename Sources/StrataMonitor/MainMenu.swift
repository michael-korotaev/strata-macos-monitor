import AppKit

/// Minimal main menu of the menu bar app.
///
/// The app lives in the menu bar (accessory policy), so it has no visible
/// menu bar. But AppKit takes the keyboard shortcuts from the main menu: with
/// no menu at all there is no source of `⌘V`, `⌘C` and `⌘A`, so pasting into
/// the address field does nothing. The menu is invisible, but it makes the
/// standard editing shortcuts work.
enum MainMenu {
    /// Installs the menu. Call it after `NSApplication.shared` is created.
    static func install() {
        let name = bundleName
        let mainMenu = NSMenu()

        // Application menu: about, hide, quit.
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: name)
        let about = NSMenuItem(
            title: "About \(name)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(
            title: "Hide \(name)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hide.target = NSApp
        appMenu.addItem(hide)
        let quit = NSMenuItem(
            title: "Quit \(name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu: the shortcuts of the text fields.
        //
        // The target is left empty on purpose: the action goes through the
        // responder chain to the field that is being edited.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = nil
    }

    private static var bundleName: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleName"] as? String
        let display = info?["CFBundleDisplayName"] as? String
        return display ?? name ?? "Strata Monitor"
    }
}
