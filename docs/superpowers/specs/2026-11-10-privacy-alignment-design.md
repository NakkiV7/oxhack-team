# Align Spottr privacy declarations

The first App Store release needs the package manifest and source-backed App Privacy answers to describe the same actual collection. This is a small configuration/test correction before freezing1.0(26), not a new data collection feature.

Read the preserved source evidence in `.superpowers/sdd/2026-11-10-app-store-membership/privacy-final-answers-addendum.md`. Saved adult cloud programme preferences restore into the active local profile and customise future exercise plans. Apple defines Product Personalization by the use, not by where the recommendation algorithm executes. Requested support emails can retain issue contents and sender identity; all optional-disclosure conditions were not established. These findings justify two precise iOS manifest additions.

## Required changes

In Native/iOS/PrivacyInfo.xcprivacy add `NSPrivacyCollectedDataTypePurposeProductPersonalization` to the existing Fitness purpose set. It must contain exactly App Functionality, Product Personalization and Analytics. Add Customer Support with App Functionality only, linked true and tracking false.

The resulting exact six data types and purposes are

| Type suffix | Purpose suffixes |
| --- | --- |
| EmailAddress | AppFunctionality |
| UserID | AppFunctionality |
| DeviceID | AppFunctionality, Analytics |
| Fitness | AppFunctionality, ProductPersonalization, Analytics |
| ProductInteraction | Analytics |
| CustomerSupport | AppFunctionality |

Each uses Apple's full `NSPrivacyCollectedDataType` / `NSPrivacyCollectedDataTypePurpose` prefixes. Every type is linked true and tracking false; global NSPrivacyTracking stays false. Preserve required API categories/reasons exactly. Do not add Health, video, audio, location, advertising or purchase-history collection, change consent controls, enable analytics or add a support upload endpoint. The Watch manifest remains unchanged; its direct processing is on user devices and this correction concerns the iPhone/account flows.

Update the existing native service contract to parse the actual plist and validate the six-category/per-category purpose contract, so a purpose mistakenly added to another type cannot pass. Update the existing hosted ReleasePackagingTests helper/host test, which still incorrectly assumes the iOS manifest contains only API reasons and no collection declarations. The helper must still validate API reasons, the host test must assert the actual six-category no-tracking contract, and the Watch test must retain its unchanged specific reason expectations. No weakened assertion or broad test skip.

## Boundaries and verification

Only Native/iOS/PrivacyInfo.xcprivacy, landing/tests-public/native-service-contract.test.mjs and Tests/iOS/ReleasePackagingTests.swift are task-owned. Actual configuration RED before manifest edit using the updated source contract, then GREEN and plutil lint. A focused hosted packaged-resource test may run once under controller lease with jobs1/driver1/backend1, scrubbed environment, SSD outputs and exact existing BF27 only. No broad native suite, new simulator/runtime/target/worktree, reset/erase/uninstall, provider or credential operation. Preserve source audio/model/build17/Vendor/all old artifacts.

All previous onboarding/account and runtime behavior stays as reviewed. App Privacy UI remains separately unsaved/unpublished and must eventually use the source-backed six-category matrix with the same purposes. No legal certification, review submission or public release is performed by this task.

Primary Apple definitions checked10November2026
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
- https://developer.apple.com/app-store/app-privacy-details/
