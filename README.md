# Wissh

Wissh is an iPhone SSH multiplexer client with first-class ProxyJump support.
It supports tmux on POSIX hosts and psmux on Windows hosts.

The project starts from the open-source
[Remux](https://github.com/h3nock/remux) iOS tmux client and retains its
Ghostty terminal, Citadel SSH transport, tmux control mode, SFTP, file
preview, and localhost preview foundations.

## Status

Wissh is in early development. The first milestone establishes the Wissh
product identity before adding a single-server ProxyJump experience.

## Product direction

- One visible server profile for the final SSH target.
- An optional jump-host transport embedded in that profile.
- Independent host-key verification for the jump host and target host.
- One client identity may be reused for both hops.
- No private key is copied to or stored on the jump host.
- Direct SSH remains available for servers that do not require a jump host.
- OpenSSH private keys and unencrypted legacy PKCS#1 RSA PEM keys can be imported.
- Server profiles can select tmux or Windows-native psmux control mode.
- Native tmux workspace, SFTP, file preview, and localhost preview behavior
  remains compatible with upstream Remux where possible.

See [the development plan](docs/development-plan.md) for scope, architecture,
milestones, and acceptance criteria.

## Building the imported baseline

Requirements:

- Xcode with iOS 18 SDK support
- XcodeGen

Fetch the prebuilt GhosttyKit framework:

```bash
scripts/fetch_ghosttykit.sh
```

Generate the project and build:

```bash
xcodegen generate

xcodebuild build \
  -project Wissh.xcodeproj \
  -scheme Wissh \
  -destination 'generic/platform=iOS Simulator'
```

Run the tests:

```bash
xcodebuild test \
  -project Wissh.xcodeproj \
  -scheme Wissh \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

The app, target, and scheme are named `Wissh`.

## Upstream and license

Wissh is based on Remux and is distributed under the MIT License. See
[UPSTREAM.md](UPSTREAM.md) and [LICENSE](LICENSE).
