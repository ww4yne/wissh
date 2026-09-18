# Development

Wissh uses XcodeGen. The checked-in project definition is `project.yml`.

## Requirements

- Xcode with iOS 18 SDK support
- XcodeGen on `PATH`
- Zig and the Ghostty source checkout at the relative path configured in
  [project.yml](../project.yml)

## Build GhosttyKit

Build the XCFramework used by Release and performance profiling with:

```bash
scripts/build_release_ghosttykit.sh
```

Set `GHOSTTY_SOURCE_DIR` when the Ghostty checkout is not the configured
sibling directory. The script always builds `ReleaseFast`, and Wissh Release
builds independently query the resulting XCFramework and fail on any other
mode. The app also validates the selected iOS slice at launch.

## Generate Project

```bash
xcodegen generate
```

Run this after changing [project.yml](../project.yml).

## Build

```bash
xcodebuild build \
  -project Wissh.xcodeproj \
  -scheme Wissh \
  -destination 'generic/platform=iOS Simulator'
```

## Test

```bash
xcodebuild test \
  -project Wissh.xcodeproj \
  -scheme Wissh \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

## Local Files

Keep developer-only notes, live validation configuration, and machine-specific
working files in `.local/`. The directory is ignored by Git.

Do not commit local credentials, live SSH host details, machine-specific result
bundles, or generated build products.

## Debug Seeding

Debug builds can seed one saved connection from launch environment variables.

```bash
WISSH_DEBUG_SEED_CONNECTION=1
WISSH_DEBUG_SERVER_NAME="Example Server"
WISSH_DEBUG_SERVER_HOST="server.example.com"
WISSH_DEBUG_SERVER_PORT=22
WISSH_DEBUG_SERVER_USERNAME="demo"
WISSH_DEBUG_SERVER_PASSWORD="<password>"
WISSH_DEBUG_TMUX_SESSION="base"
```

Live validation should stay opt-in and local. Keep any real host, username,
password, or test-control files out of the tracked repository.

When running generated live UI tests, use the tracked host-side wrapper so the
app runs with ephemeral debug storage, the test records the exact disposable
`remux-latency-*` tmux sessions it creates, and the wrapper removes only those
allowlisted sessions after the run:

```bash
scripts/wissh_live_ui_test_with_cleanup.sh \
  --only-testing WisshUITests/WisshAppUITests/testLiveSSHTmuxActionCycleWhenConfigured
```
