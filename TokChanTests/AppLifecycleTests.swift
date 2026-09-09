import XCTest
@testable import TokChan

final class SystemWakeObserverTests: XCTestCase {
    private let wakeName = Notification.Name("TokChanTestsDidWake")

    func testRepeatedStartRegistersASingleObserver() {
        let center = NotificationCenter()
        var wakes = 0
        let observer = SystemWakeObserver(
            center: center,
            notificationName: wakeName,
            handler: { wakes += 1 }
        )

        observer.start()
        observer.start()
        center.post(name: wakeName, object: nil)

        XCTAssertEqual(wakes, 1)
    }

    func testEveryWakeIsForwardedWhileObserving() {
        let center = NotificationCenter()
        var wakes = 0
        let observer = SystemWakeObserver(
            center: center,
            notificationName: wakeName,
            handler: { wakes += 1 }
        )
        observer.start()

        center.post(name: wakeName, object: nil)
        center.post(name: wakeName, object: nil)

        XCTAssertEqual(wakes, 2)
    }

    func testStoppingRemovesTheObserverAndCanRestart() {
        let center = NotificationCenter()
        var wakes = 0
        let observer = SystemWakeObserver(
            center: center,
            notificationName: wakeName,
            handler: { wakes += 1 }
        )

        observer.start()
        observer.stop()
        center.post(name: wakeName, object: nil)
        XCTAssertEqual(wakes, 0)

        observer.start()
        center.post(name: wakeName, object: nil)
        XCTAssertEqual(wakes, 1)
    }

    func testDeallocationStopsForwarding() {
        let center = NotificationCenter()
        var wakes = 0
        do {
            let observer = SystemWakeObserver(
                center: center,
                notificationName: wakeName,
                handler: { wakes += 1 }
            )
            observer.start()
        }

        center.post(name: wakeName, object: nil)

        XCTAssertEqual(wakes, 0)
    }
}
