import AppKit
import SwiftUI
import MacCleanKit
import UniformTypeIdentifiers

struct ProjectJunkView: View {
    @Environment(AppState.self) private var appState
    @State private var rootURL: URL?
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?
    @State private var showPicker = false

    private let scanner = ProjectJunkScanner()

    private var subtitle: String {
        if let rootURL {
            return L10n.tr(
                "扫描范围：\(rootURL.path(percentEncoded: false))。不会自动勾选。",
                "Scanning \(rootURL.path(percentEncoded: false)). Nothing is auto-selected.",
                "Область: \(rootURL.path(percentEncoded: false)). Ничего не выбирается заранее."
            )
        }
        return L10n.tr(
            "选择项目文件夹（例如 ~/Code），查找 node_modules、venv、target、build 等可重建目录。",
            "Choose a projects folder (e.g. ~/Code) to find regenerable folders like node_modules, venvs, target, and build.",
            "Выберите папку с проектами (например ~/Code), чтобы найти восстанавливаемые каталоги вроде node_modules, venv, target и build."
        )
    }

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("项目垃圾", "Project Junk", "Мусор проектов"),
            subtitle: subtitle,
            theme: .cleanup,
            emptyMessage: rootURL == nil
                ? L10n.tr("点击扫描以选择项目文件夹", "Click Scan to choose a projects folder", "Нажмите «Сканировать», чтобы выбрать папку")
                : L10n.tr("未找到项目垃圾", "No project junk found", "Мусор проектов не найден"),
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: beginScan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset
        )
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                rootURL = url
                runScan(root: url)
            }
        }
    }

    private func beginScan() {
        if rootURL == nil {
            showPicker = true
            return
        }
        runScan(root: rootURL!)
    }

    private func runScan(root: URL) {
        isScanning = true
        scanComplete = false
        scanProgress = 0.2
        scanPhase = L10n.tr("正在扫描项目…", "Scanning projects…", "Сканирование проектов…")
        results = []
        selectedItems = []
        Task {
            let items = await Task.detached {
                ProjectJunkScanner().scan(root: root)
            }.value
            results = scanner.asScanResults(items)
            selectedItems = []
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let preCleanSelectedCount = selectedItems.count
        cleaning = CleaningEngine.Progress(
            totalItems: preCleanSelectedCount,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { progress in
                    Task { @MainActor in cleaning = progress }
                }
            )
            cleaning = nil
            completion = CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            )
        }
    }

    private func reset() {
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
