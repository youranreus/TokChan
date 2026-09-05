import Foundation

struct CustomPricingEntry: Identifiable, Equatable {
    var id: String { modelID }

    let modelID: String
    let inputPrice: Double?
    let outputPrice: Double?
    let cacheReadPrice: Double?
    let cacheWritePrice: Double?
    let source: String?
    let notes: String?
    let issue: String?
}

struct CustomPricingSnapshot: Equatable {
    let fileURL: URL
    let originalData: Data?
    let entries: [CustomPricingEntry]

    var exists: Bool { originalData != nil }
}

struct CustomPricingDraft: Equatable {
    var modelID = ""
    var inputPrice = ""
    var outputPrice = ""
    var cacheReadPrice = ""
    var cacheWritePrice = ""
    var source = ""
    var notes = ""

    init() {}

    init(entry: CustomPricingEntry) {
        modelID = entry.modelID
        inputPrice = Self.string(entry.inputPrice)
        outputPrice = Self.string(entry.outputPrice)
        cacheReadPrice = Self.string(entry.cacheReadPrice)
        cacheWritePrice = Self.string(entry.cacheWritePrice)
        source = entry.source ?? ""
        notes = entry.notes ?? ""
    }

    private static func string(_ value: Double?) -> String {
        guard let value else { return "" }
        // Swift's description is locale-independent and round-trips a Double.
        // Capping decimal places here could silently change an untouched rate
        // when the user edits only another field.
        return String(value)
    }
}

struct ValidatedCustomPricingDraft: Equatable {
    let modelID: String
    let inputPrice: Double?
    let outputPrice: Double?
    let cacheReadPrice: Double?
    let cacheWritePrice: Double?
    let source: String?
    let notes: String?
}

enum CustomPricingValidation {
    static func validate(
        _ draft: CustomPricingDraft,
        entries: [CustomPricingEntry],
        editing originalModelID: String?
    ) throws -> ValidatedCustomPricingDraft {
        let editingEntry = originalModelID.flatMap { original in
            entries.first { $0.modelID == original }
        }
        let modelID = draft.modelID == originalModelID
            ? draft.modelID
            : draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty,
              modelID.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CustomPricingError.invalidModelID
        }
        let duplicate = entries.contains {
            $0.modelID.caseInsensitiveCompare(modelID) == .orderedSame && $0.modelID != originalModelID
        }
        guard !duplicate else { throw CustomPricingError.duplicateModelID(modelID) }

        let input = try price(draft.inputPrice)
        let output = try price(draft.outputPrice)
        let cacheRead = try price(draft.cacheReadPrice)
        let cacheWrite = try price(draft.cacheWritePrice)
        guard input != nil || output != nil else { throw CustomPricingError.missingRequiredPrice }

        return ValidatedCustomPricingDraft(
            modelID: modelID,
            inputPrice: input,
            outputPrice: output,
            cacheReadPrice: cacheRead,
            cacheWritePrice: cacheWrite,
            source: metadata(draft.source, previous: editingEntry?.source),
            notes: metadata(draft.notes, previous: editingEntry?.notes)
        )
    }

    private static func price(_ text: String) throws -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let value = Double(normalized), value.isFinite, value >= 0 else {
            throw CustomPricingError.invalidPrice(text)
        }
        return value
    }

    private static func metadata(_ text: String, previous: String?) -> String? {
        // Preserve an untouched value byte-for-byte, including intentional
        // leading/trailing whitespace. Normalize only an actively edited value.
        if text == previous { return previous }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum PricingCheckOutcome: Equatable {
    case missingPricing
    case noMissingPricing
    case noData
    case partialData
    case unknownFormat
}

struct MissingPricingItem: Identifiable, Equatable {
    let id: UUID
    let providerModel: String
    let provider: String?
    let modelID: String?
    let messageCount: Int?
    let tokenCount: Double?
    let reason: String

    init(
        id: UUID = UUID(),
        providerModel: String,
        provider: String?,
        modelID: String?,
        messageCount: Int?,
        tokenCount: Double?,
        reason: String
    ) {
        self.id = id
        self.providerModel = providerModel
        self.provider = provider
        self.modelID = modelID
        self.messageCount = messageCount
        self.tokenCount = tokenCount
        self.reason = reason
    }
}

struct PricingDiagnosticReport: Equatable {
    let outcome: PricingCheckOutcome
    let items: [MissingPricingItem]
    let warnings: [String]
    let details: String
    let checkedAt: Date
}

enum CustomPricingError: LocalizedError, Equatable {
    case invalidDocument(String)
    case invalidModels
    case invalidEntry(String)
    case invalidModelID
    case duplicateModelID(String)
    case invalidPrice(String)
    case missingRequiredPrice
    case externalModification
    case staleConfiguration
    case missingOriginalEntry(String)
    case unsupportedLocation

    var errorDescription: String? {
        switch self {
        case let .invalidDocument(detail):
            return "自定义价格文件已损坏，未进行写入：\(detail)"
        case .invalidModels:
            return "自定义价格文件的 models 必须是 JSON 对象，未进行写入。"
        case let .invalidEntry(model):
            return "模型 \(model) 的价格条目不是 JSON 对象，无法编辑。"
        case .invalidModelID:
            return "模型 ID 不能为空，也不能包含控制字符。"
        case let .duplicateModelID(model):
            return "已存在大小写相同的模型 ID：\(model)"
        case let .invalidPrice(value):
            return "价格“\(value)”无效；请输入大于或等于 0 的数字。"
        case .missingRequiredPrice:
            return "至少填写输入或输出价格之一；空值不会保存为 0。"
        case .externalModification:
            return "价格文件已被其他程序修改。请重新载入并确认新内容后再保存。"
        case .staleConfiguration:
            return "已保存的 npx 或 Tokscale 版本已变化。请重新载入价格文件后再操作。"
        case let .missingOriginalEntry(model):
            return "模型 \(model) 已不存在。请重新载入价格文件。"
        case .unsupportedLocation:
            return "Tokscale 返回了无法识别的价格文件路径。"
        }
    }
}
