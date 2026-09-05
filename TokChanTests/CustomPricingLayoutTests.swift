import AppKit
import SwiftUI
import XCTest
@testable import TokChan

@MainActor
final class CustomPricingLayoutTests: XCTestCase {
    func testRendersLongAndManyEntriesInBothAppearances() async throws {
        let model = CustomPricingViewModel(
            cli: PreviewCLIService(),
            store: PreviewCustomPricingStore(),
            preferencesStore: PreviewPreferencesStore(),
            npxLocator: PreviewNpxLocator()
        )
        await model.load()
        XCTAssertGreaterThan(model.entries.count, 14)
        XCTAssertTrue(model.entries.contains { $0.modelID.count > 30 })

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let hosting = NSHostingView(
                rootView: CustomPricingSettingsView(viewModel: model)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.appearance = NSAppearance(named: appearance)
            hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 680)
            hosting.layoutSubtreeIfNeeded()

            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
            XCTAssertLessThanOrEqual(hosting.fittingSize.width, 900)
            XCTAssertLessThanOrEqual(hosting.fittingSize.height, 680)
        }
    }
}
