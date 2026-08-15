# TestFlight release checklist

This checklist separates repository checks that CI can enforce from deployment and App Store Connect work that requires signed builds, production credentials, or account access.

## Automated repository gates

The `iOS CI` workflow must pass on the release candidate commit.

- Core Swift package tests pass.
- `PrivacyInfo.xcprivacy` is syntactically valid and declares the app-only `UserDefaults` required reason.
- The 1024×1024 AppIcon asset exists, is opaque, and is selected by the Release target.
- XcodeGen produces the project successfully.
- Release settings resolve to bundle ID `io.ferventio.ios`, the expected marketing version, and the expected build number.
- Debug and generic-device Release builds succeed with signing disabled.
- An unsigned generic-device archive succeeds.
- The archived app contains `PrivacyInfo.xcprivacy` at the app-bundle root.
- The archived `Info.plist` contains the expected bundle/version metadata and `ITSAppUsesNonExemptEncryption = false`.
- Simulator application tests pass.

## Apple Developer signing

Before uploading a build:

- Create or verify the App ID for `io.ferventio.ios`.
- Enable the Push Notifications capability for the App ID.
- Use an App Store distribution signing configuration that includes Push Notifications.
- Inspect the signed archive entitlements and confirm the distribution build has the expected APNs environment.
- Increment `CURRENT_PROJECT_VERSION` for every uploaded build. Keep `MARKETING_VERSION` aligned with the App Store Connect version.

The repository intentionally does not contain certificates, provisioning profiles, or APNs private keys.

## Backend production configuration

Before real-device validation, deploy the backend contracts already merged on `ferventio-backend/main` and verify runtime configuration:

- `AUTH_ALLOWED_APP_SCHEMES` contains `io.ferventio.ios` and `io.ferventio.ios.debug` where appropriate.
- APNs delivery is enabled for the environment being tested.
- APNs team ID, key ID, private key, bundle ID, and production/sandbox environment match the signed app.
- `APNS_BUNDLE_ID` is `io.ferventio.ios` for the production/TestFlight build.
- The backend settings-sync endpoints accept portable settings backup format v2.

Do not add the `remote-notification` background mode unless the production notification contract starts emitting silent/background notifications that the app actually consumes.

## Real-device smoke test

Run this on a signed physical-device build before the first external TestFlight build and again before App Store submission:

1. Fresh-install the app and complete backend/Twitch OAuth through the production callback scheme.
2. Confirm the authenticated Twitch identity and initial workspace load correctly.
3. Connect to chat, receive live EventSub messages, send a message, reply, and reopen the app after backgrounding.
4. Exercise BTTV/FFZ/7TV emotes, overlays, modifiers, links, badges, and Dynamic Type at an accessibility text size.
5. Verify local history paging preserves scroll position while new live messages arrive.
6. Verify Nuke preview before execution and the User Card moderation actions with an account that has the required scopes.
7. Verify Poll/Prediction hydration and management with an eligible broadcaster account.
8. Enable notifications, confirm APNs registration reaches the backend, and send a backend self-test notification.
9. Tap a notification for an existing workspace and confirm it selects that workspace.
10. Tap a notification for a channel that is not open and confirm the app opens/selects that workspace, including from a cold launch.
11. Upload portable settings v2 to cloud sync, download it on another installation, exercise a revision conflict, inspect history, and restore an older revision.
12. Sign out and verify session/device secrets are removed from app state while no production credential is written to logs or files.

## App Store Connect metadata

Complete these account-side items before submission:

- Create the iOS app record with bundle ID `io.ferventio.ios`.
- Provide the required Privacy Policy URL.
- Complete App Privacy answers for the app and integrated third-party services.
- Confirm export-compliance answers are consistent with `ITSAppUsesNonExemptEncryption = false` and the actual linked code.
- Provide category, description, keywords, support URL, screenshots, age rating, review contact information, and any review notes needed for Twitch authentication/moderation behavior.
- Attach the correct uploaded build to the TestFlight/App Store version and verify processing completes without privacy-manifest or entitlement warnings.

Apple references:

- https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution
- https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption
- https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
