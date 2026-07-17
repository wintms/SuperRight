import AppKit
import FinderSync
import SwiftUI

@MainActor
final class SettingsStore: NSObject, ObservableObject {
    @Published var settings = MonitoringConfiguration.loadSettings()
    @Published var extensionStatus = MonitoringConfiguration.loadStatus()
    @Published var configurationError: String?
    @Published var selectedDirectoryPath: String?
    @Published var selectedTemplateID: UUID?

    override init() {
        NSWorkspaceBridge.applicationURL = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configurationWasRequested),
            name: MonitoringConfiguration.requestConfigurationNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func reload() {
        settings = MonitoringConfiguration.loadSettings()
        extensionStatus = MonitoringConfiguration.loadStatus()
    }

    func persist() {
        do {
            try MonitoringConfiguration.save(settings: settings)
            configurationError = nil
            DistributedNotificationCenter.default().post(
                name: MonitoringConfiguration.didChangeNotification,
                object: nil,
                userInfo: MonitoringConfiguration.notificationUserInfo(for: settings)
            )
        } catch {
            configurationError = "保存失败：\(error.localizedDescription)"
        }
    }

    func addDirectories(_ urls: [URL]) {
        do {
            let directories = try urls.map(MonitoringConfiguration.makeMonitoredDirectory)
            let newPaths = Set(directories.map(\.path))
            settings.monitoredDirectories.removeAll { newPaths.contains($0.path) }
            settings.monitoredDirectories.append(contentsOf: directories)
            persist()
        } catch {
            configurationError = "无法保存监控目录：\(error.localizedDescription)"
        }
    }

    func replaceDirectory(path: String, with url: URL) {
        do {
            let replacement = try MonitoringConfiguration.makeMonitoredDirectory(for: url)
            settings.monitoredDirectories.removeAll { $0.path == path || $0.path == replacement.path }
            settings.monitoredDirectories.append(replacement)
            selectedDirectoryPath = replacement.path
            persist()
        } catch {
            configurationError = "无法更新监控目录：\(error.localizedDescription)"
        }
    }

    func removeSelectedDirectory() {
        guard let selectedDirectoryPath, settings.monitoredDirectories.count > 1 else { return }
        settings.monitoredDirectories.removeAll { $0.path == selectedDirectoryPath }
        self.selectedDirectoryPath = nil
        persist()
    }

    func moveMenuSection(_ section: MenuSection, offset: Int) {
        guard let index = settings.menuOrder.firstIndex(of: section) else { return }
        let destination = index + offset
        guard settings.menuOrder.indices.contains(destination) else { return }
        settings.menuOrder.swapAt(index, destination)
        persist()
    }

    func toggleMenuSection(_ section: MenuSection, enabled: Bool) {
        if enabled {
            settings.hiddenMenuSections.remove(section)
        } else {
            settings.hiddenMenuSections.insert(section)
        }
        persist()
    }

    func removeSelectedTemplate() {
        guard let selectedTemplateID,
              settings.templates.count > 1,
              let template = settings.templates.first(where: { $0.id == selectedTemplateID }),
              !template.isBuiltIn else { return }
        settings.templates.removeAll { $0.id == selectedTemplateID }
        self.selectedTemplateID = nil
        persist()
    }

    func upsertTemplate(_ template: FileTemplate) {
        if let index = settings.templates.firstIndex(where: { $0.id == template.id }) {
            settings.templates[index] = template
        } else {
            settings.templates.append(template)
        }
        selectedTemplateID = template.id
        persist()
    }

    @objc private func configurationWasRequested(_ notification: Notification) {
        DistributedNotificationCenter.default().post(
            name: MonitoringConfiguration.didChangeNotification,
            object: nil,
            userInfo: MonitoringConfiguration.notificationUserInfo(for: settings)
        )
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SettingsStore()
    @State private var isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var showsOnboarding = false

    var body: some View {
        TabView {
            GeneralSettingsView(store: store, isExtensionEnabled: $isExtensionEnabled)
                .tabItem { Label("概览", systemImage: "house") }

            MenuSettingsView(store: store)
                .tabItem { Label("右键菜单", systemImage: "list.bullet.rectangle") }

            TemplateSettingsView(store: store)
                .tabItem { Label("文件模板", systemImage: "doc.on.doc") }

            DirectorySettingsView(store: store)
                .tabItem { Label("监控目录", systemImage: "folder.badge.gearshape") }

            DiagnosticsView(store: store, isExtensionEnabled: isExtensionEnabled)
                .tabItem { Label("诊断", systemImage: "stethoscope") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(18)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 540, idealHeight: 620)
        .onAppear {
            store.reload()
            showsOnboarding = !store.settings.hasCompletedOnboarding
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
                store.reload()
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView(store: store, isPresented: $showsOnboarding)
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Binding var isExtensionEnabled: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 58, height: 58)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SuperRight").font(.title2.bold())
                        Text("为 Finder 右键菜单添加实用、可定制的操作")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("Finder 扩展") {
                LabeledContent {
                    Label(
                        isExtensionEnabled ? "已启用" : "尚未启用",
                        systemImage: isExtensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(isExtensionEnabled ? .green : .orange)
                } label: {
                    Text("当前状态")
                }

                Button {
                    FIFinderSyncController.showExtensionManagementInterface()
                } label: {
                    Label(isExtensionEnabled ? "管理 Finder 扩展" : "启用 Finder 扩展", systemImage: "puzzlepiece.extension")
                }
            }

            Section("新建文件") {
                Toggle("创建前询问文件名", isOn: binding(\.asksForFileName))
                Toggle("创建后使用默认应用打开", isOn: binding(\.opensCreatedFile))
            }

            if let error = store.configurationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<SuperRightSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: {
                store.settings[keyPath: keyPath] = $0
                store.persist()
            }
        )
    }
}

private struct MenuSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("菜单内容与顺序") {
                Toggle(
                    "将操作收纳在 SuperRight 子菜单中",
                    isOn: Binding(
                        get: { store.settings.usesSubmenu },
                        set: { store.settings.usesSubmenu = $0; store.persist() }
                    )
                )

                ForEach(Array(store.settings.menuOrder.enumerated()), id: \.element.id) { index, section in
                    HStack {
                        Toggle(
                            isOn: Binding(
                                get: { !store.settings.hiddenMenuSections.contains(section) },
                                set: { store.toggleMenuSection(section, enabled: $0) }
                            )
                        ) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        Spacer()
                        Button { store.moveMenuSection(section, offset: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel("上移 \(section.title)")

                        Button { store.moveMenuSection(section, offset: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == store.settings.menuOrder.count - 1)
                        .accessibilityLabel("下移 \(section.title)")
                    }
                }
            }

            Section("默认应用") {
                Picker("终端", selection: terminalBinding) {
                    ForEach(ExternalApplicationCatalog.terminals) { application in
                        Text(application.isInstalled ? application.name : "\(application.name)（未安装）")
                            .tag(application.id)
                    }
                }

                Picker("编辑器", selection: editorBinding) {
                    ForEach(ExternalApplicationCatalog.editors) { application in
                        Text(application.isInstalled ? application.name : "\(application.name)（未安装）")
                            .tag(application.id)
                    }
                }

                Text("未安装的应用会在 Finder 菜单中显示为不可用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var terminalBinding: Binding<String> {
        Binding(
            get: { store.settings.terminalApplicationID },
            set: { store.settings.terminalApplicationID = $0; store.persist() }
        )
    }

    private var editorBinding: Binding<String> {
        Binding(
            get: { store.settings.editorApplicationID },
            set: { store.settings.editorApplicationID = $0; store.persist() }
        )
    }
}

private struct TemplateSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var editingTemplate: FileTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文件模板").font(.title2.bold())
            Text("模板支持 {{filename}}、{{directory}}、{{path}}、{{date}}、{{time}} 和 {{user}} 变量。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(selection: $store.selectedTemplateID) {
                ForEach(store.settings.templates) { template in
                    HStack {
                        Toggle(
                            isOn: Binding(
                                get: { store.settings.templates.first(where: { $0.id == template.id })?.isEnabled ?? false },
                                set: { enabled in
                                    guard let index = store.settings.templates.firstIndex(where: { $0.id == template.id }) else { return }
                                    store.settings.templates[index].isEnabled = enabled
                                    store.persist()
                                }
                            )
                        ) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(template.isEnabled ? "停用 \(template.name)" : "启用 \(template.name)")

                        Image(systemName: template.format == .word ? "doc.richtext" : "doc.text")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(template.name)
                            Text(".\(template.fileExtension)\(template.isBuiltIn ? " · 内置" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(template.id)
                    .contextMenu {
                        Button("编辑") { editingTemplate = template }
                    }
                }
            }

            HStack {
                Button {
                    editingTemplate = FileTemplate(name: "自定义模板", fileExtension: "txt")
                } label: { Label("添加", systemImage: "plus") }

                Button {
                    guard let id = store.selectedTemplateID,
                          let template = store.settings.templates.first(where: { $0.id == id }) else { return }
                    editingTemplate = template
                } label: { Label("编辑", systemImage: "pencil") }
                .disabled(store.selectedTemplateID == nil)

                Button(role: .destructive) {
                    store.removeSelectedTemplate()
                } label: { Label("删除", systemImage: "minus") }
                .disabled(!canDeleteSelection)

                Spacer()

                Button("恢复内置模板") {
                    let custom = store.settings.templates.filter { !$0.isBuiltIn }
                    store.settings.templates = FileTemplate.defaults + custom
                    store.persist()
                }
            }
        }
        .padding(12)
        .sheet(item: $editingTemplate) { template in
            TemplateEditor(template: template) { updated in
                store.upsertTemplate(updated)
            }
        }
    }

    private var canDeleteSelection: Bool {
        guard let id = store.selectedTemplateID,
              let template = store.settings.templates.first(where: { $0.id == id }) else { return false }
        return !template.isBuiltIn && store.settings.templates.count > 1
    }
}

private struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FileTemplate
    let onSave: (FileTemplate) -> Void

    init(template: FileTemplate, onSave: @escaping (FileTemplate) -> Void) {
        _draft = State(initialValue: template)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.isBuiltIn ? "编辑内置模板" : "编辑模板").font(.title2.bold())
            Form {
                TextField("显示名称", text: $draft.name)
                TextField("文件扩展名", text: $draft.fileExtension)
                Picker("格式", selection: $draft.format) {
                    Text("纯文本").tag(TemplateFormat.plainText)
                    Text("Word 文档").tag(TemplateFormat.word)
                }
                .disabled(draft.isBuiltIn)
                Toggle("在 Finder 菜单中显示", isOn: $draft.isEnabled)
            }
            .formStyle(.grouped)

            Text("初始内容")
                .font(.headline)
            TextEditor(text: $draft.content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("保存") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          draft.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560, height: 520)
    }
}

private struct DirectorySettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finder 监控目录").font(.title2.bold())
            Text("只有这些目录及其子目录会显示 SuperRight。非沙盒版本可直接访问这些位置。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(selection: $store.selectedDirectoryPath) {
                ForEach(store.settings.monitoredDirectories) { directory in
                    DirectoryRow(directory: directory)
                        .tag(directory.path)
                }
            }

            HStack {
                Button(action: addDirectories) { Label("添加", systemImage: "plus") }
                Button(action: store.removeSelectedDirectory) { Label("移除", systemImage: "minus") }
                    .disabled(store.selectedDirectoryPath == nil || store.settings.monitoredDirectories.count <= 1)
                Button("重新选择", action: reauthorizeSelected)
                    .disabled(store.selectedDirectoryPath == nil)

                Spacer()

                Button("恢复默认") {
                    store.settings.monitoredDirectories = MonitoringConfiguration.defaultPaths.map {
                        MonitoredDirectory(path: $0, bookmark: nil)
                    }
                    store.persist()
                }
            }

            if let error = store.configurationError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if !MonitoringConfiguration.isAppGroupAvailable {
                Label(
                    "共享容器尚未生效；当前直接使用用户目录中的 Application Support。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text("旧版授权失效的目录可重新选择；不存在或未挂载的目录会被扩展自动忽略。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func addDirectories() {
        let panel = directoryPanel(title: "选择要显示 SuperRight 的目录", allowsMultiple: true)
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in store.addDirectories(panel.urls) }
        }
    }

    private func reauthorizeSelected() {
        guard let path = store.selectedDirectoryPath else { return }
        let panel = directoryPanel(title: "重新选择目录", allowsMultiple: false)
        panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in store.replaceDirectory(path: path, with: url) }
        }
    }

    private func directoryPanel(title: String, allowsMultiple: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultiple
        panel.canCreateDirectories = false
        return panel
    }
}

private struct DirectoryRow: View {
    let directory: MonitoredDirectory

    var body: some View {
        let resolved = MonitoringConfiguration.resolve(directory)
        let exists = FileManager.default.fileExists(atPath: resolved.url.path)
        let needsAuthorization = MonitoringConfiguration.isSandboxed && directory.bookmark == nil
        HStack {
            Image(systemName: exists ? "folder" : "folder.badge.questionmark")
            VStack(alignment: .leading) {
                Text((directory.path as NSString).abbreviatingWithTildeInPath)
                Text(statusText(exists: exists, stale: resolved.isStale))
                    .font(.caption)
                    .foregroundStyle(statusColor(exists: exists, stale: resolved.isStale))
            }
            Spacer()
            if needsAuthorization || resolved.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("需要重新选择")
            }
        }
    }

    private func statusText(exists: Bool, stale: Bool) -> String {
        if !exists { return "目录不存在或尚未挂载" }
        if stale { return "授权已失效" }
        if !MonitoringConfiguration.isSandboxed {
            return FileManager.default.isWritableFile(atPath: directory.path) ? "直接访问，可写" : "直接访问，当前不可写"
        }
        if directory.bookmark == nil { return "尚未授予安全访问权限" }
        return FileManager.default.isWritableFile(atPath: directory.path) ? "已授权，可写" : "已授权，当前不可写"
    }

    private func statusColor(exists: Bool, stale: Bool) -> Color {
        if !exists || stale || (MonitoringConfiguration.isSandboxed && directory.bookmark == nil) { return .orange }
        return .secondary
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var store: SettingsStore
    let isExtensionEnabled: Bool

    var body: some View {
        Form {
            Section("扩展健康状态") {
                LabeledContent("系统设置") {
                    Text(isExtensionEnabled ? "已启用" : "未启用")
                }
                LabeledContent("最近响应") {
                    Text(store.extensionStatus.lastHeartbeat?.formatted(date: .abbreviated, time: .standard) ?? "尚无记录")
                }
                LabeledContent("最近操作") {
                    Text(store.extensionStatus.lastAction ?? "尚无记录")
                }
                LabeledContent("扩展 build") {
                    Text(store.extensionStatus.extensionBuild ?? "未知")
                }
                LabeledContent("共享存储") {
                    Text(MonitoringConfiguration.isAppGroupAvailable ? "App Group 已连接" : "用户目录回退模式")
                }
                LabeledContent("主程序环境") {
                    Text(MonitoringConfiguration.isSandboxed ? "App Sandbox" : "非沙盒（真实用户环境）")
                }
            }

            Section("最近错误") {
                if let error = store.extensionStatus.lastError {
                    Text(error).foregroundStyle(.red)
                    if let date = store.extensionStatus.lastErrorDate {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("没有记录到错误", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                HStack {
                    Button("刷新") { store.reload() }
                    Button("复制诊断信息") { copyDiagnostics() }
                    Button("打开扩展管理") { FIFinderSyncController.showExtensionManagementInterface() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        let report = """
        SuperRight \(version) (build \(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Finder 扩展：\(isExtensionEnabled ? "已启用" : "未启用")
        Finder 扩展 build：\(store.extensionStatus.extensionBuild ?? "未知")
        主程序环境：\(MonitoringConfiguration.isSandboxed ? "App Sandbox" : "非沙盒（真实用户环境）")
        监控目录：\(store.settings.monitoredDirectories.count)
        最近响应：\(store.extensionStatus.lastHeartbeat?.description ?? "无")
        最近操作：\(store.extensionStatus.lastAction ?? "无")
        最近错误：\(store.extensionStatus.lastError ?? "无")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)
            Text("SuperRight").font(.largeTitle.bold())
            Text("版本 \(version)").foregroundStyle(.secondary)
            Text("一个轻量、原生、可定制的 Finder 右键菜单扩展。")
                .multilineTextAlignment(.center)
            Divider().frame(width: 360)
            Text("更新通道可在完成正式签名和发布地址配置后接入。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Copyright © 2026")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("欢迎使用 SuperRight").font(.title.bold())
                    Text("两步完成首次设置")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("1. 启用 Finder 扩展") {
                HStack {
                    Text("在系统设置中允许 SuperRight 出现在 Finder。")
                    Spacer()
                    Button("打开系统设置") {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                }
                .padding(8)
            }

            GroupBox("2. 选择常用目录") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("为了保护文件安全，请明确选择允许 SuperRight 创建文件的目录。")
                    Button("选择目录…") { selectDirectories() }
                }
                .padding(8)
            }

            HStack {
                Spacer()
                Button("完成") {
                    store.settings.hasCompletedOnboarding = true
                    store.persist()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 600)
    }

    private func selectDirectories() {
        let panel = NSOpenPanel()
        panel.title = "选择 SuperRight 可以访问的目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in store.addDirectories(panel.urls) }
        }
    }
}

#Preview {
    ContentView()
}
