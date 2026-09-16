# Wissh development plan

## Goal

Build an iPhone-first SSH and tmux client that presents a jump-host connection
as one server while preserving end-to-end SSH authentication and independent
host-key verification for both hops.

The initial deployment target is a Windows 365 Cloud PC reached through a
constrained SSH bastion:

```text
Wissh
  -> SSH to jump host
  -> direct-tcpip channel to a loopback reverse listener
  -> SSH to the Cloud PC
  -> WSL tmux workspace
```

The jump host forwards opaque SSH bytes. It does not receive the target
private key, terminate the inner SSH connection, or authenticate as the
Cloud PC user.

## Baseline

The initial source import is Remux commit
`f9be1b34957becc3c1cacd865ca1a16cb1bb823d`.

Reusable foundations already present in the baseline:

- SwiftUI iPhone application targeting iOS 18.
- Ghostty terminal integration.
- Citadel and SwiftNIO SSH transport.
- SSH identity storage in the iOS Keychain.
- Trusted host-key storage and trust challenges.
- tmux control-mode session, window, and pane support.
- SFTP, remote file preview, upload, and localhost preview.
- Reusable authenticated SSH roots and direct-TCPIP channels.

The pinned Citadel dependency already exposes `SSHClient.jump(to:)`, implemented
as a nested SSH connection over a `direct-tcpip` channel. ProxyJump therefore
does not require a new SSH implementation.

## Product identity

- Product name: `Wissh`
- Bundle identifier: `app.wissh.ios`
- Platform: iPhone, iOS 18 or later
- Icon direction: Windows-style tile with a terminal prompt
- Upstream license: MIT, with the original Remux notice retained

The new icon must be original artwork and must not reuse the Remux icon or
other third-party product marks.

## Connection model

Extend a saved server with an optional jump configuration:

```text
SavedServer
  target host
  target port
  target username
  target identity
  optional JumpHost
    host
    port
    username
    identity
```

The first release permits the same identity to be selected for both hops. The
model must not require identity duplication, but it must allow separate
identities for users who need independent rotation or revocation.

Each hop has its own trusted host identity. Trust records must be keyed so that
accepting or replacing the jump-host key never accepts or replaces the target
host key.

## Transport design

1. Resolve the jump-host identity and target identity from Keychain-backed
   credentials.
2. Establish and authenticate the outer SSH root.
3. Verify the jump-host key before opening any forwarding channel.
4. Open a constrained `direct-tcpip` channel to the configured target host and
   port as resolved from the jump host.
5. Establish the inner SSH client on that channel.
6. Verify the target host key independently.
7. Expose the inner authenticated root to existing tmux, exec, SFTP, upload,
   file-preview, and localhost-forward features.
8. Close inner sessions and forwarding channels before releasing the outer
   root.

For the Windows 365 prototype, the target is `127.0.0.1:<assigned-port>` from
the jump host's perspective. The UI must not generalize this into an
unrestricted port-forwarding feature.

## Milestones

### M1: Establish the Wissh product

- Rename the app, target, scheme, module, tests, and visible strings.
- Set `PRODUCT_BUNDLE_IDENTIFIER` to `app.wissh.ios`.
- Replace the icon and launch assets with original Wissh artwork.
- Update privacy, acknowledgments, build instructions, and metadata.
- Keep the imported baseline buildable throughout the rename.

Acceptance criteria:

- The generated Xcode project contains no executable target named Remux.
- The installed app is displayed as Wissh.
- No upstream icon or TestFlight link remains in product surfaces.
- Remux attribution and the MIT license remain in the repository.

### M2: Add jump-host profiles

- Add a codable `JumpHost` model and migration-safe optional field.
- Add jump-host fields to create/edit server flows.
- Reuse an existing SSH identity or select a distinct identity.
- Display one server in the library; do not expose the jump host as a separate
  top-level server.
- Validate host, port, username, and credential references before saving.

Acceptance criteria:

- Existing direct server profiles load without migration errors.
- A user can configure a target and jump host in one server form.
- The server library shows only the final target profile.

### M3: Implement nested SSH transport

- Add an outer-root pool keyed by jump endpoint, username, and credential
  fingerprint.
- Open the inner SSH root through Citadel/NIOSSH `direct-tcpip`.
- Integrate independent host-key trust challenges for both hops.
- Propagate authentication, forwarding, host-key, timeout, and disconnect
  errors without success-shaped fallbacks.
- Preserve serialized channel lifecycle and bounded connection timeouts.

Acceptance criteria:

- Direct SSH behavior remains unchanged.
- ProxyJump connects through a constrained OpenSSH bastion.
- Rejection of either host key stops the connection.
- A changed jump key and a changed target key are reported distinctly.
- The client private key never leaves the device.

### M4: Route all existing features through the inner root

- tmux discovery and attach/create.
- Interactive terminal control channel.
- SFTP and file upload.
- Static file preview.
- Remote localhost preview through nested direct-TCPIP.
- SSH public-key installation where explicitly supported.

Acceptance criteria:

- Each feature uses the final target root rather than accidentally executing
  on the jump host.
- Closing a workspace releases its inner channels and outer-root lease.
- Multiple panes and previews do not create unbounded outer connections.

### M5: Windows 365 connection preset

- Add an optional preset for the constrained Alpha SSH gateway.
- Default jump target to `127.0.0.1` with an assigned reverse-listener port.
- Support one client Ed25519 identity for both client authentication hops.
- Document Cloud PC public-key enrollment and host-key pinning.
- Launch or attach a WSL tmux session without weakening the target SSH policy.

Acceptance criteria:

- The user creates one visible Cloud PC server profile.
- No public Cloud PC inbound port is required.
- The Alpha reverse listener remains loopback-only.
- The gateway account can open only the assigned target endpoint.

### M6: Release readiness

- Add unit tests for profile migration, root keys, trust identities, and error
  classification.
- Add integration tests using two local OpenSSH servers and a constrained
  direct-TCPIP policy.
- Test network loss, app backgrounding, key rotation, tunnel restart, and
  target unavailability.
- Complete App Store privacy metadata and export-compliance review.
- Document upstream synchronization and conflict-resolution policy.

## Security requirements

- Never disable host-key validation or ship an accept-all validator.
- Never copy target private keys to the jump host.
- Never store passwords or private keys outside Keychain-backed storage.
- Never treat successful outer authentication as target authorization.
- Bind cached roots to endpoint, username, and credential fingerprint.
- Keep jump and target trust records independent.
- Reject invalid ports, empty endpoints, unsupported key formats, and stale
  credential references.
- Do not expose arbitrary forwarding as a user-facing capability in the
  Windows 365 preset.
- Do not log private keys, passwords, terminal content, or complete
  authentication material.

## Upstream strategy

Maintain Wissh as a focused fork:

- Keep an `upstream` remote for `h3nock/remux`.
- Prefer isolated additions over broad rewrites.
- Submit generally useful fixes upstream where practical.
- Record the upstream commit used for every synchronization.
- Preserve upstream tests and add Wissh-specific coverage alongside them.

The first implementation slice is M1 followed by the profile model and
host-key identity work from M2. Nested transport work starts only after the
persistence and trust boundaries are explicit.
