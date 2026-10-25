# TestFlight provisioning evidence

Verified on 24 October 2026 through the App Store Connect API, for team `952HTWFJX7` and existing App Store Connect app `6826666965`.

Only the Watch bundle's `HEALTHKIT` capability was enabled (`4B853754F7_HEALTHKIT`). The pre-existing `IN_APP_PURCHASE` capability on both bundle IDs was preserved. No other bundle IDs, certificates or provisioning profiles were modified or revoked.

| Target | Bundle ID resource | Explicit bundle identifier | App Store profile name | Profile resource | Profile UUID |
| --- | --- | --- | --- | --- | --- |
| iOS | `NS25862459` | `com.omarchoudhry.spottr` | `Spottr App Store 2026-10-24` | `K6F54KR77Y` | `17fa69d4-2164-4d0d-8243-64772176f1e9` |
| Watch | `4B853754F7` | `com.omarchoudhry.spottr.watchkitapp` | `Spottr Watch App Store 2026-10-24` | `KY5TJM5VYA` | `4dafd63e-f37c-4ba6-a122-d6445d5fd12a` |

Both profiles are `ACTIVE`, type `IOS_APP_STORE`, and expire at **2027-03-11 14:16:30 UTC**. API relationship reads independently confirmed each profile's bundle ID and sole certificate, existing distribution certificate `FNCRJ7ZW8N`.

The downloaded CMS profiles were decoded locally and verified:

- Team and application identifier prefix: `952HTWFJX7`.
- Application identifiers: `952HTWFJX7.com.omarchoudhry.spottr` and `952HTWFJX7.com.omarchoudhry.spottr.watchkitapp`.
- `get-task-allow` is `false`; no `ProvisionedDevices` or enterprise `ProvisionsAllDevices` allowance.
- Each embedded distribution certificate exactly matches the existing certificate's DER bytes. Serial: `660D08AF6315A669D215E2E172E9EA83`; SHA-256: `976254f9b3743ec652e6ccddcd9857ba9416c99d38cd8003147228526168f550`.
- The host has no HealthKit entitlement. The Watch profile permits `com.apple.developer.healthkit = true`. Apple's generated profile also permits background delivery and health-records access; these are profile allowances, and no such extra app entitlements were added to the project.

Private copies and verification records are in ignored `.local/appstore/`, with provisioning files mode `0600`. Both profiles are installed, also `0600`, as `<UUID>.mobileprovision` under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. SHA-256 comparison confirmed all **65** profiles already present in that directory were unchanged; the directory now contains 67 profiles. No signing assets or credentials are committed.

This establishes profile identity and entitlement readiness only. No archive, export, upload, Apple build validation or TestFlight processing was performed in this provisioning step. The SDK privacy/signature validation question remains separate; see [release readiness](release-readiness.md). Project identifiers and committed team-neutral signing settings were not changed.

The API requests follow Apple's [enable capability endpoint](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-bundleidcapabilities), [create profile endpoint](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles), and [App Store Connect profile workflow](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).
