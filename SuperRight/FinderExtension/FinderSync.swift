import AppKit
import FinderSync
import OSLog

final class FinderSync: FIFinderSync {
    private let fileCreator = FileCreator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.SuperRight.FinderExtension",
        category: "FinderSync"
    )

    override init() {
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(monitoredDirectoriesDidChange),
            name: MonitoringConfiguration.didChangeNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(mountedVolumesDidChange),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(mountedVolumesDidChange),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        registerMonitoredDirectories()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        logger.info(
            "Menu requested: kind=\(menuKind.rawValue), target=\(controller.targetedURL()?.path(percentEncoded: false) ?? "nil", privacy: .public)"
        )

        guard menuKind == .contextualMenuForContainer ||
                menuKind == .contextualMenuForItems ||
                menuKind == .toolbarItemMenu else {
            return nil
        }

        let menu = NSMenu(title: "")
        let superRightItem = NSMenuItem(title: "SuperRight", action: nil, keyEquivalent: "")
        superRightItem.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)

        let actionsMenu = NSMenu(title: "SuperRight")
        actionsMenu.addItem(makeNewFileMenu())
        actionsMenu.addItem(.separator())

        let terminalItem = NSMenuItem(title: "在 Terminal 中打开", action: #selector(openInTerminal), keyEquivalent: "")
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        terminalItem.target = self
        actionsMenu.addItem(terminalItem)

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
            let iTermItem = NSMenuItem(title: "在 iTerm2 中打开", action: #selector(openInITerm), keyEquivalent: "")
            iTermItem.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)
            iTermItem.target = self
            actionsMenu.addItem(iTermItem)
        }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil {
            let vscodeItem = NSMenuItem(
                title: "在 Visual Studio Code 中打开",
                action: #selector(openInVSCode),
                keyEquivalent: ""
            )
            vscodeItem.image = NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: nil
            )
            vscodeItem.target = self
            actionsMenu.addItem(vscodeItem)
        }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") != nil {
            let warpItem = NSMenuItem(title: "在 Warp 中打开", action: #selector(openInWarp), keyEquivalent: "")
            warpItem.image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: nil)
            warpItem.target = self
            actionsMenu.addItem(warpItem)
        }

        let copyItem = NSMenuItem(title: "复制当前路径", action: #selector(copyPath), keyEquivalent: "")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.target = self
        actionsMenu.addItem(copyItem)

        superRightItem.submenu = actionsMenu
        menu.addItem(superRightItem)

        return menu
    }

    private func registerMonitoredDirectories() {
        let paths = MonitoringConfiguration.loadPaths()

        let directories = Set(paths.compactMap { path -> URL? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        })

        FIFinderSyncController.default().directoryURLs = directories
        logger.info(
            "Registered \(directories.count) Finder roots: \(directories.map(\.path).sorted().joined(separator: ", "), privacy: .public)"
        )
    }

    @objc private func monitoredDirectoriesDidChange(_ notification: Notification) {
        registerMonitoredDirectories()
    }

    @objc private func mountedVolumesDidChange(_ notification: Notification) {
        registerMonitoredDirectories()
    }

    override var toolbarItemName: String { "SuperRight" }

    override var toolbarItemToolTip: String { "新建文件或在终端中打开" }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "SuperRight")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    private func makeNewFileMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)

        let submenu = NSMenu(title: "新建文件")
        submenu.addItem(actionItem("文本文档 (.txt)", selector: #selector(createTextFile), icon: "doc.text"))
        submenu.addItem(actionItem("Markdown (.md)", selector: #selector(createMarkdownFile), icon: "text.document"))
        submenu.addItem(actionItem("Word 文档 (.docx)", selector: #selector(createWordFile), icon: "doc.richtext"))
        submenu.addItem(actionItem("JSON 文件 (.json)", selector: #selector(createJSONFile), icon: "curlybraces"))
        parent.submenu = submenu
        return parent
    }

    private func actionItem(_ title: String, selector: Selector, icon: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        item.target = self
        return item
    }

    @objc private func createTextFile() {
        createFile(kind: .text)
    }

    @objc private func createMarkdownFile() {
        createFile(kind: .markdown)
    }

    @objc private func createWordFile() {
        createFile(kind: .word)
    }

    @objc private func createJSONFile() {
        createFile(kind: .json)
    }

    private func createFile(kind: FileKind) {
        guard let directory = currentDirectory() else {
            NSSound.beep()
            return
        }

        do {
            let createdURL = try fileCreator.create(kind, in: directory)
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            NSLog("SuperRight could not create file: %@", error.localizedDescription)
            NSSound.beep()
        }
    }

    @objc private func openInTerminal() {
        openCurrentDirectory(inApplication: "com.apple.Terminal")
    }

    @objc private func openInITerm() {
        openCurrentDirectory(inApplication: "com.googlecode.iterm2")
    }

    @objc private func openInVSCode() {
        openCurrentDirectory(inApplication: "com.microsoft.VSCode")
    }

    @objc private func openInWarp() {
        guard let directory = currentDirectory() else {
            NSSound.beep()
            return
        }

        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = "/new_tab"
        components.queryItems = [
            URLQueryItem(name: "path", value: directory.path(percentEncoded: false))
        ]

        guard let url = components.url, NSWorkspace.shared.open(url) else {
            // Fall back to Launch Services if this Warp build doesn't support
            // the URI action yet.
            openCurrentDirectory(inApplication: "dev.warp.Warp-Stable")
            return
        }
    }

    private func openCurrentDirectory(inApplication bundleIdentifier: String) {
        guard let directory = currentDirectory(),
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("SuperRight could not open terminal: %@", error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    @objc private func copyPath() {
        guard let directory = currentDirectory() else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(directory.path(percentEncoded: false), forType: .string)
    }

    private func currentDirectory() -> URL? {
        let controller = FIFinderSyncController.default()

        if let targetedURL = controller.targetedURL() {
            return directoryRepresented(by: targetedURL)
        }

        if let selectedURL = controller.selectedItemURLs()?.first {
            return directoryRepresented(by: selectedURL)
        }

        return nil
    }

    private func directoryRepresented(by url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
