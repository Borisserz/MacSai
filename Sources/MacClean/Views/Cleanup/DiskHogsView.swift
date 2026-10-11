import SwiftUI
import MacCleanKit

struct DiskHogsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var dockerRows: [DockerDiskRow] = []
    @State private var selectedDocker: Set<DockerDiskCategory> = DockerPrune.defaultSelection
    @State private var devices: [SimulatorDevice] = []
    @State private var runtimes: [SimulatorRuntime] = []
    @State private var selectedSim: Set<String> = SimulatorInventory.defaultSelection
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var statusMessage: String?
    private let client = DiskHogsClient()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("开发者磁盘占用", "Disk Hogs", "Дисковые «пожиратели»"))
                        .font(.system(size: 22, weight: .bold))
                    Text(L10n.tr(
                        "Docker 镜像/容器/卷/构建缓存，以及不可用的模拟器和旧运行时。仅在已安装时显示，且不会自动勾选。",
                        "Docker images, containers, volumes, and build cache, plus unavailable simulators and old runtimes. Only appears when installed, and nothing is auto-selected.",
                        "Образы, контейнеры, тома и кэш сборки Docker, а также недоступные симуляторы и старые рантаймы. Появляется только если инструменты установлены; ничего не выбирается заранее."
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
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !dockerRows.isEmpty {
                            Section(L10n.tr("Docker", "Docker", "Docker")) {
                                ForEach(dockerRows) { row in
                                    Toggle(isOn: Binding(
                                        get: { selectedDocker.contains(row.category) },
                                        set: { on in
                                            if on { selectedDocker.insert(row.category) }
                                            else { selectedDocker.remove(row.category) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.category.label)
                                                .font(.system(size: 13, weight: .medium))
                                            Text(L10n.tr(
                                                "大小 \(row.size) · 可回收 \(row.reclaimable)",
                                                "Size \(row.size) · Reclaimable \(row.reclaimable)",
                                                "Размер \(row.size) · Можно освободить \(row.reclaimable)"
                                            ))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Button(L10n.tr("清理所选 Docker 项", "Prune Selected Docker", "Очистить выбранное в Docker")) {
                                    Task { await pruneDocker() }
                                }
                                .disabled(selectedDocker.isEmpty || isWorking)
                            }
                        }

                        if !devices.isEmpty || !runtimes.isEmpty {
                            Section(L10n.tr("Xcode 模拟器", "Xcode Simulators", "Симуляторы Xcode")) {
                                ForEach(devices) { device in
                                    Toggle(isOn: Binding(
                                        get: { selectedSim.contains(device.udid) },
                                        set: { on in
                                            if on { selectedSim.insert(device.udid) }
                                            else { selectedSim.remove(device.udid) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                            Text(L10n.tr("不可用 · \(device.runtime)", "Unavailable · \(device.runtime)", "Недоступен · \(device.runtime)"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                ForEach(runtimes) { runtime in
                                    Toggle(isOn: Binding(
                                        get: { selectedSim.contains(runtime.identifier) },
                                        set: { on in
                                            if on { selectedSim.insert(runtime.identifier) }
                                            else { selectedSim.remove(runtime.identifier) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(runtime.name)
                                            Text(runtime.isAvailable
                                                 ? L10n.tr("旧运行时", "Older runtime", "Старый рантайм")
                                                 : L10n.tr("不可用运行时", "Unavailable runtime", "Недоступный рантайм"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Button(L10n.tr("删除所选模拟器", "Delete Selected Simulators", "Удалить выбранные симуляторы")) {
                                    Task { await deleteSims() }
                                }
                                .disabled(selectedSim.isEmpty || isWorking)
                            }
                        }

                        if dockerRows.isEmpty && devices.isEmpty && runtimes.isEmpty {
                            Text(L10n.tr(
                                "未检测到 Docker 或 Xcode 模拟器。",
                                "Neither Docker nor Xcode simulators were detected.",
                                "Не найдены ни Docker, ни симуляторы Xcode."
                            ))
                            .foregroundStyle(.secondary)
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
    }

    private func reload() async {
        isLoading = true
        async let d = client.dockerRows()
        async let dev = client.unavailableDevices()
        async let run = client.oldRuntimes()
        dockerRows = await d
        devices = await dev
        runtimes = await run
        selectedDocker = DockerPrune.defaultSelection
        selectedSim = SimulatorInventory.defaultSelection
        isLoading = false
    }

    private func pruneDocker() async {
        isWorking = true
        statusMessage = await client.pruneDocker(selection: selectedDocker)
        selectedDocker = []
        dockerRows = await client.dockerRows()
        isWorking = false
    }

    private func deleteSims() async {
        isWorking = true
        let deviceIDs = Set(devices.map(\.udid))
        for id in selectedSim {
            if deviceIDs.contains(id) {
                await client.deleteSimulator(udid: id)
            } else {
                await client.deleteRuntime(identifier: id)
            }
        }
        selectedSim = []
        devices = await client.unavailableDevices()
        runtimes = await client.oldRuntimes()
        statusMessage = L10n.tr("已删除所选模拟器项", "Deleted selected simulator items", "Выбранные симуляторы удалены")
        isWorking = false
    }
}
