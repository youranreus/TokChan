import AppKit
import SwiftUI
import XCTest
@testable import TokChan

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testRenderFixedDashboardInBothAppearances() async throws {
        let model = DashboardViewModel(api: PreviewAPIService(), cli: PreviewCLIService(),
            preferencesStore: PreviewPreferencesStore(), npxLocator: PreviewNpxLocator(),
            cacheStore: PreviewCacheStore())
        await model.load()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let hosting = NSHostingView(rootView: DashboardView(viewModel: model)
                .environment(\.locale, Locale(identifier: "zh_CN")))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 680),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.appearance = NSAppearance(named: appearance)
            hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 680)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/TokChan-dashboard-\(name).png"))
            XCTAssertEqual(hosting.fittingSize.width, 380, accuracy: 1)
            XCTAssertEqual(hosting.fittingSize.height, 680, accuracy: 1)
        }
    }
}
