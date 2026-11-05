# Spottr membership foundation — 5 November 2026

Requested launch plans are £10/month with an eligible 14-day introductory free trial, and £200 lifetime. The application displays only actual StoreKit product prices. Local configuration values do not activate products in App Store Connect.

`com.omarchoudhry.spottr.monthly` is an auto-renewable subscription in one membership group. `com.omarchoudhry.spottr.lifetime` is a non-consumable. Lifetime does not cancel an existing subscription; the screen directs subscribers to Apple’s subscription management page.

## Tester offer

`SPOTTRTESTERS` is a requested Apple custom offer code for a free lifetime non-consumable offer. It is **not created, active, or redeemable**. Apple saved the free tester-offer definition, but rejected production custom-code creation because the purchase is not approved and the app is not active. The definition is separate from an issued code. There is no local code comparison, license-key unlock, account-to-membership conversion, free evaluation clock, or persisted paid flag. Redemption uses Apple’s system sheet, and only verified StoreKit transactions grant access.

Apple supports offer codes for non-consumables through the StoreKit redemption APIs. A successful sheet completion alone is insufficient to grant membership. See [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).

## Integration

`ProfileSettingsView` now owns its `MembershipStore()` and presents `MembershipView(store:)` through a labelled navigation row. Both screens clearly state that all features remain available during beta and purchases are optional. No feature is gated by membership in this testing phase. Settings also link to privacy, support, and the optional website account; the account is explicitly separate from the local profile and Apple membership and does not upload workouts or unlock purchases. The abstract faceted gem is bundled as `membership-gem` with no human face.

`MembershipView` calls `load()` on first presentation and when its scene becomes active. Keep the store alive so its transaction listener receives renewals, refunds, approvals, and out-of-app redemption. `hasAccess` and `access` are derived from verified framework results. Never use membership to hide existing history, exports, privacy/data controls, help, or manual tracking. This foundation does not synchronise membership to a website account or Watch.

`MembershipCoordinator(client:now:)` accepts an injected StoreKit boundary for deterministic behavioral checks. The production `AppleMembershipClient` alone translates Apple verification results. Product availability and checkout failure leave verified access intact. Expiration is checked against the current date and a scheduled refresh; foreground refresh is still required after suspension.

The public operations are `load()`, `buy(_ plan: MembershipPlan)`, `restore()`, `refreshEntitlements()` and `completeRedemption(_:)`. Read `offers`, `busy`, `error`, `status`, `hasAccess`, and `access`; `access.mayPurchase(_:)` prevents duplicate ownership and `access.hasOverlappingSubscription` drives the cancellation reminder. `MembershipStore` is the native alias with a production convenience initializer. `MembershipOffer.displayPrice` comes directly from `Product.displayPrice`; eligible day/week free-trial durations come from Apple’s configured offer and eligibility result. Purchase, restore and transaction updates reload eligibility.

## Local StoreKit testing

The project generator now selects `StoreKit/Spottr.storekit` for the host scheme’s Run/Test StoreKit Configuration and bundles it with the native test resources. Native targets use build 19. `SpottrMembership` is an opt-in scheme selecting the StoreKit tests and the membership/guide UI journeys. Run `MembershipStoreKitTests` with the existing shared iPhone simulator, coordinated with other chats. The tests use `SKTestSession` and clear only their local StoreKit test transactions; do not run against normal App Store purchases. These are local framework tests, not genuine purchases.

Exercise monthly trial eligibility and repeat eligibility, lifetime, restore/relaunch, refund/revocation, expiration, Ask to Buy pending/approval/decline, cancellation, simulated failed verification, unavailable products, and overlapping monthly/lifetime ownership. In Xcode’s StoreKit transaction manager, enable billing grace/retry and confirm access through the verified grace deadline and removal after it ends. Use sandbox for the system offer-code sheet and custom-code/storefront behavior; local offer metadata cannot prove `SPOTTRTESTERS` is accepted by Apple.

Core behavior checks use SSD scratch under `/Volumes/Spottr Development/membership-core`. Concurrent agents may stage a plain package copy there to avoid compiling another agent’s temporary red tests; any exclusions must be reported with results.

## Verification recorded during implementation

On 5 November 2026, the staged core package passed 115 XCTest checks plus 222 Swift Testing checks (337 total), including 13 membership checks. The stage excluded only `Tests/Core/ExerciseExpansionTests.swift`, which another agent was developing, and represents the source snapshot at staging time. The initial direct package run encountered that concurrent test’s `Double`/`Int` compilation error. This staged result does not replace a final integrated suite. Logs are `membership-core/full-suite.log` and `membership-core/isolated.log` on the SSD volume. StoreKit JSON parsing and whitespace validation passed.

Observed red/green behavior covers verification and type/product boundaries, lifetime and duplicate prevention, revocation, upgrade and monthly expiry/grace boundaries; offline product failure with retained ownership; cancelled/pending/unverified checkout; matching verified checkout with fresh entitlements; restore without trial extension; redemption completion without ownership; approval/refund updates; visible deadline refresh; used-trial eligibility refresh; and delayed entitlement reads that must not overwrite a newer refund result.

After native integration, the final build and test run on the existing `iPhone` simulator (`BF27AFBA-FF1E-4484-A3BD-42916CEB1170`, iOS 26.5) passed **213 checks**: all 210 `SpottrTests` excluding only `MembershipStoreKitTests`, the two `MembershipFlowTests` journeys, and `OfflineMVPFlowTests`. It used `xcodebuild`, `-jobs 2`, serial tests, and SSD DerivedData. The result is `/Volumes/Spottr Development/Native/TestResults/MembershipFinal-20261105.xcresult`; the log is `Native/membership-final-20261105.log` on that SSD. App bundle metadata confirms version 0.1, build 19. The project was updated semantically from the authorised HEAD baseline to preserve existing UUIDs; its diff is 48 lines and the existing Spottr scheme adds six StoreKit configuration lines. The Watch scheme matches its original bytes.

The four native StoreKit framework cases were executed separately through both the CLI and Xcode IDE on that same simulator. All four encountered StoreKit environment setup failures: `SKInternalErrorDomain Code=3` while saving/clearing configuration and `StoreKitError.notEntitled`; products were unavailable before purchase behavior could be exercised. The IDE run independently passed the membership UI journey. The observations match an [Apple Developer Forums report with staff acknowledgment](https://developer.apple.com/forums/thread/826971) concerning StoreKit Test configuration on iOS 26.5. This is evidence of a setup blocker, not a passing purchase/restore/trial/refund test. No simulator reset, runtime replacement, new simulator, real purchase, or Apple account/product change was attempted. Local framework acceptance and production Apple activation remain open gates.

Actual, unedited beta membership and paused-squat guide screenshots and their receipt are in `docs/media/production-foundation-2026-11-05`. They show build 19 review behavior and are not App Store-approved assets.

## Production gates

- Confirm paid-app agreements, banking/tax setup and IAP capability in App Store Connect without accepting agreements automatically.
- Product identifiers, group, en-GB localizations, GBR availability, exact GBP prices and the two-week introductory offer are saved and verified by API readback below. Validate the actual localized StoreKit products returned on a device; metadata readback does not establish product retrieval or successful purchases.
- Configure the free non-consumable tester offer and requested custom code in App Store Connect; verify Apple accepts the code and confirms a lifetime entitlement.
- Complete native compilation and shared-device behavioral checks, sandbox transactions and redemption, then genuine device purchase/restore acceptance with explicit purchase authority.
- Submit products and the app for Apple review. Upload/build success is separate from product approval and public availability.

Apple’s [current entitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) include subscribed and grace-period subscriptions and exclude refunded/revoked products. The adapter verifies [renewal information](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalinfo) before using a [billing grace deadline](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalinfo/graceperiodexpirationdate). Trial messaging checks StoreKit eligibility and the actual configured introductory free-trial duration; see [introductory offers](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/introductoryoffer).

## App Store Connect metadata readback — 5 November 2026

Apple accepted creation of the requested products and their metadata. Independent GET requests verified the saved values in [the sanitized receipt](membership-apple-readback-2026-11-05.json):

| Product | Apple ID | Saved configuration |
| --- | --- | --- |
| `com.omarchoudhry.spottr.monthly` | `6831175695` | Auto-renewable `ONE_MONTH`, GBP **10.00**, eligible `FREE_TRIAL` for one `TWO_WEEKS` period |
| `com.omarchoudhry.spottr.lifetime` | `6831175389` | `NON_CONSUMABLE`, GBP **200.00** |

The subscription group is **Spottr Membership** (`22549158`). The group and both products have en-GB localizations. Both products are available only in **GBR**, with automatic availability in new territories disabled. Exact requested price points were available; no substitute prices were chosen. Apple uses `UPFRONT` for payment of the complete subscription period: combined with `ONE_MONTH`, this is the normal monthly renewal. Its newer `MONTHLY` plan enum means installments under a 12-month commitment and was not enabled. See [Apple’s subscription pricing guide](https://developer.apple.com/documentation/appstoreconnectapi/configuring-subscription-prices-across-territories).

The introductory offer starts on 5 November 2026 with no configured end date and remains subject to Apple's per-subscription-group customer eligibility. Apple documents that [introductory-offer metadata can take up to one hour to reach sandbox](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/). This work verified API metadata, not StoreKit retrieval, purchase, restore, or redemption.

Both products still report **`MISSING_METADATA`**, and their localizations report `PREPARE_FOR_SUBMISSION`. No product or app was submitted for public App Store review in this operation. Review completion, product approval, and public sale remain separate gates.

Apple created **Spottr Tester Lifetime** offer definition `3b82e808-90d0-4c21-b56a-90bd415644ca`, with a verified GBP **0.00** price in GBR. Readback confirms zero production codes, zero sandbox codes, and no custom codes. The `SPOTTRTESTERS` creation request returned HTTP **409**, including `STATE_ERROR.NON_APPROVED_IAP` and `STATE_ERROR.NON_ACTIVE_APP`. Apple also rejected the requested conservative quantity of 100: its supported custom-code issuance quantities begin at **500**. The complete sanitized denial is in the receipt. No further production-code request was attempted after those explicit state denials. Apple’s [offer-code instructions](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases) require an approved purchase and an app ready for distribution for production custom codes; a saved offer definition does not satisfy those requirements.

Private, header-free request/response receipts and operation scripts are under `.local/production-foundation/apple-products/`. They contain no JWTs or private-key contents. The first subscription-price request was rejected before storefront availability was established; the exact price saved after GBR availability was configured. A subsequent explicit plan-availability request returned a duplicate response because the standard plan already existed. Those responses are preserved alongside the successful writes and final readback. No agreements, banking/tax settings, purchases, native code, project files, website files, or builds were changed by this metadata operation.
