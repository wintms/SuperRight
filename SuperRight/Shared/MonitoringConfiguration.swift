import Foundation
import Darwin

func SRLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum MenuSection: String, Codable, CaseIterable, Identifiable {
    case newFile
    case terminal
    case editor
    case copyPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newFile: SRLocalized("新建文件")
        case .terminal: SRLocalized("在终端中打开")
        case .editor: SRLocalized("在编辑器中打开")
        case .copyPath: SRLocalized("复制路径")
        }
    }

    var systemImage: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .terminal: "terminal"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .copyPath: "doc.on.doc"
        }
    }
}

enum TemplateFormat: String, Codable, CaseIterable {
    case plainText
    case word
}

struct FileTemplate: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var fileExtension: String
    var content: String
    var format: TemplateFormat
    var isBuiltIn: Bool
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        fileExtension: String,
        content: String = "",
        format: TemplateFormat = .plainText,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.fileExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.content = content
        self.format = format
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }

    static let defaults: [FileTemplate] = [
        FileTemplate(
            id: UUID(uuidString: "B7E2045E-C995-4B18-A3F6-C78F88AC27E0")!,
            name: SRLocalized("文本文档"),
            fileExtension: "txt",
            isBuiltIn: true
        ),
        FileTemplate(
            id: UUID(uuidString: "77951C8D-C443-49A0-987D-5CE2BCBA0377")!,
            name: SRLocalized("Markdown"),
            fileExtension: "md",
            content: "# {{filename}}\n",
            isBuiltIn: true
        ),
        FileTemplate(
            id: UUID(uuidString: "3BDACFB3-0AB1-4A6D-BB28-8F8FE80703BA")!,
            name: SRLocalized("Word 文档"),
            fileExtension: "docx",
            format: .word,
            isBuiltIn: true
        ),
        FileTemplate(
            id: UUID(uuidString: "B0C4C9E4-58A6-4FB5-AE2C-A6B97B717127")!,
            name: SRLocalized("JSON 文件"),
            fileExtension: "json",
            content: "{\n  \n}\n",
            isBuiltIn: true
        )
    ]
}

struct MonitoredDirectory: Codable, Hashable, Identifiable {
    var path: String
    var bookmark: Data?

    var id: String { path }
}

struct ExternalApplication: Hashable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifiers: [String]

    var bundleIdentifier: String? {
        bundleIdentifiers.first {
            NSWorkspaceBridge.applicationURL($0) != nil
        } ?? bundleIdentifiers.first
    }

    var isInstalled: Bool {
        bundleIdentifiers.contains {
            NSWorkspaceBridge.applicationURL($0) != nil
        }
    }
}

/// Keeps the shared model Foundation-only while allowing the app and extension
/// to provide an AppKit-backed application lookup.
enum NSWorkspaceBridge {
    static var applicationURL: (String) -> URL? = { _ in nil }
}

enum ExternalApplicationCatalog {
    static let terminals: [ExternalApplication] = [
        ExternalApplication(id: "terminal", name: "Terminal", bundleIdentifiers: ["com.apple.Terminal"]),
        ExternalApplication(id: "iterm", name: "iTerm2", bundleIdentifiers: ["com.googlecode.iterm2"]),
        ExternalApplication(id: "warp", name: "Warp", bundleIdentifiers: ["dev.warp.Warp-Stable"]),
        ExternalApplication(id: "ghostty", name: "Ghostty", bundleIdentifiers: ["com.mitchellh.ghostty"]),
        ExternalApplication(id: "wezterm", name: "WezTerm", bundleIdentifiers: ["com.github.wez.wezterm"]),
        ExternalApplication(id: "alacritty", name: "Alacritty", bundleIdentifiers: ["org.alacritty"]),
        ExternalApplication(id: "kitty", name: "kitty", bundleIdentifiers: ["net.kovidgoyal.kitty"])
    ]

    static let editors: [ExternalApplication] = [
        ExternalApplication(id: "vscode", name: "Visual Studio Code", bundleIdentifiers: ["com.microsoft.VSCode"]),
        ExternalApplication(id: "cursor", name: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]),
        ExternalApplication(id: "zed", name: "Zed", bundleIdentifiers: ["dev.zed.Zed"]),
        ExternalApplication(id: "sublime", name: "Sublime Text", bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"]),
        ExternalApplication(id: "xcode", name: "Xcode", bundleIdentifiers: ["com.apple.dt.Xcode", "com.apple.dt.Xcode-beta"]),
        ExternalApplication(id: "nova", name: "Nova", bundleIdentifiers: ["com.panic.Nova"]),
        ExternalApplication(id: "fleet", name: "Fleet", bundleIdentifiers: ["com.jetbrains.fleet"])
    ]

    static func terminal(id: String) -> ExternalApplication {
        terminals.first(where: { $0.id == id }) ?? terminals[0]
    }

    static func editor(id: String) -> ExternalApplication {
        editors.first(where: { $0.id == id }) ?? editors[0]
    }
}

struct SuperRightSettings: Codable, Equatable {
    var monitoredDirectories: [MonitoredDirectory]
    var menuOrder: [MenuSection]
    var hiddenMenuSections: Set<MenuSection>
    var terminalApplicationID: String
    var editorApplicationID: String
    var usesSubmenu: Bool
    var asksForFileName: Bool
    var opensCreatedFile: Bool
    var templates: [FileTemplate]
    var hasCompletedOnboarding: Bool

    static var defaults: SuperRightSettings {
        SuperRightSettings(
            monitoredDirectories: MonitoringConfiguration.defaultPaths.map {
                MonitoredDirectory(path: $0, bookmark: nil)
            },
            menuOrder: MenuSection.allCases,
            hiddenMenuSections: [],
            terminalApplicationID: "terminal",
            editorApplicationID: "vscode",
            usesSubmenu: true,
            asksForFileName: true,
            opensCreatedFile: false,
            templates: FileTemplate.defaults,
            hasCompletedOnboarding: false
        )
    }

    init(
        monitoredDirectories: [MonitoredDirectory],
        menuOrder: [MenuSection],
        hiddenMenuSections: Set<MenuSection>,
        terminalApplicationID: String,
        editorApplicationID: String,
        usesSubmenu: Bool,
        asksForFileName: Bool,
        opensCreatedFile: Bool,
        templates: [FileTemplate],
        hasCompletedOnboarding: Bool
    ) {
        self.monitoredDirectories = monitoredDirectories
        self.menuOrder = menuOrder
        self.hiddenMenuSections = hiddenMenuSections
        self.terminalApplicationID = terminalApplicationID
        self.editorApplicationID = editorApplicationID
        self.usesSubmenu = usesSubmenu
        self.asksForFileName = asksForFileName
        self.opensCreatedFile = opensCreatedFile
        self.templates = templates
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoredDirectories = try container.decodeIfPresent([MonitoredDirectory].self, forKey: .monitoredDirectories)
            ?? defaults.monitoredDirectories
        menuOrder = try container.decodeIfPresent([MenuSection].self, forKey: .menuOrder)
            ?? defaults.menuOrder
        hiddenMenuSections = try container.decodeIfPresent(Set<MenuSection>.self, forKey: .hiddenMenuSections)
            ?? defaults.hiddenMenuSections
        terminalApplicationID = try container.decodeIfPresent(String.self, forKey: .terminalApplicationID)
            ?? defaults.terminalApplicationID
        editorApplicationID = try container.decodeIfPresent(String.self, forKey: .editorApplicationID)
            ?? defaults.editorApplicationID
        usesSubmenu = try container.decodeIfPresent(Bool.self, forKey: .usesSubmenu)
            ?? defaults.usesSubmenu
        asksForFileName = try container.decodeIfPresent(Bool.self, forKey: .asksForFileName)
            ?? defaults.asksForFileName
        opensCreatedFile = try container.decodeIfPresent(Bool.self, forKey: .opensCreatedFile)
            ?? defaults.opensCreatedFile
        templates = try container.decodeIfPresent([FileTemplate].self, forKey: .templates)
            ?? defaults.templates
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? defaults.hasCompletedOnboarding

        let knownSections = Set(menuOrder)
        menuOrder.append(contentsOf: MenuSection.allCases.filter { !knownSections.contains($0) })
        if templates.isEmpty { templates = FileTemplate.defaults }
    }
}

struct ExtensionStatus: Codable {
    var lastHeartbeat: Date?
    var lastAction: String?
    var lastError: String?
    var lastErrorDate: Date?
    var extensionBuild: String?

    static let empty = ExtensionStatus()
}

enum MonitoringConfiguration {
    static let didChangeNotification = Notification.Name("SuperRightConfigurationDidChange")
    static let requestConfigurationNotification = Notification.Name("SuperRightConfigurationRequested")
    static let appGroupIdentifier = "group.com.example.SuperRight"
    private static let notificationSettingsKey = "settings"

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var isAppGroupAvailable: Bool {
        writableAppGroupSupportDirectory != nil
    }

    static var defaultPaths: [String] {
        [realHomeDirectory.path, "/Volumes"]
    }

    static func loadSettings() -> SuperRightSettings {
        for url in configurationReadURLs {
            if let data = try? Data(contentsOf: url),
               let settings = try? JSONDecoder().decode(SuperRightSettings.self, from: data) {
                let settings = normalized(settings)
                if url != configurationURL {
                    try? save(settings: settings)
                }
                return settings
            }
        }

        if let legacy = loadLegacyPaths() {
            var settings = SuperRightSettings.defaults
            settings.monitoredDirectories = legacy.map { MonitoredDirectory(path: $0, bookmark: nil) }
            return normalized(settings)
        }

        return SuperRightSettings.defaults
    }

    static func save(settings: SuperRightSettings) throws {
        let settings = normalized(settings)
        guard !settings.monitoredDirectories.isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(settings)
        var lastError: Error?
        var didWrite = false

        for url in configurationWriteURLs {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                didWrite = true
            } catch {
                lastError = error
            }
        }

        if !didWrite {
            throw lastError ?? CocoaError(.fileWriteUnknown)
        }
    }

    static func notificationUserInfo(for settings: SuperRightSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(normalized(settings)) else { return nil }
        return [notificationSettingsKey: data]
    }

    static func settings(from notification: Notification) -> SuperRightSettings? {
        guard let data = notification.userInfo?[notificationSettingsKey] as? Data,
              let settings = try? JSONDecoder().decode(SuperRightSettings.self, from: data) else {
            return nil
        }
        return normalized(settings)
    }

    static func makeMonitoredDirectory(for url: URL) throws -> MonitoredDirectory {
        let standardizedURL = url.standardizedFileURL
        guard isSandboxed else {
            return MonitoredDirectory(
                path: standardizedURL.path(percentEncoded: false),
                bookmark: nil
            )
        }
        let bookmark = try standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.isDirectoryKey, .isWritableKey],
            relativeTo: nil
        )
        return MonitoredDirectory(path: standardizedURL.path(percentEncoded: false), bookmark: bookmark)
    }

    static func resolve(_ directory: MonitoredDirectory) -> (url: URL, isStale: Bool) {
        guard let bookmark = directory.bookmark else {
            return (URL(fileURLWithPath: directory.path, isDirectory: true), false)
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (url.standardizedFileURL, isStale)
        }
        return (URL(fileURLWithPath: directory.path, isDirectory: true), true)
    }

    static func loadStatus() -> ExtensionStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return statusReadURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ExtensionStatus.self, from: data)
        }.max { lhs, rhs in
            (lhs.lastHeartbeat ?? .distantPast) < (rhs.lastHeartbeat ?? .distantPast)
        } ?? .empty
    }

    static func saveStatus(_ status: ExtensionStatus) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(status) else { return }

        for url in statusWriteURLs {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                // Diagnostics must never prevent the Finder action itself.
            }
        }
    }

    private static func normalized(_ value: SuperRightSettings) -> SuperRightSettings {
        var settings = value
        var seen = Set<String>()
        settings.monitoredDirectories = settings.monitoredDirectories.compactMap { directory in
            let path = URL(fileURLWithPath: directory.path, isDirectory: true)
                .standardizedFileURL.path(percentEncoded: false)
            guard seen.insert(path).inserted else { return nil }
            return MonitoredDirectory(path: path, bookmark: directory.bookmark)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let requestedOrder = settings.menuOrder.filter { MenuSection.allCases.contains($0) }
        let knownSections = Set(requestedOrder)
        settings.menuOrder = requestedOrder + MenuSection.allCases.filter { !knownSections.contains($0) }

        settings.templates = settings.templates.map { template in
            var template = template
            template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.fileExtension = template.fileExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return template
        }.filter { !$0.name.isEmpty && !$0.fileExtension.isEmpty }
        if settings.templates.isEmpty { settings.templates = FileTemplate.defaults }
        return settings
    }

    private static func loadLegacyPaths() -> [String]? {
        struct LegacyConfiguration: Codable { let paths: [String] }
        let legacyURL = realHomeDirectory
            .appendingPathComponent("Library/Application Support/SuperRight", isDirectory: true)
            .appendingPathComponent("monitoring.json", isDirectory: false)
        guard legacyURL != configurationURL,
              let data = try? Data(contentsOf: legacyURL),
              let configuration = try? JSONDecoder().decode(LegacyConfiguration.self, from: data),
              !configuration.paths.isEmpty else { return nil }
        return configuration.paths
    }

    private static var configurationURL: URL {
        sharedSupportDirectory.appendingPathComponent("configuration.json", isDirectory: false)
    }

    private static var configurationReadURLs: [URL] {
        uniqueURLs([
            configurationURL,
            fallbackSupportDirectory.appendingPathComponent("configuration.json", isDirectory: false)
        ])
    }

    private static var configurationWriteURLs: [URL] {
        uniqueURLs([
            writableAppGroupSupportDirectory?
                .appendingPathComponent("configuration.json", isDirectory: false),
            fallbackSupportDirectory
                .appendingPathComponent("configuration.json", isDirectory: false)
        ].compactMap { $0 })
    }

    private static var statusURL: URL {
        sharedSupportDirectory.appendingPathComponent("extension-status.json", isDirectory: false)
    }

    private static var statusReadURLs: [URL] {
        uniqueURLs([
            statusURL,
            fallbackSupportDirectory.appendingPathComponent("extension-status.json", isDirectory: false)
        ])
    }

    private static var statusWriteURLs: [URL] {
        uniqueURLs([
            writableAppGroupSupportDirectory?
                .appendingPathComponent("extension-status.json", isDirectory: false),
            fallbackSupportDirectory
                .appendingPathComponent("extension-status.json", isDirectory: false)
        ].compactMap { $0 })
    }

    private static var sharedSupportDirectory: URL {
        writableAppGroupSupportDirectory ?? fallbackSupportDirectory
    }

    private static var fallbackSupportDirectory: URL {
        // Direct-distribution builds run outside App Sandbox, so this is the
        // real user's Application Support directory shared by both processes.
        realHomeDirectory
            .appendingPathComponent("Library/Application Support/SuperRight", isDirectory: true)
    }

    private static var writableAppGroupSupportDirectory: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        let supportURL = containerURL
            .appendingPathComponent("Library/Application Support/SuperRight", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: supportURL,
                withIntermediateDirectories: true
            )
            // POSIX permission checks do not account for sandbox policy. A real
            // atomic write proves that this process can use the group container.
            let probeURL = supportURL.appendingPathComponent(
                ".write-probe-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                isDirectory: false
            )
            defer { try? FileManager.default.removeItem(at: probeURL) }
            try Data().write(to: probeURL, options: .atomic)
            return supportURL
        } catch {
            return nil
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static var realHomeDirectory: URL {
        if let passwordEntry = getpwuid(getuid()),
           let homePath = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
