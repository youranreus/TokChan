import AppKit
import Foundation

/// Bridges a system wake notification into one idempotent application-level callback.
///
/// The observer owns its registration token so repeated `start()` calls cannot install a
/// second observer and deallocation cannot leave a dangling registration behind.
final class SystemWakeObserver {
    private let center: NotificationCenter
    private let notificationName: Notification.Name
    private let handler: () -> Void
    private var token: NSObjectProtocol?

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notificationName: Notification.Name = NSWorkspace.didWakeNotification,
        handler: @escaping () -> Void
    ) {
        self.center = center
        self.notificationName = notificationName
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard token == nil else { return }
        token = center.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { [handler] _ in handler() }
    }

    func stop() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }
}
