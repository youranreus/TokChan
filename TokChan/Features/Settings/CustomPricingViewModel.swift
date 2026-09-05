import Foundation

enum CustomPricingFileState: Equatable {
    case idle
    case loading
    case loaded(CustomPricingSnapshot)
    case failed(String)
}

enum CustomPricingOperation: Equatable {
    case idle
    case loading
    case saving
    case checking
    case succeeded(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loading, .saving, .checking: return true
        default: return false
        }
    }
}

enum CustomPricingEditorMode: Equatable {
    case add
    case edit(originalModelID: String)
}

@MainActor
final class CustomPricingViewModel: ObservableObject {
    @Published private(set) var fileState: CustomPricingFileState = .idle
    @Published private(set) var operation: CustomPricingOperation = .idle
    @Published var selectedModelID: String?
    @Published var draft = CustomPricingDraft()
    @Published private(set) var editorMode: CustomPricingEditorMode?
    @Published private(set) var editorError: String?
    @Published private(set) var report: PricingDiagnosticReport?
    @Published private(set) var isReportStale = false

    private let cli: CustomPricingCLIService
    private let store: CustomPricingFileStoring
    private let preferencesStore: PreferencesStoring
    private let npxLocator: NpxLocating
    private var generation = 0
    private var snapshotContext: TokscaleCommandContext?
    private var reportContext: TokscaleCommandContext?

    init(
        cli: CustomPricingCLIService,
        store: CustomPricingFileStoring,
        preferencesStore: PreferencesStoring,
        npxLocator: NpxLocating
    ) {
        self.cli = cli
        self.store = store
        self.preferencesStore = preferencesStore
        self.npxLocator = npxLocator
    }

    var snapshot: CustomPricingSnapshot? {
        guard case let .loaded(snapshot) = fileState else { return nil }
        return snapshot
    }

    var entries: [CustomPricingEntry] { snapshot?.entries ?? [] }

    var selectedEntry: CustomPricingEntry? {
        guard let selectedModelID else { return nil }
        return entries.first { $0.modelID == selectedModelID }
    }

    var canModify: Bool { snapshot != nil && !operation.isBusy }
    var isEditorPresented: Bool { editorMode != nil }

    func load() async {
        guard !operation.isBusy else { return }
        generation += 1
        let requestGeneration = generation
        let previous = snapshot
        fileState = .loading
        operation = .loading
        do {
            let context = try commandContext()
            let url = try await cli.customPricingFileURL(context: context)
            guard generation == requestGeneration else { return }
            guard try commandContext() == context else {
                throw CustomPricingError.staleConfiguration
            }
            let loaded = try store.load(from: url)
            guard generation == requestGeneration else { return }
            guard try commandContext() == context else {
                throw CustomPricingError.staleConfiguration
            }
            applyLoadedSnapshot(loaded, previous: previous)
            snapshotContext = context
            if report != nil, reportContext != context { isReportStale = true }
            operation = .idle
        } catch {
            guard generation == requestGeneration else { return }
            snapshotContext = nil
            fileState = .failed(Self.message(for: error))
            if report != nil { isReportStale = true }
            operation = .failed(Self.message(for: error))
        }
    }

    func reload() async {
        await load()
    }

    func beginAdd(prefilling modelID: String = "") {
        guard canModify else { return }
        draft = CustomPricingDraft()
        draft.modelID = modelID
        editorError = nil
        editorMode = .add
    }

    func beginEdit(_ entry: CustomPricingEntry) {
        guard canModify else { return }
        draft = CustomPricingDraft(entry: entry)
        editorError = nil
        editorMode = .edit(originalModelID: entry.modelID)
    }

    func cancelEditing() {
        editorMode = nil
        editorError = nil
    }

    func saveDraft() {
        guard let mode = editorMode, let snapshot, !operation.isBusy else { return }
        operation = .saving
        editorError = nil
        do {
            guard try commandContext() == snapshotContext else {
                throw CustomPricingError.staleConfiguration
            }
            let originalModelID: String?
            if case let .edit(value) = mode { originalModelID = value }
            else { originalModelID = nil }
            let validated = try CustomPricingValidation.validate(
                draft,
                entries: snapshot.entries,
                editing: originalModelID
            )
            let updated: CustomPricingSnapshot
            switch mode {
            case .add:
                updated = try store.add(validated, to: snapshot)
            case let .edit(originalModelID):
                updated = try store.update(
                    originalModelID: originalModelID,
                    with: validated,
                    in: snapshot
                )
            }
            fileState = .loaded(updated)
            selectedModelID = validated.modelID
            editorMode = nil
            isReportStale = report != nil
            operation = .succeeded("价格已保存。请重新检查缺失价格。")
            generation += 1
        } catch {
            let message = Self.message(for: error)
            editorError = message
            operation = .failed(message)
        }
    }

    func deleteSelected() {
        guard let snapshot, let selectedModelID, !operation.isBusy else { return }
        operation = .saving
        do {
            guard try commandContext() == snapshotContext else {
                throw CustomPricingError.staleConfiguration
            }
            let updated = try store.delete(modelID: selectedModelID, from: snapshot)
            fileState = .loaded(updated)
            self.selectedModelID = nil
            isReportStale = report != nil
            operation = .succeeded("价格条目已删除。请重新检查缺失价格。")
            generation += 1
        } catch {
            operation = .failed(Self.message(for: error))
        }
    }

    func checkMissingPricing() async {
        guard let capturedSnapshot = snapshot, !operation.isBusy else { return }
        generation += 1
        let requestGeneration = generation
        operation = .checking
        if report != nil { isReportStale = true }
        do {
            let context = try commandContext()
            guard context == snapshotContext else {
                throw CustomPricingError.staleConfiguration
            }
            let result = try await cli.checkCustomPricing(context: context)
            guard generation == requestGeneration else { return }
            let contextStillMatches = (try? commandContext()) == context
            let fileChanged = (try? store.hasChanged(capturedSnapshot)) ?? true
            report = result
            reportContext = context
            isReportStale = !contextStillMatches || fileChanged
            operation = .idle
        } catch {
            guard generation == requestGeneration else { return }
            operation = .failed(Self.message(for: error))
        }
    }

    func hasMatchingCoverage(for item: MissingPricingItem) -> Bool {
        guard let modelID = item.modelID else { return false }
        return !matchingEntries(for: modelID).isEmpty
    }

    func beginFixing(_ item: MissingPricingItem) {
        guard let modelID = item.modelID, !modelID.isEmpty else {
            operation = .failed("无法从诊断中可靠确定模型 ID。请查看原始详情后手动添加。")
            return
        }
        let matches = matchingEntries(for: modelID)
        if matches.count == 1, let entry = matches.first {
            beginEdit(entry)
        } else if matches.isEmpty {
            beginAdd(prefilling: modelID)
        } else {
            operation = .failed("存在多个可匹配该模型的覆盖，无法自动选择。请先手动处理重复条目。")
        }
    }

    func clearFeedback() {
        guard !operation.isBusy else { return }
        operation = .idle
    }

    private func applyLoadedSnapshot(
        _ loaded: CustomPricingSnapshot,
        previous: CustomPricingSnapshot?
    ) {
        if let previous,
           (previous.fileURL != loaded.fileURL || previous.originalData != loaded.originalData),
           report != nil {
            isReportStale = true
        }
        fileState = .loaded(loaded)
        if let selectedModelID,
           !loaded.entries.contains(where: { $0.modelID == selectedModelID }) {
            self.selectedModelID = nil
        }
    }

    private func matchingEntries(for modelID: String) -> [CustomPricingEntry] {
        let exact = entries.filter {
            $0.modelID.caseInsensitiveCompare(modelID) == .orderedSame
        }
        if !exact.isEmpty { return exact }

        let normalized = Self.normalizedSyntheticModelID(modelID)
        guard normalized.caseInsensitiveCompare(modelID) != .orderedSame else { return [] }
        return entries.filter {
            $0.modelID.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func normalizedSyntheticModelID(_ modelID: String) -> String {
        let lowercased = modelID.lowercased()
        if lowercased.hasPrefix("hf:") {
            let remainder = lowercased.dropFirst(3)
            return remainder.split(separator: "/", maxSplits: 1).last.map(String.init)
                ?? String(remainder)
        }
        if lowercased.hasPrefix("accounts/"),
           let range = lowercased.range(of: "/models/") {
            return String(lowercased[range.upperBound...])
        }
        return lowercased
    }

    private func commandContext() throws -> TokscaleCommandContext {
        let preferences = preferencesStore.load()
        let version = preferences.tokscaleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokscaleCommandBuilder.isValidVersion(version) else {
            throw TokscaleCLIError.invalidVersion
        }
        let path = preferences.npxPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let npxURL = npxLocator.locate(preferredPath: path.isEmpty ? nil : path) else {
            throw TokscaleCLIError.missingNpx
        }
        return TokscaleCommandContext(npxURL: npxURL, version: version)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
