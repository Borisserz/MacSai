import AppKit
import SwiftUI
import MacCleanKit

struct BrowserExtensionsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var extensions: [BrowserExtensionRecord] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var pending: BrowserExtensionRecord?
    @State private var message: String?
    private let client = BrowserExtensionsClient()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("浏览器扩展", "Browser Extensions", "Расширения браузеров"))
                        .font(.system(size: 22, weight: .bold))
                    Text(L10n.tr(
                        "Safari、Chrome、Brave、Edge、Arc 和 Firefox 的扩展列表。已知恶意项会标记出来。Safari 为只读。",
                        "Extensions from Safari, Chrome, Brave, Edge, Arc, and Firefox. Known malicious ones are flagged. Safari is read-only.",
                        "Список расширений Safari, Chrome, Brave, Edge, Arc и Firefox. Известные вредоносные помечаются. Safari доступен только для чтения."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading || isWorking)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView().controlSize(.large)
                        Text(L10n.tr("正在读取扩展…", "Reading extensions…", "Чтение расширений…"))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if extensions.isEmpty {
                    VStack {
                        Spacer()
                        Text(L10n.tr("未找到浏览器扩展", "No browser extensions found", "Расширения браузеров не найдены"))
                            .foregroundStyle(.primary.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(extensions) { ext in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ext.name)
                                        .font(.system(size: 13, weight: .medium))
                                    if ext.isMalicious {
                                        Text(L10n.tr("可疑", "Suspicious", "Подозрительное"))
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.red.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(detail(for: ext))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(actionLabel(for: ext)) {
                                pending = ext
                            }
                            .buttonStyle(.bordered)
                            .disabled(isWorking)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .background {
                if removeBackgroundColors { Color.clear }
                else { Rectangle().fill(.ultraThinMaterial) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task { await reload() }
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading && !isWorking)
        .alert(
            L10n.tr("处理扩展？", "Handle extension?", "Обработать расширение?"),
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            presenting: pending
        ) { ext in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { pending = nil }
            Button(actionLabel(for: ext), role: ext.browser == .safari ? nil : .destructive) {
                let target = ext
                pending = nil
                Task { await remove(target) }
            }
        } message: { ext in
            Text(confirmMessage(for: ext))
        }
        .alert(
            L10n.tr("浏览器扩展", "Browser Extensions", "Расширения браузеров"),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button(L10n.tr("好", "OK"), role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func detail(for ext: BrowserExtensionRecord) -> String {
        let date: String
        if let installedAt = ext.installedAt {
            date = installedAt.formatted(date: .abbreviated, time: .omitted)
        } else {
            date = L10n.tr("未知日期", "Unknown date", "Дата неизвестна")
        }
        return "\(ext.browser.label) · \(date)"
    }

    private func actionLabel(for ext: BrowserExtensionRecord) -> String {
        if ext.browser == .safari {
            return L10n.tr("在设置中打开", "Open in Settings", "Открыть в настройках")
        }
        return L10n.tr("移除", "Remove", "Удалить")
    }

    private func confirmMessage(for ext: BrowserExtensionRecord) -> String {
        if ext.browser == .safari {
            return L10n.tr(
                "Safari 扩展由系统管理，本应用只读。将打开系统设置。",
                "Safari extensions are managed by macOS. This list is read-only and will open System Settings.",
                "Расширения Safari управляются системой. Список только для чтения — откроются Системные настройки."
            )
        }
        return L10n.tr(
            "若浏览器已关闭，将把扩展文件夹移到废纸篓；若正在运行，则打开扩展页面。",
            "If the browser is closed, the extension folder moves to the Trash. If it is running, its extensions page opens instead.",
            "Если браузер закрыт, папка расширения будет перемещена в Корзину. Если он запущен, откроется страница расширений."
        )
    }

    private func reload() async {
        isLoading = true
        extensions = await client.list()
        isLoading = false
    }

    private func remove(_ record: BrowserExtensionRecord) async {
        isWorking = true
        message = await client.applyRemoval(record)
        extensions = await client.list()
        isWorking = false
    }
}
