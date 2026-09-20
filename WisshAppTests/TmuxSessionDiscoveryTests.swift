import Foundation
import XCTest
@testable import Wissh

final class TmuxSessionDiscoveryTests: XCTestCase {
    func testListCommandKeepsConfiguredExecutableOutOfLoginShellSyntax() {
        let executable = "/home/owner's tools/tmux; touch pwned"

        let command = SSHTmuxControlCommandBuilder.listSessionsCommand(
            tmuxExecutable: executable
        )

        XCTAssertTrue(command.hasPrefix("exec /bin/sh -c '"))
        XCTAssertTrue(command.contains("LC_ALL=C; export LC_ALL"))
        XCTAssertTrue(command.contains("exec \"$resolved\" list-sessions -F \"#{session_name}\""))
        XCTAssertFalse(command.contains(executable))
        XCTAssertFalse(command.contains("touch pwned"))
    }

    func testPsmuxListCommandUsesEncodedPowerShell() throws {
        let executable = #"C:\Program Files\psmux\psmux.exe"#

        let command = SSHTmuxControlCommandBuilder.listSessionsCommand(
            multiplexer: .psmux,
            tmuxExecutable: executable
        )

        let encoded = try XCTUnwrap(command.split(separator: " ").last.map(String.init))
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        let script = try XCTUnwrap(String(data: data, encoding: .utf16LittleEndian))
        XCTAssertFalse(command.contains(executable))
        XCTAssertFalse(script.contains(executable))
        XCTAssertTrue(script.contains("& $resolved list-sessions -F '#{session_name}'"))
    }

    func testParserPreservesWhitespaceDeduplicatesAndAcceptsCRLF() throws {
        let names = try TmuxSessionDiscovery.parseSessionNames(
            Data("main\r\n  spaced  \nmain\n\nops\r\n".utf8)
        )

        XCTAssertEqual(names, ["main", "  spaced  ", "ops"])
    }

    func testParserRejectsInvalidUTF8() {
        XCTAssertThrowsError(
            try TmuxSessionDiscovery.parseSessionNames(Data([0xFF]))
        ) {
            XCTAssertEqual($0 as? TmuxSessionDiscoveryError, .invalidUTF8)
        }
    }

    func testMissingTmuxServerReturnsNoSessionsForSupportedMessages() throws {
        let messages = [
            "no server running on /private/tmp/tmux-501/default\n",
            "error connecting to /private/tmp/tmux-501/default (No such file or directory)\n",
        ]

        for message in messages {
            let names = try TmuxSessionDiscovery.sessionNames(
                from: result(exitStatus: 1, stderr: message)
            )
            XCTAssertEqual(names, [])
        }
    }

    func testGenuineRemoteFailureStillThrows() {
        XCTAssertThrowsError(
            try TmuxSessionDiscovery.sessionNames(
                from: result(exitStatus: 126, stderr: "permission denied\n")
            )
        ) {
            XCTAssertEqual(
                $0 as? TmuxSessionDiscoveryError,
                .remoteExit(status: 126, stderr: "permission denied\n")
            )
        }
    }

    private func result(
        exitStatus: Int,
        stdout: String = "",
        stderr: String = ""
    ) -> RemuxSSHExecResult {
        RemuxSSHExecResult(
            exitStatus: exitStatus,
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8)
        )
    }
}
