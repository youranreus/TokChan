import Foundation

struct PricingDiagnosticsParser {
    func parse(_ output: ProcessOutput, checkedAt: Date = Date()) -> PricingDiagnosticReport {
        let stdout = Self.stripANSI(output.stdout)
        let stderr = Self.stripANSI(output.stderr)
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let lines = combined.components(separatedBy: .newlines)
        let items = Self.missingPricingItems(in: lines)
        let warnings = Self.nonPricingWarnings(in: lines)

        let lowered = combined.lowercased()
        let outcome: PricingCheckOutcome
        if !items.isEmpty {
            // This check must come before no-data: older Tokscale versions can report
            // every row as unpriced and then print a zero/no-data summary.
            outcome = .missingPricing
        } else if Self.containsPricingFailureSignal(lowered) {
            outcome = .unknownFormat
        } else if !warnings.isEmpty {
            // A clean footer cannot prove coverage when one or more scanners or
            // pricing sources degraded. Keep this separate from a verified pass.
            outcome = .partialData
        } else if lowered.contains("no usage data found to submit")
                    || lowered.contains("no usage data available")
                    || lowered.contains("nothing to submit") {
            outcome = .noData
        } else if lowered.contains("dry run - not submitting data")
                    || lowered.contains("dry-run complete")
                    || lowered.contains("dry run complete") {
            outcome = .noMissingPricing
        } else {
            outcome = .unknownFormat
        }

        return PricingDiagnosticReport(
            outcome: outcome,
            items: items,
            warnings: warnings,
            details: combined.trimmingCharacters(in: .whitespacesAndNewlines),
            checkedAt: checkedAt
        )
    }

    private static func missingPricingItems(in lines: [String]) -> [MissingPricingItem] {
        var result: [MissingPricingItem] = []
        var readsCappedIdentifiers = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = line.lowercased()

            // v4.15.0 and current main both print provider/model between
            // "unpriced" and "message(s)". Keep this fixture-faithful shape
            // ahead of looser compatibility patterns.
            let rowPattern = #"(?:excluded|submitting)\s+([0-9,]+)\s+unpriced\s+([^\s]+)\s+message(?:\(s\)|s)?\s*\(([0-9,.]+)\s+tokens?\)(?:\s+at\s+\$[0-9,.]+)?\s*:\s*(.+)"#
            if let groups = captures(rowPattern, in: line), groups.count == 4 {
                result.append(makeItem(
                    providerModel: cleanedIdentifier(groups[1]),
                    messages: integer(groups[0]),
                    tokens: number(groups[2]),
                    reason: lowered.contains("excluded")
                        ? "Tokscale 因价格缺失排除了这部分用量。"
                        : "Tokscale 将这部分用量按 $0 暂计，成本并不完整。"
                ))
                readsCappedIdentifiers = false
                continue
            }

            // Current main caps detailed rows, then emits every remaining
            // provider/model ID in comma-separated continuation lines.
            if lowered.range(of: #"^\.\.\.\s+and\s+[0-9,]+\s+more\s+at\s+\$0(?:\.0+)?\s*:$"#,
                             options: .regularExpression) != nil {
                readsCappedIdentifiers = true
                continue
            }
            if readsCappedIdentifiers {
                if lowered.hasPrefix("unpriced total:") || lowered.hasPrefix("hint:") {
                    readsCappedIdentifiers = false
                } else if !line.isEmpty {
                    let identifiers = line.split(separator: ",").map {
                        cleanedIdentifier(String($0).trimmingCharacters(in: .whitespaces))
                    }
                    if identifiers.allSatisfy({ $0.contains("/") }) {
                        result += identifiers.map {
                            makeItem(providerModel: $0, messages: nil, tokens: nil,
                                     reason: "Tokscale 报告该模型缺少价格；详细影响数已被 CLI 汇总。")
                        }
                        continue
                    }
                    readsCappedIdentifiers = false
                }
            }

            guard lowered.contains("unpriced") || lowered.contains("missing pricing") else { continue }

            // Compatibility with older/alternate prose that places the model
            // identifier after the impact counts.
            let trailingIdentifierPattern = #"(?:excluded|submitting)\s+([0-9,]+)\s+unpriced\s+message(?:\(s\)|s)?\s*\(([0-9,.]+)\s+tokens?\)(?:\s+at\s+\$[0-9,.]+)?\s*:\s*([^\s]+)"#
            if let groups = captures(trailingIdentifierPattern, in: line), groups.count == 3 {
                result.append(makeItem(
                    providerModel: cleanedIdentifier(groups[2]),
                    messages: integer(groups[0]),
                    tokens: number(groups[1]),
                    reason: lowered.contains("excluded")
                        ? "Tokscale 因价格缺失排除了这部分用量。"
                        : "Tokscale 将这部分用量按 $0 暂计，成本并不完整。"
                ))
                continue
            }

            let missingPattern = #"missing\s+pricing(?:\s+data)?(?:\s+for)?\s*[:\-]?\s*([^\s:,]+)[^0-9\n]*([0-9,]+)\s+message(?:s)?[^0-9\n]*([0-9,.]+)\s+tokens?"#
            if let groups = captures(missingPattern, in: line), groups.count == 3 {
                result.append(makeItem(
                    providerModel: cleanedIdentifier(groups[0]),
                    messages: integer(groups[1]),
                    tokens: number(groups[2]),
                    reason: "Tokscale 报告该模型缺少价格。"
                ))
                continue
            }

            let reversePattern = #"([0-9,]+)\s+message(?:s)?[^0-9\n]*([0-9,.]+)\s+tokens?[^:\n]*:\s*([^\s]+).*missing\s+pricing"#
            if let groups = captures(reversePattern, in: line), groups.count == 3 {
                result.append(makeItem(
                    providerModel: cleanedIdentifier(groups[2]),
                    messages: integer(groups[0]),
                    tokens: number(groups[1]),
                    reason: "Tokscale 报告该模型缺少价格。"
                ))
            }
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0.providerModel).inserted }
    }

    private static func makeItem(
        providerModel: String,
        messages: Int?,
        tokens: Double?,
        reason: String
    ) -> MissingPricingItem {
        let identity = splitProviderModel(providerModel)
        return MissingPricingItem(
            providerModel: providerModel,
            provider: identity.provider,
            modelID: identity.model,
            messageCount: messages,
            tokenCount: tokens,
            reason: reason
        )
    }

    private static func splitProviderModel(_ value: String) -> (provider: String?, model: String?) {
        guard let separator = value.firstIndex(of: "/") else {
            return (nil, value.isEmpty ? nil : value)
        }
        let provider = String(value[..<separator])
        let modelStart = value.index(after: separator)
        let model = String(value[modelStart...])
        guard !provider.isEmpty, !model.isEmpty else { return (nil, nil) }
        // Tokscale constructs this field as `provider_id/model_id`, so the
        // first slash is the boundary and any later slash belongs to model_id.
        return (provider, model)
    }

    private static func nonPricingWarnings(in lines: [String]) -> [String] {
        var result: [String] = []
        var isInWarningsSection = false
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = text.lowercased()
            if lowered == "warnings:" || lowered == "warnings" {
                isInWarningsSection = true
                continue
            }
            if lowered.hasPrefix("summary:") || lowered.contains("dry run - not submitting") {
                isInWarningsSection = false
            }
            guard !text.isEmpty else {
                isInWarningsSection = false
                continue
            }
            let directWarning = lowered.contains("warning:")
                || lowered.contains("[tokscale] warning")
                || lowered.contains("failed to cache")
                || lowered.contains("sync failed")
            let sectionWarning = isInWarningsSection
                && (text.hasPrefix("-") || text.hasPrefix("•") || text.hasPrefix("⚠"))
            guard directWarning || sectionWarning else { continue }
            guard !lowered.contains("unpriced") && !lowered.contains("missing pricing") else { continue }
            result.append(text)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private static func containsPricingFailureSignal(_ text: String) -> Bool {
        text.contains("unpriced")
            || text.contains("missing pricing")
            || text.contains("pricing data is unavailable")
            || text.contains("pricing is unavailable")
            || text.contains("cost-incomplete")
    }

    private static func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(
            of: "\u{001B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    private static func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func cleanedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:()[]{}"))
    }

    private static func integer(_ value: String) -> Int? {
        Int(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }
}
