# Spottr public website

The current website source is `landing/public/`. The Spottr Worker serves that directory, the account client and the account API; its configuration is in [`web/wrangler.jsonc`](../web/wrangler.jsonc). Source changes are a testing candidate until the corresponding deployment and public readback receipts are recorded. The public TestFlight build can differ from this candidate.

For a static, loopback-only preview from the repository root:

```sh
python3 -m http.server 8149 --bind 127.0.0.1 --directory landing/public
```

Open `http://127.0.0.1:8149/`. Serve only `landing/public/`, never the repository root, private configuration or evidence. This preview supports the public pages and account page rendering; it does not provide the Worker account API, passkeys or live analytics.

The page uses actual Today and Coach simulator captures from the local overhaul candidate. [`screenshot-provenance.json`](screenshot-provenance.json) records their capture dates, dimensions, hashes and illustrative local test input. These images are not evidence of physical exercise, sensor accuracy or a released build. Existing historical assets remain available. Exercise artwork is faceless; the page starts no camera, microphone, voice or provider request.

Before publication, inspect desktop and narrow layouts, both current screenshots, keyboard focus and Skip to content, section links, FAQ disclosure, the TestFlight destination, and the privacy, terms, support and deletion pages. Inspect the account page separately with the real Worker API for authentication acceptance. The public page explains mandatory native accounts, separate Apple membership, optional adult analytics and the distinction between local training records and Apple Health syncing.

The native privacy contract in this command requires macOS with `plutil` available on `PATH`. It parses the real iOS privacy plist rather than a test copy. Other operating systems need a supported plist parser before this complete command can be treated as portable.

Run source checks from the repository root:

```sh
node --test landing/tests-public/*.test.mjs
```

See [`web/README.md`](../web/README.md) and the [service activation checklist](../web/docs/service-activation.md) for local API tests, deployment boundaries and remaining release checks. Do not infer service activation or physical-device acceptance from static checks.

## Historical demo publication

The October white landing page, legacy `landing/index.html`, old simulator assets and demo-VM routing tests are retained as historical material. They are not the current Worker static root. The [24 October browser receipt](../docs/evidence/landing-browser-2026-10-24.md), [25 October availability receipt](../docs/evidence/testflight-availability-2026-10-25.md) and [demo publication receipt](../docs/evidence/landing-publication-2026-10-25.md) describe those earlier revisions and their limits. They do not extend any VM lifetime or authorize changes to the old gateway, credentials or unrelated services.
