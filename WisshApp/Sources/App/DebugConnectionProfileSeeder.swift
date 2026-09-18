import Foundation

#if DEBUG || WISSH_LIVE_UI_TESTING
enum DebugConnectionProfileSeederError: LocalizedError, Sendable {
    case invalidEnvironment(TmuxConnectionDraftValidation)
    case invalidJumpEnvironment(String)

    var errorDescription: String? {
        switch self {
        case .invalidEnvironment(let validation):
            let messages = [
                validation.displayName,
                validation.host,
                validation.port,
                validation.username,
                validation.proxyJumpHost,
                validation.proxyJumpPort,
                validation.proxyJumpUsername,
                validation.password,
                validation.privateKey,
                validation.privateKeyPassphrase,
                validation.sessionName,
            ].compactMap { $0 }
            return "Invalid debug connection seed: \(messages.joined(separator: " "))"
        case .invalidJumpEnvironment(let message):
            return "Invalid debug jump-host seed: \(message)"
        }
    }
}

enum DebugConnectionProfileSeeder {
    private enum Key {
        static let enabled = "WISSH_DEBUG_SEED_CONNECTION"
        static let displayName = "WISSH_DEBUG_SERVER_NAME"
        static let host = "WISSH_DEBUG_SERVER_HOST"
        static let port = "WISSH_DEBUG_SERVER_PORT"
        static let username = "WISSH_DEBUG_SERVER_USERNAME"
        static let password = "WISSH_DEBUG_SERVER_PASSWORD"
        static let privateKey = "WISSH_DEBUG_PRIVATE_KEY"
        static let privateKeyPassphrase = "WISSH_DEBUG_PRIVATE_KEY_PASSPHRASE"
        static let sessionName = "WISSH_DEBUG_TMUX_SESSION"
        static let proxyJump = "WISSH_DEBUG_JUMP_HOST"
        static let jumpPort = "WISSH_DEBUG_JUMP_PORT"
        static let jumpUsername = "WISSH_DEBUG_JUMP_USERNAME"
    }

    @discardableResult
    static func seedIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        profileRepository: any ConnectionProfileRepository,
        credentialStore: any SSHCredentialStore
    ) async throws -> Bool {
        guard environment[Key.enabled] == "1" else { return false }

        let existingProfile = try await profileRepository.loadProfile()
        let draft = TmuxConnectionDraft(
            displayName: environment[Key.displayName] ?? "Example Server",
            host: environment[Key.host] ?? "",
            port: environment[Key.port] ?? "22",
            username: environment[Key.username] ?? "",
            password: environment[Key.password] ?? "",
            privateKey: environment[Key.privateKey],
            privateKeyPassphrase: environment[Key.privateKeyPassphrase],
            sessionName: environment[Key.sessionName] ?? "base"
        )

        switch TmuxConnectionDraftValidator.validate(
            draft,
            existingServerID: existingProfile?.0.id,
            existingWorkspaceID: existingProfile?.1.id
        ) {
        case .invalid(let validation):
            throw DebugConnectionProfileSeederError.invalidEnvironment(validation)

        case .valid(let submission):
            let identity: SSHIdentity
            let credential: SSHCredential?
            switch submission.server.credential {
            case .password(let password):
                identity = SSHIdentity(
                    name: submission.server.displayName,
                    authenticationKind: .password
                )
                credential = .password(password)

            case .privateKey(let privateKeyCredential):
                let inspection = try SSHPrivateKeyInspector.inspect(
                    privateKeyCredential.privateKeyPEM
                )
                identity = SSHIdentity(
                    name: submission.server.displayName,
                    authenticationKind: .privateKey,
                    publicFingerprint: inspection.publicFingerprint
                )
                credential = .privateKey(privateKeyCredential)

            case .none:
                identity = SSHIdentity(
                    name: submission.server.displayName,
                    authenticationKind: .none
                )
                credential = nil
            }
            var server = submission.server.savedServer(identityID: identity.id)
            if let proxyJump = environment[Key.proxyJump], !proxyJump.isEmpty {
                let jumpUsername = environment[Key.jumpUsername] ?? ""
                guard !jumpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DebugConnectionProfileSeederError.invalidJumpEnvironment(
                        "Username is required."
                    )
                }
                let jumpPortText = environment[Key.jumpPort] ?? "22"
                guard let jumpPort = Int(jumpPortText),
                      (1...65_535).contains(jumpPort) else {
                    throw DebugConnectionProfileSeederError.invalidJumpEnvironment(
                        "Port must be between 1 and 65535."
                    )
                }
                server.proxyJump = ProxyJumpConfiguration(
                    host: proxyJump,
                    port: jumpPort,
                    username: jumpUsername,
                    identityID: identity.id
                )
            }
            if let credential {
                try await credentialStore.saveCredential(
                    credential,
                    identityID: identity.id
                )
            }
            try await profileRepository.saveIdentityProfile(
                identity: identity,
                server: server,
                workspace: submission.workspace
            )
            return true
        }
    }
}

private extension TmuxConnectionDraft {
    init(
        displayName: String,
        host: String,
        port: String,
        username: String,
        password: String,
        privateKey: String?,
        privateKeyPassphrase: String?,
        sessionName: String
    ) {
        self.init()
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        if let privateKey, !privateKey.isEmpty {
            self.authenticationKind = .privateKey
            self.privateKeyPEM = privateKey
            self.privateKeyFileName = "Debug private key"
            self.privateKeyPassphrase = privateKeyPassphrase ?? ""
        } else if password.isEmpty {
            self.authenticationKind = .none
        } else {
            self.password = password
        }
        self.sessionName = sessionName
    }
}
#endif
