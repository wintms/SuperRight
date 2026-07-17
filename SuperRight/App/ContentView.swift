import AppKit
import FinderSync
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var monitoredPaths = MonitoringConfiguration.loadPaths()
    @State private var selectedPath: String?
    @State private var configurationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 50, height: 50)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("SuperRight")
                        .font(.title2.bold())
                    Text("为 Finder 右键菜单添加实用功能")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isExtensionEnabled ? "Finder 扩展已启用" : "Finder 扩展尚未启用")
                        .font(.headline)
                    Text(isExtensionEnabled
                         ? "现在可以在 Finder 中右键使用 SuperRight。"
                         : "启用后，右键即可新建文件或从当前目录打开终端。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isExtensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(isExtensionEnabled ? .green : .orange)
            }

            Button {
                FIFinderSyncController.showExtensionManagementInterface()
            } label: {
                Label(isExtensionEnabled ? "管理 Finder 扩展" : "启用 Finder 扩展",
                      systemImage: "puzzlepiece.extension")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单包含")
                    .font(.headline)
                FeatureRow(icon: "doc.badge.plus", text: "新建 TXT、Markdown、Word 和 JSON 文件")
                FeatureRow(icon: "terminal", text: "在 Terminal 或 iTerm2 中打开当前目录")
                FeatureRow(icon: "doc.on.doc", text: "复制当前路径")
            }

            GroupBox {
                VStack(spacing: 10) {
                    List(selection: $selectedPath) {
                        ForEach(monitoredPaths, id: \.self) { path in
                            Label((path as NSString).abbreviatingWithTildeInPath,
                                  systemImage: "folder")
                                .tag(path)
                        }
                    }
                    .frame(height: 170)

                    HStack {
                        Button(action: addDirectories) {
                            Image(systemName: "plus")
                        }
                        .help("添加监控目录")

                        Button(action: removeSelectedDirectory) {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedPath == nil || monitoredPaths.count <= 1)
                        .help("移除所选目录")

                        Spacer()

                        Button("恢复默认") {
                            saveDirectories(MonitoringConfiguration.defaultPaths)
                        }
                    }

                    if let configurationError {
                        Text(configurationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("修改后立即生效，无需重启 Finder。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(4)
            } label: {
                Label("Finder 监控目录", systemImage: "folder.badge.gearshape")
                    .font(.headline)
            }
        }
        .padding(28)
        .frame(width: 520)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                isExtensionEnabled = FIFinderSyncController.isExtensionEnabled
            }
        }
    }

    private func addDirectories() {
        let panel = NSOpenPanel()
        panel.title = "选择要显示 SuperRight 菜单的目录"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        panel.begin { response in
            guard response == .OK else { return }
            let newPaths = panel.urls.map { $0.standardizedFileURL.path(percentEncoded: false) }
            DispatchQueue.main.async {
                saveDirectories(monitoredPaths + newPaths)
            }
        }
    }

    private func removeSelectedDirectory() {
        guard let selectedPath, monitoredPaths.count > 1 else { return }
        saveDirectories(monitoredPaths.filter { $0 != selectedPath })
        self.selectedPath = nil
    }

    private func saveDirectories(_ paths: [String]) {
        do {
            try MonitoringConfiguration.save(paths: paths)
            monitoredPaths = MonitoringConfiguration.loadPaths()
            configurationError = nil
            DistributedNotificationCenter.default().post(
                name: MonitoringConfiguration.didChangeNotification,
                object: nil
            )
        } catch {
            configurationError = "保存失败：\(error.localizedDescription)"
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView()
}
