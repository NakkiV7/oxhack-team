# Weekly gateway container acceptance — 25 October 2026

**The current Linux/ARM64 image passed local isolated runtime checks.** This verifies packaging and offline HTTP/schema behavior, not hosted deployment or a live weekly Gemini response. The [machine receipt](container-weekly-verification-2026-10-25.json) pins every copied source/runtime hash to commit `7868d1dc6f26a4d50a93288b5fd7b48924774431`; none differed from that commit.

Built from the repository root with:

```sh
docker --context colima-spottr-verify build --platform linux/arm64 \
  --progress=plain -f server/Dockerfile -t spottr-weekly-verify:20261025 .
```

The build exited 0, using the pinned Node base and a cached locked-dependency layer. The Dockerfile-specific allowlist transferred **24.96 kB**. All **23 runtime file hashes** matched, including canonical `coach-guidance.json` SHA-256 `72347cb0b1e2edcefc2fc386e7531c4a23c079d9048fac69808f5910ff2589b8`. The image is `sha256:7b75fea74797e6d5dedf4eef7c3a5f4c672e01161e7c5a8d1257f8d2d2cc6bc1`.

The single task container ran as **UID 1000**, with a read-only filesystem, network `none`, no mounts or published ports, all capabilities dropped, no-new-privileges, 64 PID/128 MiB/one-CPU limits. An attempted application-directory write failed `EROFS`. Only a synthetic owner token was supplied; real provider configuration stayed blank. Docker health became **healthy**.

Internal loopback HTTP checks returned health **200**, missing/wrong authentication **401**, unknown route **404**, and unconfigured chat/weekly routes **503**. Malformed weekly JSON also returned 503 because configuration is checked before body parsing; this is not evidence that malformed input was accepted.

A separate in-memory provider double inside the built container produced a schema-validated seven-day proposal (**200**); an invented guidance identifier was rejected (**502**). These were **two fake provider invocations and zero external provider calls**. No database queries or health capture occurred.

The exact task container was removed and `spottr-verify` stopped at **03:34:43 UTC**. Colima created its named context during startup; the default remained `desktop-linux`. Existing engines, profiles and containers were preserved.

Unverified: AMD64, hosted HTTPS/ACME/firewall, live provider generation, live database persistence and physical-device access. The earlier [container receipt](container-verification-2026-10-24.json) remains historical; Caddy was not revalidated here.
