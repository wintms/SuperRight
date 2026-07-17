import AppKit
import FinderSync
import OSLog

private struct FinderContext {
    let kind: FIMenuKind
    let targetedURL: URL?
    let selectedURLs: [URL]

    var copyURLs: [URL] {
        if kind == .contextualMenuForItems, !selectedURLs.isEmpty {
            return selectedURLs
        }
        if !selectedURLs.isEmpty, kind == .toolbarItemMenu {
            return selectedURLs
        }
        return targetedURL.map { [$0] } ?? []
    }

    var operationDirectory: URL? {
        if kind == .contextualMenuForItems, !selectedURLs.isEmpty {
            if selectedURLs.count == 1, selectedURLs[0].isDirectoryOnDisk {
                return selectedURLs[0]
            }
            return commonParent(of: selectedURLs)
        }

        if let targetedURL {
            return targetedURL.isDirectoryOnDisk ? targetedURL : targetedURL.deletingLastPathComponent()
        }

        if selectedURLs.count == 1, selectedURLs[0].isDirectoryOnDisk {
            return selectedURLs[0]
        }
        return commonParent(of: selectedURLs)
    }

    var relativeBaseDirectory: URL? {
        if let targetedURL, targetedURL.isDirectoryOnDisk { return targetedURL }
        return operationDirectory
    }

    private func commonParent(of urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let candidate = first.isDirectoryOnDisk ? first.deletingLastPathComponent() : first.deletingLastPathComponent()
        return urls.dropFirst().allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL == candidate.standardizedFileURL
        } ? candidate : first.deletingLastPathComponent()
    }
}

private extension URL {
    var isDirectoryOnDisk: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

final class FinderSync: FIFinderSync {
    private let fileCreator = FileCreator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.SuperRight.FinderExtension",
        category: "FinderSync"
    )
    private var settings = MonitoringConfiguration.loadSettings()
    private var activeContext: FinderContext?
    private var securityScopedURLs: [URL] = []

    override init() {
        NSWorkspaceBridge.applicationURL = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configurationDidChange),
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
        updateStatus(action: "Finder 扩展已启动", clearError: true)
        DistributedNotificationCenter.default().post(
            name: MonitoringConfiguration.requestConfigurationNotification,
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer ||
                menuKind == .contextualMenuForItems ||
                menuKind == .contextualMenuForSidebar ||
                menuKind == .toolbarItemMenu else {
            return nil
        }

        let controller = FIFinderSyncController.default()
        let context = FinderContext(
            kind: menuKind,
            targetedURL: controller.targetedURL()?.standardizedFileURL,
            selectedURLs: (controller.selectedItemURLs() ?? []).map(\.standardizedFileURL)
        )
        settings = MonitoringConfiguration.loadSettings()
        guard isWithinConfiguredScope(context) else { return nil }
        activeContext = context
        updateStatus(action: "Finder 菜单已响应")

        let targetPath = context.targetedURL?.path(percentEncoded: false) ?? "nil"
        logger.info(
            "Menu requested: kind=\(menuKind.rawValue), target=\(targetPath, privacy: .public), selected=\(context.selectedURLs.count)"
        )

        let actionsMenu = NSMenu(title: "SuperRight")
        for section in settings.menuOrder where !settings.hiddenMenuSections.contains(section) {
            guard let item = menuItem(for: section, context: context) else { continue }
            actionsMenu.addItem(item)
        }

        guard !actionsMenu.items.isEmpty else { return nil }
        if !settings.usesSubmenu { return actionsMenu }
        let menu = NSMenu(title: "")
        let superRightItem = NSMenuItem(title: "SuperRight", action: nil, keyEquivalent: "")
        superRightItem.image = NSImage(
            systemSymbolName: "cursorarrow.click.2",
            accessibilityDescription: "SuperRight"
        )
        superRightItem.submenu = actionsMenu
        menu.addItem(superRightItem)
        return menu
    }

    override var toolbarItemName: String { "SuperRight" }
    override var toolbarItemToolTip: String { SRLocalized("新建文件、复制路径或打开当前位置") }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "SuperRight")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    private func menuItem(for section: MenuSection, context: FinderContext) -> NSMenuItem? {
        switch section {
        case .newFile:
            return makeNewFileMenu(context: context)
        case .terminal:
            let application = ExternalApplicationCatalog.terminal(id: settings.terminalApplicationID)
            let item = actionItem(
                String(format: SRLocalized("在 %@ 中打开"), application.name),
                selector: #selector(openInTerminal),
                icon: "terminal",
                context: context
            )
            item.isEnabled = context.operationDirectory != nil && application.isInstalled
            return item
        case .editor:
            let application = ExternalApplicationCatalog.editor(id: settings.editorApplicationID)
            let item = actionItem(
                String(format: SRLocalized("在 %@ 中打开"), application.name),
                selector: #selector(openInEditor),
                icon: "chevron.left.forwardslash.chevron.right",
                context: context
            )
            item.isEnabled = context.operationDirectory != nil && application.isInstalled
            return item
        case .copyPath:
            return makeCopyMenu(context: context)
        }
    }

    private func makeNewFileMenu(context: FinderContext) -> NSMenuItem? {
        let templates = settings.templates.filter(\.isEnabled)
        guard !templates.isEmpty else { return nil }

        let parent = NSMenuItem(title: SRLocalized("新建文件"), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        let submenu = NSMenu(title: SRLocalized("新建文件"))
        let canWrite = context.operationDirectory.map {
            FileManager.default.isWritableFile(atPath: $0.path)
        } ?? false

        for template in templates {
            let item = actionItem(
                String(format: SRLocalized("%@ (.%@)"), template.name, template.fileExtension),
                selector: #selector(createFileFromTemplate(_:)),
                icon: icon(for: template),
                context: context
            )
            item.identifier = NSUserInterfaceItemIdentifier(template.id.uuidString)
            item.tag = settings.templates.firstIndex(where: { $0.id == template.id }) ?? -1
            item.isEnabled = canWrite
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func makeCopyMenu(context: FinderContext) -> NSMenuItem? {
        guard !context.copyURLs.isEmpty else { return nil }
        let parent = NSMenuItem(
            title: context.copyURLs.count > 1 ? SRLocalized("复制所选项目") : SRLocalized("复制路径"),
            action: nil,
            keyEquivalent: ""
        )
        parent.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        let submenu = NSMenu(title: SRLocalized("复制路径"))
        submenu.addItem(actionItem(SRLocalized("复制绝对路径"), selector: #selector(copyAbsolutePaths(_:)), icon: "point.topleft.down.to.point.bottomright.curvepath", context: context))
        submenu.addItem(actionItem(SRLocalized("复制文件名"), selector: #selector(copyFileNames(_:)), icon: "textformat", context: context))
        submenu.addItem(actionItem(SRLocalized("复制相对路径"), selector: #selector(copyRelativePaths(_:)), icon: "arrow.triangle.branch", context: context))
        submenu.addItem(actionItem(SRLocalized("复制文件 URL"), selector: #selector(copyFileURLs(_:)), icon: "link", context: context))
        submenu.addItem(actionItem(SRLocalized("复制 Shell 路径"), selector: #selector(copyShellPaths(_:)), icon: "terminal", context: context))
        parent.submenu = submenu
        return parent
    }

    private func actionItem(
        _ title: String,
        selector: Selector,
        icon: String,
        context: FinderContext
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        item.target = self
        return item
    }

    private func icon(for template: FileTemplate) -> String {
        switch template.format {
        case .word: "doc.richtext"
        case .plainText where template.fileExtension.lowercased() == "json": "curlybraces"
        case .plainText where template.fileExtension.lowercased() == "md": "text.document"
        case .plainText: "doc.text"
        }
    }

    @objc private func createFileFromTemplate(_ sender: NSMenuItem) {
        let templateID = sender.identifier.flatMap { UUID(uuidString: $0.rawValue) }
        let template = templateID.flatMap { templateID in
            settings.templates.first(where: { $0.id == templateID })
        } ?? settings.templates[safe: sender.tag]
        let context = liveFinderContext() ?? activeContext

        logger.info(
            "Create action invoked: identifier=\(sender.identifier?.rawValue ?? "nil", privacy: .public), tag=\(sender.tag), template=\(template != nil), context=\(context != nil)"
        )

        guard let template, let directory = context?.operationDirectory else {
            logger.error(
                "Create context unavailable: tag=\(sender.tag), template=\(template != nil), context=\(context != nil)"
            )
            reportError(title: SRLocalized("无法新建文件"), message: SRLocalized("Finder 没有提供有效的目标目录。"))
            return
        }

        let suggestedName = fileCreator.suggestedBaseName(for: template)
        let requestedName: String
        if settings.asksForFileName {
            guard delegateCreation(template: template, directory: directory) else { return }
            updateStatus(action: "已打开文件命名窗口", clearError: true)
            return
        } else {
            requestedName = suggestedName
        }

        do {
            let createdURL = try fileCreator.create(
                template: template,
                requestedName: requestedName,
                in: directory
            )
            updateStatus(action: "已创建 \(createdURL.lastPathComponent)", clearError: true)
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            if settings.opensCreatedFile {
                NSWorkspace.shared.open(createdURL)
            }
        } catch {
            reportError(title: SRLocalized("无法新建文件"), message: error.localizedDescription)
        }
    }

    private func delegateCreation(template: FileTemplate, directory: URL) -> Bool {
        var components = URLComponents()
        components.scheme = "superright"
        components.host = "create"
        components.queryItems = [
            URLQueryItem(name: "template", value: template.id.uuidString),
            URLQueryItem(name: "directory", value: directory.path(percentEncoded: false))
        ]
        guard let url = components.url,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.example.SuperRight"
              ) else {
            reportError(
                title: SRLocalized("无法新建文件"),
                message: SRLocalized("找不到 SuperRight 主程序，请将它安装到“应用程序”文件夹。")
            )
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.reportError(
                    title: SRLocalized("无法新建文件"),
                    message: String(
                        format: SRLocalized("无法打开 SuperRight 的文件命名窗口：%@"),
                        error.localizedDescription
                    )
                )
            }
        }
        return true
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        openCurrentDirectory(
            in: ExternalApplicationCatalog.terminal(id: settings.terminalApplicationID),
            context: actionContext(from: sender)
        )
    }

    @objc private func openInEditor(_ sender: NSMenuItem) {
        openCurrentDirectory(
            in: ExternalApplicationCatalog.editor(id: settings.editorApplicationID),
            context: actionContext(from: sender)
        )
    }

    private func openCurrentDirectory(in application: ExternalApplication, context: FinderContext?) {
        guard let directory = context?.operationDirectory,
              let bundleIdentifier = application.bundleIdentifiers.first(where: {
                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
              }),
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            reportError(
                title: SRLocalized("无法打开目录"),
                message: String(format: SRLocalized("没有找到 %@，请在 SuperRight 设置中选择其他应用。"), application.name)
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.reportError(
                        title: String(format: SRLocalized("无法使用 %@ 打开"), application.name),
                        message: error.localizedDescription
                    )
                } else {
                    self?.updateStatus(action: "已在 \(application.name) 中打开 \(directory.lastPathComponent)", clearError: true)
                }
            }
        }
    }

    @objc private func copyAbsolutePaths(_ sender: NSMenuItem) {
        copy(strings: actionContext(from: sender)?.copyURLs.map { $0.path(percentEncoded: false) } ?? [], action: "已复制绝对路径")
    }

    @objc private func copyFileNames(_ sender: NSMenuItem) {
        copy(strings: actionContext(from: sender)?.copyURLs.map(\.lastPathComponent) ?? [], action: "已复制文件名")
    }

    @objc private func copyRelativePaths(_ sender: NSMenuItem) {
        guard let context = actionContext(from: sender) else { return }
        let base = context.relativeBaseDirectory
        copy(strings: context.copyURLs.map { relativePath(for: $0, base: base) }, action: "已复制相对路径")
    }

    @objc private func copyFileURLs(_ sender: NSMenuItem) {
        copy(strings: actionContext(from: sender)?.copyURLs.map(\.absoluteString) ?? [], action: "已复制文件 URL")
    }

    @objc private func copyShellPaths(_ sender: NSMenuItem) {
        let paths = actionContext(from: sender)?.copyURLs.map { shellEscaped($0.path(percentEncoded: false)) } ?? []
        copy(strings: paths, action: "已复制 Shell 路径")
    }

    private func actionContext(from sender: NSMenuItem) -> FinderContext? {
        liveFinderContext() ?? activeContext
    }

    private func liveFinderContext() -> FinderContext? {
        let controller = FIFinderSyncController.default()
        let targetedURL = controller.targetedURL()?.standardizedFileURL
        let selectedURLs = (controller.selectedItemURLs() ?? []).map(\.standardizedFileURL)
        guard targetedURL != nil || !selectedURLs.isEmpty else { return nil }
        return FinderContext(
            kind: selectedURLs.isEmpty ? .contextualMenuForContainer : .contextualMenuForItems,
            targetedURL: targetedURL,
            selectedURLs: selectedURLs
        )
    }

    private func copy(strings: [String], action: String) {
        guard !strings.isEmpty else {
            reportError(title: SRLocalized("无法复制"), message: SRLocalized("Finder 没有提供所选项目。"))
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(strings.joined(separator: "\n"), forType: .string)
        updateStatus(action: action, clearError: true)
    }

    private func relativePath(for url: URL, base: URL?) -> String {
        guard let base else { return url.lastPathComponent }
        let basePath = base.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if path == basePath { return "." }
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func shellEscaped(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func registerMonitoredDirectories() {
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedURLs.removeAll()
        settings = MonitoringConfiguration.loadSettings()

        var stalePaths: [String] = []
        let configuredDirectories = Set(settings.monitoredDirectories.compactMap { directory -> URL? in
            let resolved = MonitoringConfiguration.resolve(directory)
            if resolved.isStale { stalePaths.append(directory.path) }
            if directory.bookmark != nil, resolved.url.startAccessingSecurityScopedResource() {
                securityScopedURLs.append(resolved.url)
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return resolved.url
        })

        // Finder replaces sidebar icons for exact monitored roots. Register a
        // stable system parent for regular folders, but use the mounted volume
        // root itself because Finder monitoring does not cross mount points.
        let registrationDirectories = Set(configuredDirectories.map(registrationRoot(for:)))
        FIFinderSyncController.default().directoryURLs = registrationDirectories
        if !stalePaths.isEmpty {
            updateStatus(error: "部分目录授权已失效，请在设置中重新添加：\(stalePaths.joined(separator: "、"))")
        }
        logger.info(
            "Registered \(registrationDirectories.count) Finder roots for \(configuredDirectories.count) configured locations"
        )
    }

    private func registrationRoot(for url: URL) -> URL {
        let url = url.standardizedFileURL
        let home = MonitoringConfiguration.realHomeDirectory.standardizedFileURL
        if isSameOrDescendant(url, of: home) { return home }

        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true).standardizedFileURL
        if isSameOrDescendant(url, of: volumes) {
            let relativeComponents = url.pathComponents.dropFirst(volumes.pathComponents.count)
            guard let volumeName = relativeComponents.first else { return volumes }
            return volumes.appendingPathComponent(volumeName, isDirectory: true)
        }
        return url
    }

    private func isWithinConfiguredScope(_ context: FinderContext) -> Bool {
        let candidates: [URL]
        switch context.kind {
        case .contextualMenuForItems, .toolbarItemMenu:
            if !context.selectedURLs.isEmpty {
                candidates = context.selectedURLs
            } else if let targetedURL = context.targetedURL {
                candidates = [targetedURL]
            } else {
                return false
            }
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            guard let targetedURL = context.targetedURL else { return false }
            candidates = [targetedURL]
        @unknown default:
            return false
        }

        let configuredRoots = settings.monitoredDirectories.map {
            MonitoringConfiguration.resolve($0).url.standardizedFileURL
        }
        return candidates.allSatisfy { candidate in
            configuredRoots.contains { isSameOrDescendant(candidate, of: $0) }
        }
    }

    private func isSameOrDescendant(_ url: URL, of root: URL) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        guard path != rootPath else { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix)
    }

    @objc private func configurationDidChange(_ notification: Notification) {
        if let receivedSettings = MonitoringConfiguration.settings(from: notification) {
            try? MonitoringConfiguration.save(settings: receivedSettings)
        }
        registerMonitoredDirectories()
    }

    @objc private func mountedVolumesDidChange(_ notification: Notification) {
        registerMonitoredDirectories()
    }

    private func reportError(title: String, message: String) {
        logger.error("\(title, privacy: .public): \(message, privacy: .public)")
        updateStatus(error: "\(title)：\(message)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: SRLocalized("好"))
        alert.runModal()
    }

    private func updateStatus(action: String? = nil, error: String? = nil, clearError: Bool = false) {
        var status = MonitoringConfiguration.loadStatus()
        status.lastHeartbeat = Date()
        status.extensionBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let action { status.lastAction = action }
        if let error {
            status.lastError = error
            status.lastErrorDate = Date()
        } else if clearError {
            status.lastError = nil
            status.lastErrorDate = nil
        }
        MonitoringConfiguration.saveStatus(status)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
