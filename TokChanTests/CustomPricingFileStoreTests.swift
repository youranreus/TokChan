import XCTest
@testable import TokChan

final class CustomPricingFileStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private let store = CustomPricingFileStore()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokChan-CustomPricing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("custom-pricing.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadsMissingFileAsDistinctEmptySnapshotAndCreatesMinimalDocument() throws {
        let empty = try store.load(from: fileURL)
        XCTAssertFalse(empty.exists)
        XCTAssertTrue(empty.entries.isEmpty)

        let saved = try store.add(draft(modelID: "free-model", input: 0, output: 0), to: empty)

        XCTAssertTrue(saved.exists)
        XCTAssertEqual(saved.entries.first?.inputPrice, 0)
        let root = try json(at: fileURL)
        XCTAssertNotNil((root["models"] as? [String: Any])?["free-model"])
    }

    func testEditingChangedRateNormalizesAliasesAndPreservesUnknownAndTierFields() throws {
        try Data(#"""
        {
          "$schema": "https://example/schema.json",
          "root_extension": {"enabled": true},
          "models": {
            "claude/test": {
              "input_cost_per_token": 0.000003,
              "output_cost_per_million_tokens": 15,
              "output_cost_per_million_tokens_above_200k_tokens": 22.5,
              "source": "manual",
              "notes": "keep",
              "extension": {"nested": [1, 2, 3]}
            },
            "other": {"input_cost_per_million_tokens": 1, "output_cost_per_million_tokens": 2, "untouched": 42}
          }
        }
        """#.utf8).write(to: fileURL)
        let loaded = try store.load(from: fileURL)
        XCTAssertEqual(loaded.entries.first { $0.modelID == "claude/test" }?.inputPrice, 3)

        let updated = try store.update(
            originalModelID: "claude/test",
            with: draft(modelID: "claude/test", input: 4, output: 15, source: "manual", notes: "keep"),
            in: loaded
        )

        XCTAssertEqual(updated.entries.first { $0.modelID == "claude/test" }?.inputPrice, 4)
        let root = try json(at: fileURL)
        let models = try XCTUnwrap(root["models"] as? [String: Any])
        let edited = try XCTUnwrap(models["claude/test"] as? [String: Any])
        XCTAssertNil(edited["input_cost_per_token"])
        XCTAssertEqual((edited["input_cost_per_million_tokens"] as? NSNumber)?.doubleValue, 4)
        XCTAssertEqual((edited["output_cost_per_million_tokens_above_200k_tokens"] as? NSNumber)?.doubleValue, 22.5)
        XCTAssertNotNil(edited["extension"])
        XCTAssertEqual((models["other"] as? [String: Any])?["untouched"] as? Int, 42)
        XCTAssertNotNil(root["root_extension"])
    }

    func testClearingCacheRateRemovesMillionAndPerTokenAliases() throws {
        try Data(#"""
        {"models":{"model":{"input_cost_per_million_tokens":1,"cache_read_input_token_cost":0.0000002,"cache_read_input_token_cost_per_million_tokens":0.2,"cacheReadInputTokenCost":"unknown-extension"}}}
        """#.utf8).write(to: fileURL)
        let loaded = try store.load(from: fileURL)

        _ = try store.update(
            originalModelID: "model",
            with: draft(modelID: "model", input: 1, output: nil, cacheRead: nil),
            in: loaded
        )

        let model = try XCTUnwrap((try json(at: fileURL)["models"] as? [String: Any])?["model"] as? [String: Any])
        XCTAssertNil(model["cache_read_input_token_cost"])
        XCTAssertNil(model["cache_read_input_token_cost_per_million_tokens"])
        XCTAssertEqual(model["cacheReadInputTokenCost"] as? String, "unknown-extension")
    }

    func testEditingOtherFieldPreservesRoundTripRateAndMetadataWhitespace() throws {
        try Data(#"{"models":{"precise":{"input_cost_per_million_tokens":0.0000000000001234567,"source":"  exact source  ","notes":" keep spacing "}}}"#.utf8)
            .write(to: fileURL)
        let loaded = try store.load(from: fileURL)
        let entry = try XCTUnwrap(loaded.entries.first)
        var editorDraft = CustomPricingDraft(entry: entry)
        editorDraft.outputPrice = "2"
        let validated = try CustomPricingValidation.validate(
            editorDraft,
            entries: loaded.entries,
            editing: entry.modelID
        )

        _ = try store.update(originalModelID: entry.modelID, with: validated, in: loaded)

        let saved = try JSONDecoder().decode(PrecisePriceDocument.self, from: Data(contentsOf: fileURL))
            .models["precise"]
        XCTAssertEqual(saved?.inputPrice, Decimal(string: "0.0000000000001234567"))
        XCTAssertEqual(saved?.source, "  exact source  ")
        XCTAssertEqual(saved?.notes, " keep spacing ")
    }

    func testDeleteRemovesOnlySelectedEntry() throws {
        try Data(#"{"models":{"remove":{"input_cost_per_million_tokens":1},"keep":{"output_cost_per_million_tokens":2,"unknown":{"a":true}}}}"#.utf8)
            .write(to: fileURL)
        let loaded = try store.load(from: fileURL)

        _ = try store.delete(modelID: "remove", from: loaded)

        let models = try XCTUnwrap(try json(at: fileURL)["models"] as? [String: Any])
        XCTAssertNil(models["remove"])
        XCTAssertNotNil((models["keep"] as? [String: Any])?["unknown"])
    }

    func testWriteFailureLeavesOriginalReadable() throws {
        let original = Data(#"{"models":{}}"#.utf8)
        try original.write(to: fileURL)
        let loaded = try store.load(from: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try store.add(draft(modelID: "new", input: 1, output: nil), to: loaded))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testRefusesMalformedJSONAndExternalModification() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertThrowsError(try store.load(from: fileURL)) { error in
            XCTAssertTrue(error is CustomPricingError)
        }

        try Data(#"{"models":{}}"#.utf8).write(to: fileURL)
        let loaded = try store.load(from: fileURL)
        try Data(#"{"models":{"external":{"input_cost_per_million_tokens":1}}}"#.utf8).write(to: fileURL)
        XCTAssertThrowsError(try store.add(draft(modelID: "mine", input: 1, output: nil), to: loaded)) { error in
            XCTAssertEqual(error as? CustomPricingError, .externalModification)
        }
        XCTAssertNotNil((try json(at: fileURL)["models"] as? [String: Any])?["external"])
    }

    func testValidationRejectsCaseInsensitiveDuplicateNegativeAndMissingCorePrices() throws {
        let entries = [CustomPricingEntry(modelID: "GPT-5", inputPrice: 1, outputPrice: nil,
                                          cacheReadPrice: nil, cacheWritePrice: nil,
                                          source: nil, notes: nil, issue: nil)]
        var duplicate = CustomPricingDraft()
        duplicate.modelID = "gpt-5"
        duplicate.inputPrice = "1"
        XCTAssertThrowsError(try CustomPricingValidation.validate(duplicate, entries: entries, editing: nil))

        var negative = CustomPricingDraft()
        negative.modelID = "new"
        negative.inputPrice = "-1"
        XCTAssertThrowsError(try CustomPricingValidation.validate(negative, entries: [], editing: nil))

        var cacheOnly = CustomPricingDraft()
        cacheOnly.modelID = "new"
        cacheOnly.cacheReadPrice = "0"
        XCTAssertThrowsError(try CustomPricingValidation.validate(cacheOnly, entries: [], editing: nil))
    }

    private func draft(
        modelID: String,
        input: Double?,
        output: Double?,
        cacheRead: Double? = nil,
        cacheWrite: Double? = nil,
        source: String? = nil,
        notes: String? = nil
    ) -> ValidatedCustomPricingDraft {
        ValidatedCustomPricingDraft(modelID: modelID, inputPrice: input, outputPrice: output,
                                    cacheReadPrice: cacheRead, cacheWritePrice: cacheWrite,
                                    source: source, notes: notes)
    }

    private func json(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

private struct PrecisePriceDocument: Decodable {
    struct Entry: Decodable {
        let inputPrice: Decimal
        let source: String
        let notes: String

        enum CodingKeys: String, CodingKey {
            case inputPrice = "input_cost_per_million_tokens"
            case source, notes
        }
    }

    let models: [String: Entry]
}
