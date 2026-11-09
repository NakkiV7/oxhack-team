# Spottr Landing Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make the public landing page clearer and more polished while preserving truthful product, account and membership boundaries.

**Architecture:** Keep the existing static Cloudflare asset delivery and local screenshots. Refine the homepage and shared CSS without changing service behaviour or legal facts.

**Tech Stack:** Static HTML, CSS, Node behavioural contracts, Cloudflare Workers.

**Spec:** docs/superpowers/specs/2026-11-09-landing-refinement-design.md

## Global Constraints

The Binding constraints section of the spec applies verbatim. Reuse this checkout on codex/spottr-demo-consolidation. No new worktrees, simulators or browser instances. No unrelated files or provider changes. The controller owns Safari, deployment and live Apple operations. Implementers do not dispatch subagents.

## Review Focus

- Narrow-screen navigation must remain reachable and must not cause overflow.
- Shared CSS changes must preserve readable support, privacy, terms and account pages.
- Concise membership copy must retain eligibility, renewal, account and Apple availability boundaries.
- Screenshot framing must preserve the full real image and its illustrative provenance.
- Keyboard and reduced-motion users must retain all essential navigation and FAQ content.

### Task 1: Refine the public product story and layout

**Files:** Modify landing/public/index.html and landing/public/styles.css. Extend landing/tests-public/public-site.test.mjs only for meaningful visitor-facing contracts. Preserve landing/screenshot-provenance.json and screenshot bytes.

**Interfaces:** Consumes existing public routes and local assets. Produces the same static homepage contract consumed by the Worker assets binding, without new runtime code or dependencies.

- [ ] Inspect the current page and the local TinyTaps/NAKU references. Write a compact design decision note in the task report with palette, type, layout and one deliberate Spottr-specific visual motif.
- [ ] Add a failing behavioural contract for the chosen simplification, such as one concise visible screen disclosure and a single clearly labelled account/membership help journey. Preserve existing material safety and availability assertions, changing brittle wording assertions only where equivalent information remains visible and accessible. Run it and record the failure.
- [ ] Implement the new hierarchy, readable copy, upright real-screen framing, consistent links, responsive layout and restrained interaction feedback. Retain explicit beta, account and membership facts in the relevant FAQ and pricing context.
- [ ] Run node --test landing/tests-public/*.test.mjs, then the web tests and typecheck. Check all local references and image hashes, inspect responsive CSS and shared-page impacts. Do not run historical landing/test_publication.py against the separate obsolete landing/index.html as a claim about the public site.
- [ ] Self-review, commit only task files, and write the implementation report with exact commands/results, red-green evidence, changed files and limitations. Do not deploy or run Safari. The controller will perform rendered desktop/narrow checks and fix through the implementation agent if needed.

### Task 2: Review, render and publish the accepted landing page

**Files:** Controller evidence on the SSD and a concise source evidence note when verified.

**Interfaces:** Consumes Task 1 reviewed commit and existing Cloudflare configuration. Produces verified deployment, actual response/asset readback and Safari visual evidence, while preserving all account Worker secrets and bindings.

- [ ] Obtain a fresh scoped spec/quality review of Task 1 and resolve actionable findings with the same implementer.
- [ ] Run one broad final review of this continuation diff. Preserve all reports.
- [ ] Coordinate Safari before desktop/narrow inspection of real routes and FAQ interaction. No Chrome fallback. Record measured viewport widths and remaining limitations.
- [ ] Verify the Worker service tests and deployment payload before normal authorised deployment. Never rerun old provisioning, migration, email-send or uploader helpers.
- [ ] Verify the actual public response, stylesheet and image hashes and account/legal routes after deployment. Record exact commit/version and distinguish site success from native or provider acceptance.
