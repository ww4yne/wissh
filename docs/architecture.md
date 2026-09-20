# Architecture

Remux keeps the iOS app shell separate from the tmux transport and the
Ghostty terminal runtime.

SwiftUI owns presentation and user intent. The transport layer moves bytes.
Ghostty renders terminal surfaces. Persistence is hidden behind repository and
store interfaces.

## Main Types

- `RemuxRootModel`: top-level app coordinator for the library, setup flow,
  terminal sessions, and settings.
- `ConnectionProfileRepository`: persisted saved servers and multiplexer workspaces.
- `SSHCredentialStore`: saved SSH credentials, backed by Keychain in live builds.
- `TrustedHostStore`: SSH host identity persistence and validation.
- `TerminalSettingsRepository`: persisted terminal appearance settings.
- `TmuxControlTransport`: byte-stream transport boundary for a bare tmux or
  psmux control-mode exec channel.
- `TmuxSessionController`: wrapper around Ghostty's tmux session API. Ghostty
  owns command generation, control-mode parsing, reconciliation, and pane
  projection.
- `TmuxScreenModel`: terminal screen coordinator that connects a target,
  transport, and Ghostty tmux session runtime.
- `GhosttyRuntimeSurfaceRegistry`: tracks runtime-created Ghostty surfaces and
  focused pane state.

## Runtime Flow

```text
Saved server + workspace
-> TmuxConnectionTarget
-> TmuxScreenModel
-> TmuxSessionController
-> TmuxControlTransport
-> SSH exec channel running tmux/psmux control mode
-> Ghostty tmux session callbacks
-> Ghostty pane projections
-> SwiftUI/UIKit shell
```

Transport code does not import UI concepts. Ghostty surface views do not read
repositories directly.

## Persistence

Live builds store app data under the app's application-support root:

- saved servers in JSON
- saved workspaces in JSON
- terminal settings in JSON
- SSH credentials (password or private key) in Keychain
- trusted host identities in the trusted-host store

UI tests use in-memory repositories and deterministic transports when possible.

## Transport

SSH is the implemented transport. Unsupported transports fail explicitly
instead of silently falling back to SSH.

Authentication is per-identity and the setup UI supports passwords and private
keys. Private-key import accepts OpenSSH keys and converts unencrypted legacy
PKCS#1 RSA PEM keys into the equivalent OpenSSH container before Keychain
storage. Existing profiles that used SSH's `none` authentication remain
decodable for compatibility, but the setup UI does not offer that method for
new or edited profiles.

WireGuard only supplies a network path. Ordinary SSH servers reached through
WireGuard still require whatever password or key authentication they normally
use.

Server profiles select tmux for POSIX hosts or psmux for Windows hosts. tmux
commands run through `/bin/sh`; psmux commands run through PowerShell with a
UTF-16LE `-EncodedCommand`, keeping executable and session values out of shell
syntax.

The transport boundary is small: prepare/start, write outbound bytes, stream
inbound bytes, report liveness when available, and close. It deliberately does
not allocate a PTY or inject tmux commands. Client size, tmux command
semantics, control-mode parsing, reconciliation, and pane materialization stay
inside Ghostty's tmux session API; terminal rendering stays out of generic app
views.
