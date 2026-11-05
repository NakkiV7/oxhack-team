# Spottr public website design

5 November 2026. New standalone public output in `landing/public/`; existing landing/history pages are preserved.

## Direction and review

Use paper `#ffffff`, ink `#14233d`, muted `#53627b`, cobalt `#2156ce`, teal `#08786f`, ice `#eef4ff`. Native rounded Avenir Next (local system stack) carries the large left-aligned headlines and readable body copy. No font service, analytics, trackers, or third-party script.

```
Spottr                       Explore | Membership | FAQ | Account
Train a little.               current Skills screenshot
Build from there.             on a cobalt training mat
TestFlight invitation
Offline / camera or manual / optional Watch
Skills & library     |       local coach screenshot
Tracking choices + Watch
Monthly launch plan  |       lifetime launch plan
FAQ / honest testing status / privacy and support
```

The memorable element is the large real skill-path screen sitting on a cobalt field. Keep the rest quiet: broad editorial rows rather than a repeated feature-card grid; no charts, outcome scores, faces, fake trainers, reviews, endorsement badges or invented users. Mobile navigation wraps into labelled links. FAQ uses native details/summary. The page works without JavaScript.

Review against the brief: keep native rounded typography and cobalt/teal, but avoid a generic coloured-word hero and decorative metrics. Actual app content replaces stock fitness imagery. Screenshots show the current local testing candidate, explicitly not the currently distributed TestFlight build. Website account and Apple membership are different things.

## Sources

- Read-only design inspiration: TinyTaps `landing/dist/index.html` and NAKU `docs/landing-concepts/DESIGN.md` / `merged.css`; neither project modified.
- Current screenshots copied unchanged from `docs/media/offline-mvp-2026-11-05/`: `vertical-skill-path.png`, `offline-coach-options.png`, `abstract-trainer-onboarding.png`. These are 5 November simulator captures, not physical-device accuracy evidence. Onboarding is not used publicly because its optional inspired voice-pack label requires separate rights/release review.
- Existing faceless exercise artwork copied unchanged from `wallPushup.imageset` and `inclinePushup.imageset`; the social preview is a custom 1200 x 630 typography/geometric composition rendered locally, without people or generated product UI.
- Existing app icon from `Native/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Genuine existing invitation: `https://testflight.apple.com/join/f3MhePbf`. Availability and build approval are controlled by Apple.
- Public support identity verified from `https://omarchoudhry.co.uk/` on 5 November: Omar Choudhry, `O.Choudhry@leeds.ac.uk`. This confirms an already published contact, not a dedicated Spottr support mailbox or institutional endorsement.

## Content boundaries

£10/month with an eligible 14-day trial and £200 lifetime are proposed UK launch plans. No website checkout, active offer code, entitlement bypass, or public App Store download claim. Apple purchase screens govern actual prices and eligibility. SPOTTRTESTERS is not advertised because activation is unverified.

Core app operation is offline. Website accounts are optional and do not sync workout, video or health information. Account security/storage copy is subject to the root agent's actual implementation review. Privacy retention, operator identity, deletion, rights and release wording need final review before publication. Legal pages describe this testing candidate and its intended service boundaries; they are not an assertion of legal approval.

## Validation

Static behavior tests are written first in `landing/tests-public/public-site.test.mjs` and run with Node's built-in runner. They cover navigable required routes, genuine testing CTA, honest launch plan, account separation, local-only assets/scripts, screenshot provenance, discoverability metadata and baseline accessible markup. All 14 checks pass after the initial expected failures. Screenshot byte comparisons confirm the current source images were copied unchanged. The initial pass did not open a browser or simulator. Later native WebKit verification is recorded below. No deployment was performed by this agent and no physical acceptance is claimed.

## Account wording reconciliation

The root implementation contract supplied during this task specifies 12-hour sessions, 5-minute enrollment/login/Authenticator replacement challenges with at most five attempts, HMAC-hashed IP keys for 10-minute rate-limit buckets, encrypted TOTP seeds, hashed session and recovery tokens, and account retention until deletion. Expired records are cleaned up on account requests and scheduled maintenance; expiry is independent from cleanup. Deletion removes active credentials, MFA/recovery and sessions after fresh two-factor proof within 5 minutes. Privacy/deletion pages reflect that contract. Root must verify it against final code before publication. No arbitrary Cloudflare logs/backup retention period is promised.

Public policy guidance checked on 5 November: Cloudflare privacy policy, ICO right-to-erasure guidance and Apple subscription-cancellation guidance. The latter two direct page reads returned 403/429; official search results confirmed the limited statements used (rights depend on circumstances; Apple subscriptions require separate management). Links are retained in the public pages. This does not replace final legal/consumer-rights review.

## Abstract artwork and catalogue update

Two owner-requested AI-generated, transparent abstract assets are exported as 256-pixel web derivatives in `landing/public/assets/`; originals remain unchanged at their source paths and on the evidence SSD. `privacy-shield.png` comes from `/Users/scsoc/.codex/generated_images/01a1a13d-f18a-72b3-b26c-19f74f16159a/exec-a8d568ab-85ed-48ba-bce4-8fb2e4f2de80.png` (SHA-256 `f101f319ca9222ee51569466623b6563c1f5107827a1226c0bf1ded00fb17a65`). `membership-gem.png` comes from the same directory, `exec-014aa7b0-416e-40c3-a558-0d456653322d.png` (SHA-256 `0a7eed4c799bf89bd596d855b4df6271f0e68f3affbf7616a6b4b4b8641f4617`). They render as small decorative icons in offline/privacy information and proposed membership, without suggesting certification or unlocked paid access. No faces, figures or fabricated product screens were generated.

Source verification of `Shared/Core/ExerciseCatalog.swift` confirms 32 entries, 13 with non-nil camera tracking, and 19 manual/timed entries. Public copy explicitly calls these local beta candidate capabilities and says the public TestFlight build may differ. These counts are catalogue facts, not evidence of camera accuracy or physical validation.

Account UI review confirms the two-factor wording, backup-code limits and separation from local data and Apple purchases. Deletion instructions now match the actual confirmation text and recent-sign-in requirement. A checkbox-width issue caused by shared input styles was reported to the account owner for correction in its separately owned subtree. No account implementation was edited by this agent.

The privacy notice now names UK GDPR Article 6(1)(b) for the account service requested and Article 6(1)(f) for proportionate security/support interests, per the root owner's instruction. ICO contract and legitimate-interests guidance was checked on 5 November. No age restriction was introduced.

## Compact artwork export receipt

Standard export command: `sips -Z 256 SOURCE --out DESTINATION`. No creative edits. Both originals are 1254 x 1254 RGBA PNGs. Both derivatives are 256 x 256 RGBA PNGs; alpha still spans 0 through 255.

| Asset | Original bytes | Original SHA-256 | Web bytes | Web SHA-256 |
| --- | ---: | --- | ---: | --- |
| privacy-shield.png | 1085019 | f101f319ca9222ee51569466623b6563c1f5107827a1226c0bf1ded00fb17a65 | 52983 | 02f852aabffdc9729cd7cc910b19be2f72ac1dbac71368e95bb2309a40eb9195 |
| membership-gem.png | 858659 | 0a7eed4c799bf89bd596d855b4df6271f0e68f3affbf7616a6b4b4b8641f4617 | 43303 | e7b995a2983693bf95ef7386b7154b3ef2f461acc458d7cdf2118af8627548af |

Originals, export metadata and SHA-256 manifest are preserved at `/Volumes/Extreme SSD/Codex Evidence/Spottr/2026-11-05-public-website/`. No original was removed.

## Native WebKit layout and interaction review

Used existing macOS AppKit/WebKit frameworks through a small temporary Swift WKWebView harness. No Chrome, simulator, new browser dependency or local server was used. The initial custom-scheme preview serves only the local public files and a mock unauthenticated 401 response; it proves rendering rather than authentication. The live run loads `https://spottr.omarchoudhry.co.uk/` and its actual public/account routes over HTTPS.

Eight states were checked at desktop 1440 x 1000 or mobile 390 x 844: home, membership, FAQ-open, privacy, account welcome, and Create an account to the username form. All had meaningful intended content, loaded fonts, zero missing images, zero window error/unhandled-rejection events, and zero horizontal overflow. The live run reported a secure context, loaded both abstract icons and displayed the 32-exercise catalogue wording. Opening the first FAQ revealed its answer; choosing Create an account revealed the username form. No registration was submitted and no passkey/MFA or paid entitlement was accepted in this review. Runtime event checks are not a complete browser-console capture.

Evidence, screenshots, JSON DOM measurements and replay scripts are in the SSD folder above, under `local-render/` and `live-before-256px-export/`. Three selected live captures are retained in `docs/media/production-foundation-2026-11-05/`: `website-desktop.png`, `website-mobile.png` and `website-account-mobile.png`. Source screenshots are at 2x display scale; no screenshot content was altered. The initial live evidence predates only the subsequent resolution reduction of the two decorative icons; final derivative live verification is recorded separately below when available.

## Final live derivative verification

After the root owner’s final deployment, all eight native WebKit states were rechecked against the live HTTPS site. The JSON measurements confirm 1440/390 CSS-pixel document widths exactly equal to their viewports, no missing images, no recorded runtime error/unhandled-rejection events, and no overflowing elements. Both decorative assets load at intrinsic 256 x 256 pixels. The FAQ open-state check and account username-form transition pass. The final account mobile screenshot scrolls the username form and its controls into view.

Live PNG bytes were independently downloaded with curl and compared byte-for-byte with the local exports: privacy shield 52,983 bytes and membership gem 43,303 bytes. An initial Python urllib download received HTTP 403; curl and native WebKit both succeeded without changing site configuration. No screenshot/authentication acceptance was inferred from the cryptographic backend smoke tests owned separately by root.

Final evidence is preserved at `/Volumes/Extreme SSD/Codex Evidence/Spottr/2026-11-05-public-website/live-final-256px-export/`; its replay script and the complete `SHA256.json` receipt sit at the evidence root. Every manifest entry was reread and verified. Selected repo captures have been refreshed from this final live run. Public static tests remain 14/14 passing. No deployment, configuration change or commit was performed by this agent.

At this checkpoint, the current source and live username form had no in-form Terms/Privacy acknowledgement statement; this was reported to the account owner. The following before/after regression check records its resolution. No age or consent checkbox was requested or added.

## Account policy-disclosure regression check, before change

A focused native WebKit behavior assertion was written before the account owner changed the client. At the live `/account/` route, select Create an account, then require that the resulting account-content panel contains working Terms and Privacy links and wording that creating an account agrees to Terms and acknowledges Privacy. No age or consent checkbox is required. The unauthenticated single-state run uses a nonpersistent WebKit store and creates no account.

The initial run exits 1, as expected: the username form exists, but the in-form Terms link, Privacy link and acknowledgement all report false. Its screenshot, `checks.json` and replay script are preserved under the evidence root in `account-disclosure-before/` and `spottr-account-disclosure-before.swift`. The account owner was notified to implement and redeploy the change before rerunning the same assertion.

## Account policy-disclosure regression check, after change

After the root owner implemented the wording, rebuilt the account bundle and redeployed it, the same single-state native WebKit assertion exits 0. In-form Terms link, Privacy link and acknowledgement all report true. The username form remains present, secure-context true, document width 390, and runtime-error, missing-image and horizontal-overflow lists remain empty. The screenshot was visually reviewed: the acknowledgement appears alongside the account-creation controls, with readable policy links. No age/consent checkbox or account was created.

Before and after evidence plus replay scripts are preserved at the SSD evidence root under `account-disclosure-before/` and `account-disclosure-after/`. The selected `website-account-mobile.png` repository capture is refreshed from the passing after-state. The final SHA-256 manifest covers all preserved evidence and has been reread and verified.

## Native brand-icon exports

The unchanged native app icon is preserved in its source asset catalogue and `artwork-originals/native-app-icon.png` on the evidence SSD. Standard `sips -Z SIZE SOURCE --out DESTINATION` exports supply a 256px app icon, 180px Apple touch icon, and 64px favicon. Pixel content was resized for delivery only; no creative editing occurred. Export metadata records mode/alpha as well as dimensions, sizes and hashes.

| File | Dimensions | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Native original | 1024 x 1024 | 233849 | 5c54223c59d1147cefae7a1670dcff9c3e6f07cadc9d79f1ecdf18c2e543c255 |
| app-icon.png | 256 x 256 | 24003 | 7907185c804d6c699dba4bfd5c229dda770e7531c751a94b314ffc6e319880e5 |
| apple-touch-icon.png | 180 x 180 | 13258 | 44f5f272097360d44ba3d405426ee36a04a9a0481c41ef2ef108ee29dc168585 |
| favicon.png | 64 x 64 | 2764 | 5b78297075977500ab74319c7b03dc6fb5f101b3757e6a51e1b6a944582df5fa |

The app-icon display dimensions and layout are unchanged. The public static suite now has 14 passing checks, including compact brand-icon export dimensions and byte budgets. Only live dimensions/byte readback is repeated for this derivative-only change.

## Bounded synthetic account-frontend exercise

A separate native WKWebView run loaded the deployed account HTML/JS/CSP while replacing only the fetch and credential boundaries at document start. All `/api/` requests were intercepted by explicit public synthetic fixtures; unexpected API paths would throw. A generated dummy credential object and standard illustrative Authenticator fixture were used. No real account, native passkey, Authenticator enrolment, server MFA acceptance or purchase was created; no screenshots were taken. JSON reports intentionally omit fixture codes and seed values. This is frontend behavior evidence, separate from root’s live cryptographic server smoke tests and any hardware acceptance.

Eight client stages passed at 390px: unauthenticated entry; registration and in-form policy links; Authenticator QR Blob rendering under the live CSP, numeric/one-time-code input and heading focus; ten backup codes with Continue disabled before acknowledgement; Continue enabled after the saved-code checkbox; dashboard recovery/Authenticator/export controls; deletion form rejecting an incorrect confirmation and accepting exact DELETE; and no recorded runtime events or horizontal overflow. Delete was not submitted. The default fixture path visits only session, registration options/verification, enrolment and session again, entirely inside the boundary double.

The initial method-only credential override was insufficient in WKWebView and produced NotAllowedError before credential verification. Replacing the complete `navigator.credentials` boundary resolved the harness limitation; no production fix was inferred from that mock issue. The passing replay script and JSON are preserved as `spottr-synthetic-client.swift` and `synthetic-client-only/checks.json` at the SSD evidence root. No screenshots of Authenticator/recovery information exist in this exercise.

## Final brand-icon readback

Final live HTTP downloads confirm the compact app icon (256px, 24,003 bytes), Apple touch icon (180px, 13,258 bytes) and favicon (64px, 2,764 bytes) match their local derivative bytes and SHA-256 values exactly. `live-brand-icons.json` is preserved on the SSD. The unchanged-layout design did not trigger a repeat of all eight visual states. The final evidence manifest was rebuilt and every entry reread after adding the synthetic frontend result and this readback.
