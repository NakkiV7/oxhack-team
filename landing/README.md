# Spottr landing page

The existing white landing page is published at **https://spottr.omarchoudhry.co.uk/** on the already authorized Vultr demo VM. It needs no build step or service credentials. The [publication receipt](../docs/evidence/landing-publication-2026-10-25.md) records hosted checks and screenshots. Hosting is temporary within the existing VM's approved lifetime; publication does not extend its teardown deadline.

From the repository root:

```bash
python3 -m http.server 8149 --bind 127.0.0.1 --directory landing
```

Open `http://127.0.0.1:8149/`. Any static host can serve the contents of `landing/`; include `assets/`. No other repository folders or `.env` files need to be served.

The page displays two actual white iPhone/Watch simulator captures: `assets/today-simulator.jpg` and `assets/watch-simulator.jpg`. The caption identifies them as simulator captures; they are not evidence of physical-device acceptance. The Watch image shows no heart-rate reading. The dark concept phones, fabricated Watch reading and How It Works concept images are no longer displayed. The two images retain their aspect ratios and explicit source dimensions.

Both **Join the TestFlight beta** links use the existing [public invitation](https://testflight.apple.com/join/f3MhePbf). The current documented release is **0.1 (5)**; the page states iOS 26+ and watchOS 26+ for the optional companion. A reported build-5 onboarding crash remains under investigation. See the [installation guide](../docs/testflight.md) for distribution evidence and limits; this publication did not accept an invitation or install the app. The feature copy stays within build-5 capabilities: push-up/squat counting, local history, skill progression, opt-in local voice and optional configured Gemini coaching. It makes no claim about newly integrated active energy, remote ElevenLabs playback, Presage or physical Watch acceptance. Contributor and demo-guide links lead to the repository's existing documentation.

Before contributing, check the hero, feature cards, How It Works and availability/footer at desktop and narrow widths. Use the keyboard to reach Skip to content and section links. Confirm image loads, visible focus, reduced-motion behavior, and both TestFlight links. Preserve the restrained white/black layout and existing green accent. The page loads local assets only and starts no camera, microphone, voice or provider request.

## Review checkpoint — 24 October 2026

CUA/Chrome review verified desktop rendering, 320/390 CSS-pixel responsive previews, selected desktop/mobile section anchors and HTTP 200 for all five images. These are desktop previews, not physical Safari/touchscreen checks. Source-color calculation found 15px gray descriptions on the card background at 4.346:1; darkening the gray token to `#6b6b6b` raises that contrast above 4.5:1. The stale all-voice-planned copy was also corrected. Both issues were reproduced before the change; focused contrast/copy checks pass afterward. No SVG or artwork was added.

Those initial rendered checks preceded the text/color edits. A local pass at 23:14–23:19 UTC subsequently verified that earlier five-preview revision with dedicated Playwright browser tools and CUA/Chrome captures. Its source hash is retained in the [browser receipt](../docs/evidence/landing-browser-2026-10-24.md).

After the page switched to the two actual white simulator screens, a focused CUA/Chrome follow-up at 23:32–23:33 UTC verified desktop 1440px, tablet 768px and 390/320px mobile previews, image loads, no horizontal overflow, the simulator caption, keyboard/skip-link navigation, visible focus, anchors, reduced motion and zero console warnings/errors. The receipt includes the revised source/image hashes and new full-page screenshots.

External link destinations were inspected but not opened. Physical iPhone/Safari, touchscreen, screen-reader and deployed-hosting acceptance remain unverified. Both availability controls were disabled at that historical checkpoint; see the 25 October follow-up below. No public deployment or provider call occurred; only task-owned tabs and isolated local servers were closed.

## Availability follow-up — 25 October 2026

The public Apple invitation was verified before replacing the two disabled buttons with ordinary HTTPS links. The existing layout and artwork are unchanged. Local browser checks and the public invitation screenshot are recorded in the [availability receipt](../docs/evidence/testflight-availability-2026-10-25.md). No TestFlight invitation was accepted, app installed, provider called or landing site deployed by this check.

## Hosting boundary and checks

`deploy/compose.yaml` mounts only `landing/` read-only at `/srv/landing`. Caddy serves `/` and `/assets/*` publicly. Every other path retains the remote-IP allowlist and existing gateway behavior, including `/health`; API bearer authentication remains in the gateway. There is no SPA fallback. Private env files and repository directories are outside the static root. Publish only `index.html` and its referenced assets; tests and this README need not be copied.

```sh
python3 -m unittest discover -s landing -p 'test_*.py'
# On the existing Docker host, with its spottr_default network and gateway running:
python3 deploy/tests/landing-routing.py /absolute/path/to/source
```

The routing check uses the pinned Caddy image, a temporary named container and loopback port 18149. It tests both allowed and excluded clients, image byte identity, health, protected routes, missing files and forged forwarding headers, then removes its own container. All gateway requests lack a valid bearer; no provider is called. Older gateway images may return 404 for optional voice routes; supported protected routes must return 401. Do not run two copies concurrently.

For deployment, validate Compose with `config --quiet`, validate Caddy, and recreate **only Caddy** with `up -d --no-deps --no-build caddy`, using the existing private `deployment.env`. Keep certificate volumes and gateway runtime intact. See the [receipt](../docs/evidence/landing-publication-2026-10-25.md) for this deployment's restoration trail. Landing updates do not authorize VM replacement, runtime-secret edits, public API access or extending the existing spending/lifetime limit.
