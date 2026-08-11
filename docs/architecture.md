# Architecture

Ferventio iOS is a native SwiftUI application that reuses the Ferventio backend contract while connecting directly to Twitch for chat and Helix traffic after obtaining a short-lived Twitch access lease.

## Module boundaries

```text
Ferventio                  SwiftUI app shell, feature composition and navigation
FerventioDomain            Platform-independent models and product rules
FerventioNetworking        Backend and Twitch HTTP clients
FerventioPersistence       Local history, drafts and settings persistence
FerventioSupport           Keychain and other platform support utilities
```

The application target may depend on every core module. Core modules must not depend on the application target or SwiftUI.

## State ownership

Long-lived services are owned by the application environment. Feature-specific observable state belongs to feature stores rather than views. Views should render prepared state and avoid parsing chat payloads in `body`.

## Backend contract

The iOS client follows the same mobile authentication and Twitch token lease model as Android:

1. Create a stable installation identifier and device secret locally.
2. Start mobile OAuth through the Ferventio backend.
3. Complete the backend handoff after the browser callback.
4. Store the backend session securely in Keychain.
5. Request short-lived Twitch access leases from the backend.
6. Use Twitch Chat and Helix directly from the device.

Device credentials, backend session tokens and Twitch access tokens must never be written to logs or synced settings.

## Project generation

`project.yml` is the source of truth for the Xcode project. Run:

```bash
brew install xcodegen
xcodegen generate
open Ferventio.xcodeproj
```

Generated Xcode project files are intentionally ignored by Git.
