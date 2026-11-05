# Spottr App Store preparation

These URLs are deployed and can be used when preparing the listing. This document does not assert Apple approval or that the newest local candidate is on TestFlight.

| Listing field | URL |
| --- | --- |
| Marketing | https://spottr.omarchoudhry.co.uk/ |
| Support | https://spottr.omarchoudhry.co.uk/support/ |
| Privacy policy | https://spottr.omarchoudhry.co.uk/privacy/ |
| Terms | https://spottr.omarchoudhry.co.uk/terms/ |
| Account deletion help | https://spottr.omarchoudhry.co.uk/delete-account/ |

## Listing copy draft

**Subtitle:** A little support. Every session.

Build a training routine at your own pace with Spottr. Choose an exercise, follow clear stick-figure guides, and record the work you complete. Supported squat and push-up styles use your iPhone camera to estimate visible movement and count reps on device. Other movements offer manual or timed logging.

Set a comfortable starting point during onboarding and follow a simple skill path. Choose your coach's voice and style, review summaries calculated from your recorded training, and keep your local history available offline. Optional Apple Watch features bring workout controls and available heart-rate context to your wrist, with your permission.

Camera estimates can miss movement, especially with poor framing or visibility. Spottr is a general fitness tool. It does not diagnose conditions, verify clinical recovery or replace individual advice from a qualified professional.

## Review notes draft

Core training does not require an account or online AI service. Complete the beginning onboarding, open Today or the exercise library, and select manual logging to try a session without camera access. Camera-supported exercises are labelled; a real side-on view of the relevant joints is required. Saved reports identify manual and camera sources.

Profile settings expose privacy, support, local data controls and membership. All beta training features remain available without a purchase. The optional website account uses a passkey and Authenticator, has its own deletion controls, and does not sync local training or grant Apple entitlements.

Before an App Store submission, replace beta-specific listing text with the actual released access policy and complete the Apple product configuration below. Do not submit unavailable purchase options as a finished commercial experience.

## Apple metadata saved

Exact requested products, GBP prices, two-week introductory offer and GBR-only availability are saved and independently verified. Both products remain MISSING_METADATA. The tester offer definition exists, but Apple rejected custom code creation because the app and purchase are unapproved. See [Apple readback](membership-apple-readback-2026-11-05.json).

## Apple configuration and acceptance still required

- Confirm the existing Spottr record, IAP capability, current agreements, territories, tax and banking status. Do not accept agreements automatically.
- Complete review metadata for `com.omarchoudhry.spottr.monthly` and validate actual StoreKit retrieval and eligibility. Its GBP10 monthly price and two-week free introductory offer are saved.
- Complete review metadata for the saved GBP200 non-consumable `com.omarchoudhry.spottr.lifetime` and verify actual StoreKit retrieval.
- After app and IAP approval, create and verify custom code `SPOTTRTESTERS` against the saved free lifetime offer. Apple has rejected preapproval creation; no code exists. Do not substitute a local string-based unlock.
- Verify purchase, cancellation, pending approval, renewal, grace/expiry, refund, restore, overlapping monthly/lifetime ownership and system offer-code redemption in sandbox and on a real device.
- Confirm actual data handling for the submitted binary and associated account service before completing privacy labels. Inspect vendor SDKs and required-reason manifests. Published web policies do not automatically determine the App Store labels.
- Capture final screenshots at supported listing sizes using existing simulators. The current screenshots are real local-candidate captures; website framing is marketing artwork, not evidence of a public release.
- Finish physical iPhone/Watch counting, tracking-recovery, audio and accessibility acceptance. Keep expected versus recorded counts and observation coverage.

No paid Apple purchase, product activation, tester-code activation, public App Store submission or clinical validation is established by this change.
