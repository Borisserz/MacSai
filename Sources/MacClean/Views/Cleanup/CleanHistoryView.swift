import SwiftUI
import MacCleanKit

struct CleanHistoryView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var sessions: [CleanHistorySession] = []
    @State private var pendingRestore: CleanHistorySession?
    @State private var lastSummary: CleanHistoryRestoreSummary?
    @State private var isRestoring = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("清理历史", "Clean History", "История очистки"))
                        .font(.system(size: 22, weight: .bold))
                    Text(L10n.tr(
                        "把最近一次清理整批恢复到原位置。已清空废纸篓或原路径已有文件的项会被跳过。",
                        "Restore a whole clean in one click. Items emptied from Trash or whose original path reappeared are skipped.",
                        "Восстановите всю очистку одним нажатием. Элементы, уже удалённые из Корзины или появившиеся снова по старому пути, будут пропущены."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Button {
                    sessions = CleanHistoryRecorder.load()
                } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Group {
                if sessions.isEmpty {
                    VStack {
                        Spacer()
                        Text(L10n.tr("还没有可恢复的清理记录", "No clean sessions to restore yet", "Пока нет очисток для восстановления"))
                            .foregroundStyle(.primary.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13, weight: .medium))
                                Text(L10n.tr(
                                    "\(session.items.count) 项 · \(FileSizeFormatter.format(session.totalBytes))",
                                    "\(session.items.count) items · \(FileSizeFormatter.format(session.totalBytes))",
                                    "\(session.items.count) \(L10n.russianPlural(session.items.count, one: "элемент", few: "элемента", many: "элементов")) · \(FileSizeFormatter.format(session.totalBytes))"
                                ))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L10n.tr("恢复", "Restore", "Восстановить")) {
                                pendingRestore = session
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRestoring)
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
        .task { sessions = CleanHistoryRecorder.load() }
        .alert(
            L10n.tr("恢复这次清理？", "Restore this clean?", "Восстановить эту очистку?"),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            presenting: pendingRestore
        ) { session in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { pendingRestore = nil }
            Button(L10n.tr("恢复", "Restore", "Восстановить")) {
                let target = session
                pendingRestore = nil
                isRestoring = true
                // File moves and stats stay off the main thread.
                Task {
                    let summary = await Task.detached { CleanHistoryRecorder.restore(target) }.value
                    let reloaded = await Task.detached { CleanHistoryRecorder.load() }.value
                    lastSummary = summary
                    sessions = reloaded
                    isRestoring = false
                }
            }
        } message: { session in
            Text(L10n.tr(
                "将尝试恢复 \(session.items.count) 项。不会覆盖已重新出现在原路径的文件。",
                "Will try to restore \(session.items.count) items. Files that reappeared at the original path are never overwritten.",
                "Будет выполнена попытка восстановить \(session.items.count) \(L10n.russianPlural(session.items.count, one: "элемент", few: "элемента", many: "элементов")). Файлы, снова появившиеся по исходному пути, не перезаписываются."
            ))
        }
        .alert(
            L10n.tr("恢复完成", "Restore finished", "Восстановление завершено"),
            isPresented: Binding(
                get: { lastSummary != nil },
                set: { if !$0 { lastSummary = nil } }
            )
        ) {
            Button(L10n.tr("好", "OK"), role: .cancel) { lastSummary = nil }
        } message: {
            if let lastSummary {
                Text(L10n.tr(
                    "已恢复 \(lastSummary.restored)，废纸篓已清空 \(lastSummary.emptied)，原路径已占用 \(lastSummary.reappeared)，无法恢复 \(lastSummary.failed)。",
                    "Restored \(lastSummary.restored), emptied from Trash \(lastSummary.emptied), original path reappeared \(lastSummary.reappeared), couldn't restore \(lastSummary.failed).",
                    "Восстановлено: \(lastSummary.restored), уже удалено из Корзины: \(lastSummary.emptied), путь занят: \(lastSummary.reappeared), не удалось: \(lastSummary.failed)."
                ))
            }
        }
    }
}
