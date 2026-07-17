import AppKit
import FinderSync
import SwiftUI

@main
struct SuperRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("管理 Finder 扩展") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(FileCreationRequestHandler.handle)
    }
}

@MainActor
private enum FileCreationRequestHandler {
    private static let fileCreator = FileCreator()

    static func handle(_ url: URL) {
        guard url.scheme == "superright",
              url.host == "create",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "template" })?.value,
              let templateID = UUID(uuidString: idValue),
              let directoryValue = components.queryItems?.first(where: { $0.name == "directory" })?.value else {
            showError(SRLocalized("无法新建文件"), SRLocalized("创建请求无效。"))
            return
        }

        let settings = MonitoringConfiguration.loadSettings()
        let directory = URL(fileURLWithPath: directoryValue, isDirectory: true).standardizedFileURL
        guard let template = settings.templates.first(where: { $0.id == templateID && $0.isEnabled }),
              isAllowed(directory, settings: settings) else {
            showError(SRLocalized("无法新建文件"), SRLocalized("目标目录不在 SuperRight 的监控范围内。"))
            return
        }

        let presentation = NamingPromptPresentation.begin()
        defer { presentation.finish() }
        let suggestedName = fileCreator.suggestedBaseName(for: template)
        guard let requestedName = requestFileName(
            suggestedName: suggestedName,
            fileExtension: template.fileExtension
        ) else { return }

        do {
            let createdURL = try fileCreator.create(
                template: template,
                requestedName: requestedName,
                in: directory
            )
            updateStatus(action: "已创建 \(createdURL.lastPathComponent)", error: nil)
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            if settings.opensCreatedFile {
                NSWorkspace.shared.open(createdURL)
            }
        } catch {
            updateStatus(action: nil, error: "无法新建文件：\(error.localizedDescription)")
            showError(SRLocalized("无法新建文件"), error.localizedDescription)
        }
    }

    private static func isAllowed(_ directory: URL, settings: SuperRightSettings) -> Bool {
        let path = directory.path(percentEncoded: false)
        return settings.monitoredDirectories.contains { monitoredDirectory in
            let root = MonitoringConfiguration.resolve(monitoredDirectory).url.standardizedFileURL
                .path(percentEncoded: false)
            guard path != root else { return true }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            return path.hasPrefix(prefix)
        }
    }

    private static func requestFileName(suggestedName: String, fileExtension: String) -> String? {
        let alert = NSAlert()
        alert.messageText = String(format: SRLocalized("新建 .%@ 文件"), fileExtension)
        alert.informativeText = SRLocalized("输入文件名。若文件已存在，SuperRight 会自动添加编号。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: SRLocalized("创建"))
        alert.addButton(withTitle: SRLocalized("取消"))

        let field = NSTextField(string: suggestedName)
        field.placeholderString = suggestedName
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = .floating
        alert.window.center()

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func updateStatus(action: String?, error: String?) {
        var status = MonitoringConfiguration.loadStatus()
        status.lastHeartbeat = Date()
        if let action {
            status.lastAction = action
            status.lastError = nil
            status.lastErrorDate = nil
        }
        if let error {
            status.lastError = error
            status.lastErrorDate = Date()
        }
        MonitoringConfiguration.saveStatus(status)
    }

    private static func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: SRLocalized("好"))
        alert.window.level = .floating
        alert.runModal()
    }

    @MainActor
    private struct NamingPromptPresentation {
        let shouldReturnToPreviousApplication: Bool

        static func begin() -> Self {
            let shouldReturn = !NSApp.isActive
            if shouldReturn {
                // A URL-triggered creation request should show only the compact
                // naming prompt, not bring the SwiftUI settings window forward.
                NSApp.windows.filter(\.isVisible).forEach { $0.orderOut(nil) }
            }
            NSApp.activate(ignoringOtherApps: true)
            return Self(shouldReturnToPreviousApplication: shouldReturn)
        }

        func finish() {
            guard shouldReturnToPreviousApplication else { return }
            NSApp.hide(nil)
        }
    }
}
