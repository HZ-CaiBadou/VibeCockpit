# VibeCockpit

VibeCockpit is a native macOS menu bar app for monitoring Codex usage and keeping a Codex account warm with lightweight scheduled wakeups.

## Features

- Codex usage monitoring in the macOS menu bar
- Remaining-quota display for primary and secondary usage windows
- Codex OAuth account login and account switching
- Secure credential storage through macOS Keychain
- Optional automatic wakeup while the menu bar app is running
- Daily wakeup time slots, quota-reset wakeup, manual wakeup test, and wakeup history
- Launch at Login support
- Native SwiftUI settings and popover UI

## Automatic Wakeup

The first VibeCockpit wakeup implementation is intentionally local and simple:

- Runs only while VibeCockpit is open
- Uses the current Codex account
- Sends a lightweight official Codex Responses request
- Default prompt asks for an `OK` reply
- Success does not notify; failure conditions can notify

This is not a system daemon or LaunchAgent. If the app is closed, wakeup scheduling stops.

## Security

- Account credentials are stored locally in macOS Keychain.
- The repository does not include user tokens, session cookies, refresh tokens, certificates, or private keys.
- Generated apps, DMGs, build folders, local agent state, and signing materials are ignored by Git.
- Sparkle automatic update checks are disabled for this fork until a VibeCockpit-owned update feed is configured.

## Build

The Xcode project remains the main app build entry:

```sh
open VibeCockpit.xcodeproj
```

The SwiftPM manifest is kept lightweight for pure-function checks:

```sh
swift run VibeCockpitCoreChecks
```

## Repository

GitHub: [HZ-CaiBadou/VibeCockpit](https://github.com/HZ-CaiBadou/VibeCockpit)

## License

MIT License. See [LICENSE](LICENSE).
