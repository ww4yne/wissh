import Foundation

enum GhosttyTerminalRuntimePhase: Equatable, Sendable {
    case idle
    case starting
    case running
    case failed(message: String, reason: TerminalDisconnectReason?)
}
