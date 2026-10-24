# Spottr landing page

This is Misha's static landing page, with availability, accessibility and copy corrections. It needs no build step or service credentials.

From the repository root:

```bash
python3 -m http.server 8149 --bind 127.0.0.1 --directory landing
```

Open `http://127.0.0.1:8149/`. Any static host can serve the contents of `landing/`; include `assets/`. No other repository folders or `.env` files need to be served.

The page displays two actual white iPhone/Watch simulator captures: `assets/today-simulator.jpg` and `assets/watch-simulator.jpg`. The caption identifies them as simulator captures; they are not evidence of physical-device acceptance. The Watch image shows no heart-rate reading. The dark concept phones, fabricated Watch reading and How It Works concept images are no longer displayed. The two images retain their aspect ratios and explicit source dimensions.

Keep both **TestFlight soon** buttons disabled until the external build is approved and its public invitation is usable. Build 0.1 (1) has owner-internal access; its external invitation is still waiting for Apple beta review. See the [installation guide](../docs/testflight.md). Local Apple voice is implemented and opt-in; ElevenLabs synthesis and actual audible phone acceptance remain pending. Pose counting, local history and on-screen cues are distinguished from optional online Gemini requests and workout uploads.

Before contributing, check the hero, feature cards, How It Works and availability/footer at desktop and narrow widths. Use the keyboard to reach Skip to content and section links. Confirm image loads, visible focus, reduced-motion behavior, and the two disabled availability controls. Preserve the restrained white/black layout and existing green accent. The page loads local assets only and starts no camera, microphone, voice or provider request.

## Review checkpoint — 24 October 2026

CUA/Chrome review verified desktop rendering, 320/390 CSS-pixel responsive previews, selected desktop/mobile section anchors and HTTP 200 for all five images. These are desktop previews, not physical Safari/touchscreen checks. Source-color calculation found 15px gray descriptions on the card background at 4.346:1; darkening the gray token to `#6b6b6b` raises that contrast above 4.5:1. The stale all-voice-planned copy was also corrected. Both issues were reproduced before the change; focused contrast/copy checks pass afterward. No SVG or artwork was added.

Those initial rendered checks preceded the text/color edits. A local pass at 23:14–23:19 UTC subsequently verified that earlier five-preview revision with dedicated Playwright browser tools and CUA/Chrome captures. Its source hash is retained in the [browser receipt](../docs/evidence/landing-browser-2026-10-24.md).

After the page switched to the two actual white simulator screens, a focused CUA/Chrome follow-up at 23:32–23:33 UTC verified desktop 1440px, tablet 768px and 390/320px mobile previews, image loads, no horizontal overflow, the simulator caption, keyboard/skip-link navigation, visible focus, anchors, reduced motion and zero console warnings/errors. The receipt includes the revised source/image hashes and new full-page screenshots.

External link destinations were inspected but not opened. Physical iPhone/Safari, touchscreen, screen-reader and deployed-hosting acceptance remain unverified. Both availability controls remain disabled while the external invitation awaits approval. No public deployment or provider call occurred; only task-owned tabs and isolated local servers were closed.
