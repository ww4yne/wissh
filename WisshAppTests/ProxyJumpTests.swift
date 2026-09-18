import Foundation
import XCTest
@testable import Wissh

final class ProxyJumpTests: XCTestCase {
    func testDirectServerJSONWithoutProxyJumpConfigurationStillDecodes() throws {
        let serverID = UUID()
        let identityID = UUID()
        let json = """
        {
          "id": "\(serverID.uuidString)",
          "displayName": "Direct",
          "host": "direct.example",
          "port": 22,
          "username": "demo",
          "identityID": "\(identityID.uuidString)"
        }
        """

        let server = try JSONDecoder().decode(
            SavedServer.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(server.proxyJump)
        XCTAssertEqual(server.id, serverID)
        XCTAssertEqual(server.identityID, identityID)
    }

    func testSameIdentityIsRetargetedToJumpUsername() throws {
        let identityID = UUID()
        let auth = try ResolvedSSHAuth.privateKey(
            username: "target-user",
            credential: SSHPrivateKeyCredential(
                privateKeyPEM: Self.ed25519Key
            ),
            identityID: identityID,
            displayLabel: "Shared key"
        )
        let proxyJump = ProxyJumpConfiguration(
            host: "jump.example",
            username: "jump-user",
            identityID: identityID
        )
        let server = SavedServer(
            displayName: "Target",
            host: "127.0.0.1",
            port: 22022,
            username: "target-user",
            identityID: identityID,
            proxyJump: proxyJump
        )

        let target = TmuxConnectionTarget(
            server: server,
            workspace: SavedWorkspace(
                serverID: server.id,
                sessionName: "main"
            ),
            sshAuth: auth
        )

        XCTAssertEqual(target.proxyJumpSSHAuth?.username, "jump-user")
        XCTAssertEqual(target.proxyJumpSSHAuth?.identityID, identityID)
        XCTAssertEqual(target.proxyJumpSSHAuth?.credential, auth.credential)
    }

    func testRootKeyIncludesJumpEndpoint() throws {
        let identityID = UUID()
        let auth = try ResolvedSSHAuth.privateKey(
            username: "target-user",
            credential: SSHPrivateKeyCredential(
                privateKeyPEM: Self.ed25519Key
            ),
            identityID: identityID,
            displayLabel: "Shared key"
        )
        let serverID = UUID()
        let workspace = SavedWorkspace(serverID: serverID, sessionName: "main")
        let firstServer = SavedServer(
            id: serverID,
            displayName: "Target",
            host: "127.0.0.1",
            port: 22022,
            username: "target-user",
            identityID: identityID,
            proxyJump: ProxyJumpConfiguration(
                host: "jump-one.example",
                username: "jump-user",
                identityID: identityID
            )
        )
        let secondServer = SavedServer(
            id: serverID,
            displayName: "Target",
            host: "127.0.0.1",
            port: 22022,
            username: "target-user",
            identityID: identityID,
            proxyJump: ProxyJumpConfiguration(
                host: "jump-two.example",
                username: "jump-user",
                identityID: identityID
            )
        )

        XCTAssertNotEqual(
            RemuxSSHRootKey(
                target: TmuxConnectionTarget(
                    server: firstServer,
                    workspace: workspace,
                    sshAuth: auth
                )
            ),
            RemuxSSHRootKey(
                target: TmuxConnectionTarget(
                    server: secondServer,
                    workspace: workspace,
                    sshAuth: auth
                )
            )
        )
    }

    func testDraftPreservesDistinctProxyJumpIdentity() {
        let targetIdentityID = UUID()
        let jumpIdentityID = UUID()
        let server = SavedServer(
            displayName: "Target",
            host: "target.example",
            username: "target-user",
            identityID: targetIdentityID,
            proxyJump: ProxyJumpConfiguration(
                host: "jump.example",
                username: "jump-user",
                identityID: jumpIdentityID
            )
        )
        var draft = TmuxConnectionDraft(
            server: server,
            workspace: SavedWorkspace(serverID: server.id, sessionName: "main")
        )
        draft.authenticationKind = .none

        guard case .valid(let submission) = TmuxConnectionDraftValidator.validateServer(
            draft,
            existingServerID: server.id
        ) else {
            return XCTFail("Expected valid ProxyJump draft.")
        }

        XCTAssertEqual(draft.proxyJumpIdentityID, jumpIdentityID)
        XCTAssertEqual(
            submission.savedServer(identityID: targetIdentityID).proxyJump?.identityID,
            jumpIdentityID
        )
    }

    private static let ed25519Key = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACA6y4Nl6dWkC0PdxZrJ6S7aYcmBpy9RytK9V0Xz7eIwVQAAAJj3zGE298xh
    NgAAAAtzc2gtZWQyNTUxOQAAACA6y4Nl6dWkC0PdxZrJ6S7aYcmBpy9RytK9V0Xz7eIwVQ
    AAAEB6gaBHbjL56VCVbX8Es1jVLdoaQnikXUxM3SAV105ghzrLg2Xp1aQLQ93FmsnpLtph
    yYGnL1HK0r1XRfPt4jBVAAAAEnJlbXV4LXRlc3QtZml4dHVyZQECAw==
    -----END OPENSSH PRIVATE KEY-----
    """
}

final class ProxyJumpLiveTests: XCTestCase {
    func testConfiguredProxyJumpExecutesOnTarget() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WISSH_LIVE_PROXYJUMP"] == "1" else {
            throw XCTSkip("Set WISSH_LIVE_PROXYJUMP=1 for the opt-in live test.")
        }

        let privateKey = try requiredBase64("WISSH_LIVE_PRIVATE_KEY_BASE64")
        let proxyJumpKey = try requiredBase64("WISSH_LIVE_JUMP_HOST_KEY_BASE64")
        let targetHostKey = try requiredBase64("WISSH_LIVE_TARGET_HOST_KEY_BASE64")
        let proxyJump = try required("WISSH_LIVE_JUMP_HOST")
        let jumpPort = try requiredPort("WISSH_LIVE_JUMP_PORT")
        let jumpUsername = try required("WISSH_LIVE_JUMP_USERNAME")
        let targetHost = try required("WISSH_LIVE_TARGET_HOST")
        let targetPort = try requiredPort("WISSH_LIVE_TARGET_PORT")
        let targetUsername = try required("WISSH_LIVE_TARGET_USERNAME")
        let expectedOutput = try required("WISSH_LIVE_EXPECTED_OUTPUT")

        let identityID = UUID()
        let jump = ProxyJumpConfiguration(
            host: proxyJump,
            port: jumpPort,
            username: jumpUsername,
            identityID: identityID
        )
        let server = SavedServer(
            displayName: "Live ProxyJump",
            host: targetHost,
            port: targetPort,
            username: targetUsername,
            identityID: identityID,
            proxyJump: jump
        )
        let auth = try ResolvedSSHAuth.privateKey(
            username: targetUsername,
            credential: SSHPrivateKeyCredential(privateKeyPEM: privateKey),
            identityID: identityID,
            displayLabel: "Live test key"
        )
        let target = TmuxConnectionTarget(
            server: server,
            workspace: SavedWorkspace(
                serverID: server.id,
                sessionName: "live-test"
            ),
            sshAuth: auth
        )

        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wissh-proxyjump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        defer {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try? FileManager.default.removeItem(at: storageURL)
            }
        }
        let trustedHostStore = TrustedHostStore(rootURL: storageURL)
        let jumpChallenge = try challenge(
            connectionID: jump.id,
            host: jump.host,
            openSSHKey: proxyJumpKey,
            environmentName: "WISSH_LIVE_JUMP_HOST_KEY_BASE64"
        )
        let targetChallenge = try challenge(
            connectionID: server.id,
            host: server.host,
            openSSHKey: targetHostKey,
            environmentName: "WISSH_LIVE_TARGET_HOST_KEY_BASE64"
        )
        try trustedHostStore.trustHostKey(jumpChallenge)
        try trustedHostStore.trustHostKey(targetChallenge)

        let rootService = RemuxSSHRootService()
        let configuration = RemuxAppDependencies.sshConfiguration(
            for: target,
            trustedHostStore: trustedHostStore,
            traceFlowID: "live.proxyjump"
        )
        let trace = RemuxTransportStartupTrace(flowID: "live.proxyjump")
        let preparedRoot = await rootService.preparedRoot(
            for: RemuxSSHRootKey(target: target),
            configuration: configuration.sshRootConfiguration,
            trace: trace
        )

        do {
            let root = try await preparedRoot.sshRoot()
            let claimedRoot = try await preparedRoot.claim(root, trace: trace)
            let result = try await RemuxSSHExecSession.run(
                using: claimedRoot,
                command: "whoami",
                stdin: nil,
                trace: trace
            )
            await preparedRoot.cancelAndCleanup()

            XCTAssertEqual(result.exitStatus, 0)
            let output = String(decoding: result.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(output.lowercased(), expectedOutput.lowercased())
        } catch {
            await preparedRoot.cancelAndCleanup()
            throw error
        }
    }

    private func required(_ name: String) throws -> String {
        let value = ProcessInfo.processInfo.environment[name] ?? ""
        guard !value.isEmpty else {
            throw XCTSkip("Missing \(name).")
        }
        return value
    }

    private func requiredPort(_ name: String) throws -> Int {
        let value = try required(name)
        guard let port = Int(value), (1...65_535).contains(port) else {
            XCTFail("\(name) must be a valid TCP port.")
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        return port
    }

    private func requiredBase64(_ name: String) throws -> String {
        let value = try required(name)
        guard let data = Data(base64Encoded: value) else {
            XCTFail("\(name) must contain Base64.")
            throw CocoaError(.coderInvalidValue)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func challenge(
        connectionID: UUID,
        host: String,
        openSSHKey: String,
        environmentName: String
    ) throws -> SSHHostKeyTrustChallenge {
        let parts = openSSHKey.split(
            whereSeparator: \.isWhitespace
        )
        guard parts.count >= 2 else {
            XCTFail("\(environmentName) must decode to an OpenSSH public key.")
            throw TrustedHostStoreError.invalidHostKey
        }
        let challenge = SSHHostKeyTrustChallenge(
            kind: .unknown,
            serverID: connectionID,
            host: host,
            trustedKeyType: nil,
            trustedOpenSSHPublicKey: nil,
            receivedKeyType: String(parts[0]),
            receivedOpenSSHPublicKey: "\(parts[0]) \(parts[1])"
        )
        guard challenge.receivedKeyFingerprint != nil else {
            XCTFail("\(environmentName) contains an invalid \(parts[0]) key blob.")
            throw TrustedHostStoreError.invalidHostKey
        }
        return challenge
    }
}
