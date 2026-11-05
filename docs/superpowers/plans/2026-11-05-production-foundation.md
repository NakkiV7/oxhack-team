# Spottr Production Foundation Implementation Plan

> Native execution with independent exercise, commerce and website workers. Root owns account backend and integration. The membership worker was explicitly assigned sole coordinated use of the existing simulator and project references during integration.

**Goal:** Extend the offline app and produce a testable Cloudflare account/site and verified purchase foundation.
**Architecture:** Pure Swift exercise/entitlement policies drive native views. A static public site is served with a Worker routing only account APIs to D1. Passkeys and TOTP establish sessions; iOS membership remains StoreKit-owned.
**Tech stack:** Swift/SwiftUI/StoreKit 2, TypeScript, Workers Static Assets, D1, Web Crypto, SimpleWebAuthn.
**Spec:** docs/superpowers/specs/2026-11-05-production-foundation-design.md

## Constraints
Faceless artwork; no Chrome; reuse existing sims only; preserve build 17/18 and active dependencies; SSD scratch; no real purchases, new paid plans, or training runs.

## Review focus
- Occlusion/slow/paused movement cannot fabricate, double-count or erase reps.
- Pending/unverified/refunded/expired transactions cannot grant membership.
- Registration, passkey-only and TOTP setup cannot issue a full session early.
- Replayed challenge/TOTP/backup tokens, races and expired sessions fail closed.
- Account deletion and recovery require fresh factors and remove/revoke the correct data.

## Tasks
- [x] Exercises: add tests first, variation rules/artwork/catalogue/instructions, red-green core checks; no project writes or simulator use.
- [x] Membership: pure verified-entitlement tests, StoreKit adapter, localized paywall/restore/offer code UI, local StoreKit configuration; no actual paid purchase.
- [x] Landing: existing TinyTaps/Naku patterns, public HTML/CSS/assets/screenshots and accurate legal/support routes; static route/content tests.
- [x] Accounts: schema/crypto/WebAuthn state machine tests first, atomic D1 adapter, rate limits/headers/session/CSRF/deletion/recovery, complete account frontend.
- [x] Infrastructure: inspect existing Cloudflare domain/account/site, preserve rollback, create only Spottr resources, deploy free-service-compatible configuration; live checks.
- [x] Integration: phone settings/legal/member entry points, native/core/Watch tests, existing-device screenshot capture, signed candidate on SSD.
- [x] Review: independent authentication and source review, repair findings, receipts/feature backlog, clear separation of tested versus pending production activation.

## Final checkpoint

Build 19 passed Apple validation and upload and is IN_BETA_TESTING internally and externally. Four local StoreKit framework cases remain setup-blocked; paid activation and real-device acceptance are not claimed. See docs/evidence/production-foundation-2026-11-05.md.
