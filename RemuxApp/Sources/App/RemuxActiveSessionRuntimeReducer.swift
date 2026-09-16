import Foundation

enum ActiveSessionRuntimeTransitionOutcome: Equatable, Sendable {
    case missingSession
    case staleInstance(current: UUID, stale: UUID)
    case applied(TerminalRuntimeState)
    case automaticReconnectStarted(source: TerminalReconnectSource, state: TerminalRuntimeState)
    case automaticReconnectSkipped(source: TerminalReconnectSource, state: TerminalRuntimeState)
}

enum RemuxActiveSessionRuntimeReducer {
    static func apply(
        _ update: TerminalRuntimeStateUpdate,
        to activeSessions: inout [ActiveTerminalSession],
        requestedReconnectSource: TerminalReconnectSource?
    ) -> ActiveSessionRuntimeTransitionOutcome {
        guard let index = activeSessions.firstIndex(where: { $0.id == update.workspaceID }) else {
            return .missingSession
        }
        guard activeSessions[index].instanceID == update.instanceID else {
            return .staleInstance(
                current: activeSessions[index].instanceID,
                stale: update.instanceID
            )
        }

        let nextState = resolvedRuntimeState(
            update.state,
            current: activeSessions[index].runtimeState
        )
        activeSessions[index].applyRuntimeState(nextState)

        guard let requestedReconnectSource else {
            return .applied(nextState)
        }
        guard activeSessions[index].markAutomaticReconnectAttempted(source: requestedReconnectSource) else {
            return .automaticReconnectSkipped(
                source: requestedReconnectSource,
                state: nextState
            )
        }
        return .automaticReconnectStarted(
            source: requestedReconnectSource,
            state: nextState
        )
    }

    private static func resolvedRuntimeState(
        _ nextState: TerminalRuntimeState,
        current: TerminalRuntimeState
    ) -> TerminalRuntimeState {
        if case .connecting = nextState,
           case .reconnecting = current {
            return current
        }
        return nextState
    }
}
