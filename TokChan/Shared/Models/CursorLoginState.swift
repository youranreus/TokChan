import Foundation

enum CursorLoginState: Equatable {
    case idle
    case loggingIn
    case succeeded(String)
    case failed(message: String, fallbackCommand: String)
}

enum CursorSessionStatus: Equatable {
    case valid
    case unavailable
    case indeterminate
}

enum CursorConnectionState: Equatable {
    case idle
    case checking
    case loggedIn
    case needsLogin
    case checkFailed(String)

    var showsLoginAction: Bool {
        self == .needsLogin
    }

    var showsRetryAction: Bool {
        if case .checkFailed = self { return true }
        return false
    }
}
