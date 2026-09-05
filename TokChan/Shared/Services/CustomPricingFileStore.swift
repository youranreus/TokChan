import Foundation

protocol CustomPricingFileStoring {
    func load(from url: URL) throws -> CustomPricingSnapshot
    func hasChanged(_ snapshot: CustomPricingSnapshot) throws -> Bool
    func add(_ draft: ValidatedCustomPricingDraft, to snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot
    func update(
        originalModelID: String,
        with draft: ValidatedCustomPricingDraft,
        in snapshot: CustomPricingSnapshot
    ) throws -> CustomPricingSnapshot
    func delete(modelID: String, from snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot
}

final class CustomPricingFileStore: CustomPricingFileStoring {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from url: URL) throws -> CustomPricingSnapshot {
        let data = try existingData(at: url)
        guard let data else {
            return CustomPricingSnapshot(fileURL: url, originalData: nil, entries: [])
        }
        let root = try parseRoot(data)
        let models = try modelsDictionary(in: root)
        let duplicates = Dictionary(grouping: models.keys, by: { $0.lowercased() })
            .filter { $0.value.count > 1 }
            .flatMap(\.value)
        let duplicateSet = Set(duplicates)
        let entries = models.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { modelID in
                Self.entry(
                    modelID: modelID,
                    value: models[modelID] ?? NSNull(),
                    hasCaseDuplicate: duplicateSet.contains(modelID)
                )
            }
        return CustomPricingSnapshot(fileURL: url, originalData: data, entries: entries)
    }

    func hasChanged(_ snapshot: CustomPricingSnapshot) throws -> Bool {
        try existingData(at: snapshot.fileURL) != snapshot.originalData
    }

    func add(
        _ draft: ValidatedCustomPricingDraft,
        to snapshot: CustomPricingSnapshot
    ) throws -> CustomPricingSnapshot {
        var root = try mutableRoot(for: snapshot)
        var models = try modelsDictionary(in: root)
        guard !models.keys.contains(where: {
            $0.caseInsensitiveCompare(draft.modelID) == .orderedSame
        }) else {
            throw CustomPricingError.duplicateModelID(draft.modelID)
        }
        models[draft.modelID] = Self.newEntry(from: draft)
        root["models"] = models
        return try save(root, replacing: snapshot)
    }

    func update(
        originalModelID: String,
        with draft: ValidatedCustomPricingDraft,
        in snapshot: CustomPricingSnapshot
    ) throws -> CustomPricingSnapshot {
        var root = try mutableRoot(for: snapshot)
        var models = try modelsDictionary(in: root)
        guard var entry = models[originalModelID] as? [String: Any] else {
            if models[originalModelID] == nil {
                throw CustomPricingError.missingOriginalEntry(originalModelID)
            }
            throw CustomPricingError.invalidEntry(originalModelID)
        }
        let old = Self.entry(modelID: originalModelID, value: entry, hasCaseDuplicate: false)
        if draft.modelID != originalModelID {
            guard !models.keys.contains(where: {
                $0 != originalModelID && $0.caseInsensitiveCompare(draft.modelID) == .orderedSame
            }) else {
                throw CustomPricingError.duplicateModelID(draft.modelID)
            }
        }

        Self.updateRate(.input, desired: draft.inputPrice, previous: old.inputPrice, entry: &entry)
        Self.updateRate(.output, desired: draft.outputPrice, previous: old.outputPrice, entry: &entry)
        Self.updateRate(.cacheRead, desired: draft.cacheReadPrice, previous: old.cacheReadPrice, entry: &entry)
        Self.updateRate(.cacheWrite, desired: draft.cacheWritePrice, previous: old.cacheWritePrice, entry: &entry)
        Self.updateMetadata("source", desired: draft.source, previous: old.source, entry: &entry)
        Self.updateMetadata("notes", desired: draft.notes, previous: old.notes, entry: &entry)

        if draft.modelID != originalModelID { models.removeValue(forKey: originalModelID) }
        models[draft.modelID] = entry
        root["models"] = models
        return try save(root, replacing: snapshot)
    }

    func delete(modelID: String, from snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot {
        var root = try mutableRoot(for: snapshot)
        var models = try modelsDictionary(in: root)
        guard models.removeValue(forKey: modelID) != nil else {
            throw CustomPricingError.missingOriginalEntry(modelID)
        }
        root["models"] = models
        return try save(root, replacing: snapshot)
    }

    private func mutableRoot(for snapshot: CustomPricingSnapshot) throws -> [String: Any] {
        let current = try existingData(at: snapshot.fileURL)
        guard current == snapshot.originalData else { throw CustomPricingError.externalModification }
        guard let current else { return ["models": [String: Any]()] }
        return try parseRoot(current)
    }

    private func save(
        _ root: [String: Any],
        replacing snapshot: CustomPricingSnapshot
    ) throws -> CustomPricingSnapshot {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw CustomPricingError.invalidDocument("包含无法编码的值")
        }
        let current = try existingData(at: snapshot.fileURL)
        guard current == snapshot.originalData else { throw CustomPricingError.externalModification }
        try fileManager.createDirectory(
            at: snapshot.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: snapshot.fileURL, options: .atomic)
        return try load(from: snapshot.fileURL)
    }

    private func existingData(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func parseRoot(_ data: Data) throws -> [String: Any] {
        do {
            let value = try JSONDecoder().decode(DecimalPreservingJSONValue.self, from: data)
            guard case let .object(root) = value else {
                throw CustomPricingError.invalidDocument("根节点必须是 JSON 对象")
            }
            return root.mapValues(\.foundationValue)
        } catch let error as CustomPricingError {
            throw error
        } catch {
            throw CustomPricingError.invalidDocument(error.localizedDescription)
        }
    }

    private func modelsDictionary(in root: [String: Any]) throws -> [String: Any] {
        guard let models = root["models"] as? [String: Any] else {
            throw CustomPricingError.invalidModels
        }
        return models
    }

    private enum RateField {
        case input, output, cacheRead, cacheWrite

        var aliases: [(key: String, perToken: Bool)] {
            switch self {
            case .input:
                return [
                    ("input_cost_per_million_tokens", false),
                    ("input_cost_per_token", true)
                ]
            case .output:
                return [
                    ("output_cost_per_million_tokens", false),
                    ("output_cost_per_token", true)
                ]
            case .cacheRead:
                return [
                    ("cache_read_input_token_cost_per_million_tokens", false),
                    ("cache_read_input_token_cost", true)
                ]
            case .cacheWrite:
                return [
                    ("cache_creation_input_token_cost_per_million_tokens", false),
                    ("cache_creation_input_token_cost", true)
                ]
            }
        }

        var canonicalKey: String { aliases[0].key }
    }

    private static func entry(
        modelID: String,
        value: Any,
        hasCaseDuplicate: Bool
    ) -> CustomPricingEntry {
        guard let object = value as? [String: Any] else {
            return CustomPricingEntry(
                modelID: modelID, inputPrice: nil, outputPrice: nil,
                cacheReadPrice: nil, cacheWritePrice: nil,
                source: nil, notes: nil, issue: "条目不是 JSON 对象；CLI 可能会跳过它。"
            )
        }
        var issues: [String] = []
        let input = readRate(.input, from: object, issues: &issues)
        let output = readRate(.output, from: object, issues: &issues)
        let cacheRead = readRate(.cacheRead, from: object, issues: &issues)
        let cacheWrite = readRate(.cacheWrite, from: object, issues: &issues)
        if hasCaseDuplicate { issues.append("存在大小写重复的模型 ID；添加和自动匹配已被阻止。") }
        let source = readString("source", from: object, issues: &issues)
        let notes = readString("notes", from: object, issues: &issues)
        return CustomPricingEntry(
            modelID: modelID,
            inputPrice: input,
            outputPrice: output,
            cacheReadPrice: cacheRead,
            cacheWritePrice: cacheWrite,
            source: source,
            notes: notes,
            issue: issues.isEmpty ? nil : issues.joined(separator: " ")
        )
    }

    private static func readRate(
        _ field: RateField,
        from object: [String: Any],
        issues: inout [String]
    ) -> Double? {
        var values: [(String, Decimal)] = []
        for alias in field.aliases where object[alias.key] != nil {
            guard let number = numeric(object[alias.key] as Any) else {
                issues.append("\(alias.key) 不是有效数字。")
                continue
            }
            let normalized = alias.perToken ? number * Decimal(1_000_000) : number
            guard !normalized.isNaN, normalized >= 0 else {
                issues.append("\(alias.key) 不是非负有限价格。")
                continue
            }
            values.append((alias.key, normalized))
        }
        if values.count > 1 {
            // Tokscale rejects an entry whenever both its per-million and
            // per-token forms are present, even if their numeric values agree.
            issues.append("同一费率同时存在每百万和每 Token 别名；CLI 会跳过该条目，编辑该费率可统一表示。")
        }
        return values.first.map { NSDecimalNumber(decimal: $0.1).doubleValue }
    }

    private static func numeric(_ value: Any) -> Decimal? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c" else { return nil }
        if let decimal = number as? NSDecimalNumber { return decimal.decimalValue }
        return Decimal(number.doubleValue)
    }

    private static func readString(
        _ key: String,
        from object: [String: Any],
        issues: inout [String]
    ) -> String? {
        guard let value = object[key] else { return nil }
        guard let string = value as? String else {
            issues.append("\(key) 不是文本，已保留原值。")
            return nil
        }
        return string
    }

    private static func newEntry(from draft: ValidatedCustomPricingDraft) -> [String: Any] {
        var entry: [String: Any] = [:]
        setRate(.input, value: draft.inputPrice, entry: &entry)
        setRate(.output, value: draft.outputPrice, entry: &entry)
        setRate(.cacheRead, value: draft.cacheReadPrice, entry: &entry)
        setRate(.cacheWrite, value: draft.cacheWritePrice, entry: &entry)
        if let source = draft.source { entry["source"] = source }
        if let notes = draft.notes { entry["notes"] = notes }
        return entry
    }

    private static func updateRate(
        _ field: RateField,
        desired: Double?,
        previous: Double?,
        entry: inout [String: Any]
    ) {
        guard desired != previous else { return }
        for alias in field.aliases { entry.removeValue(forKey: alias.key) }
        setRate(field, value: desired, entry: &entry)
    }

    private static func setRate(
        _ field: RateField,
        value: Double?,
        entry: inout [String: Any]
    ) {
        if let value { entry[field.canonicalKey] = value }
    }

    private static func updateMetadata(
        _ key: String,
        desired: String?,
        previous: String?,
        entry: inout [String: Any]
    ) {
        guard desired != previous else { return }
        if let desired { entry[key] = desired }
        else { entry.removeValue(forKey: key) }
    }
}

private enum DecimalPreservingJSONValue: Decodable {
    case object([String: DecimalPreservingJSONValue])
    case array([DecimalPreservingJSONValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    var foundationValue: Any {
        switch self {
        case let .object(value): return value.mapValues(\.foundationValue)
        case let .array(value): return value.map(\.foundationValue)
        case let .string(value): return value
        case let .number(value): return NSDecimalNumber(decimal: value)
        case let .bool(value): return value
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: DynamicJSONKey.self) {
            var result: [String: DecimalPreservingJSONValue] = [:]
            for key in object.allKeys {
                result[key.stringValue] = try object.decode(DecimalPreservingJSONValue.self, forKey: key)
            }
            self = .object(result)
            return
        }
        if var array = try? decoder.unkeyedContainer() {
            var result: [DecimalPreservingJSONValue] = []
            while !array.isAtEnd {
                result.append(try array.decode(DecimalPreservingJSONValue.self))
            }
            self = .array(result)
            return
        }

        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else {
            throw DecodingError.dataCorruptedError(
                in: value,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

private struct DynamicJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
