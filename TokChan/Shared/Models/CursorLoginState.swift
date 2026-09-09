import Foundation

enum CursorLoginState: Equatable {
    case idle
    case loggingIn
    case succeeded(String)
    case failed(message: String, fallbackCommand: String)
}
