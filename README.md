# Ferventio iOS

Ferventio is a native iOS client for Twitch chat, moderation and multi-channel workflows.

The Android client lives in [`0xDive/ferventio-android`](https://github.com/0xDive/ferventio-android), and the server component lives in [`0xDive/ferventio-backend`](https://github.com/0xDive/ferventio-backend).

> **Status:** Early development. The iOS client is not ready for end users yet.

## Requirements

- macOS with Xcode 16 or newer
- XcodeGen
- Git

## Build from source

```bash
git clone https://github.com/0xDive/ferventio-ios.git
cd ferventio-ios
brew install xcodegen
xcodegen generate
open Ferventio.xcodeproj
```

Core packages can be tested without generating the application project:

```bash
swift test --package-path Packages/FerventioCore
```

## Project structure

```text
Ferventio/                  SwiftUI application and features
Packages/FerventioCore/     Domain, networking, persistence and support modules
FerventioTests/             Application-level unit tests
docs/                       Architecture and development documentation
```

See [`docs/architecture.md`](docs/architecture.md) for module boundaries and the backend contract.

Release candidates should also follow [`docs/release-checklist.md`](docs/release-checklist.md), which separates CI-enforced checks from signing, backend deployment, real-device, and App Store Connect gates.

## Security

Do not commit OAuth tokens, backend session tokens, device secrets, APNs private keys or other production credentials. Device and session secrets belong in Keychain.

## License

Ferventio is an independent project and is not affiliated with or endorsed by Twitch Interactive, Inc.
