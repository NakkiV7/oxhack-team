# Optional Raspberry Pi side camera

This companion captures and forwards camera JPEGs. The iPhone remains the training-session owner and runs pose inference and rep counting. This is preparation for replacing the Arduino hardware role with a Pi and a side camera; it does not implement onboard inference, Bluetooth, sensors, a display, workout state, or motor control.

The isolated companion was configured on the bootcamp Pi on 24 October 2026. Initial real camera JPEGs and authenticated HTTPS work, but the attached Elgato repeatedly disconnects over USB during capture; sustained capture is blocked. The companion is left running with the camera stopped. See [the hardware evidence](EVIDENCE-2026-10-24.md) for the verified endpoint, measurements and limits. Preserve the existing bootcamp/LAVA setup; no network, boot, package or existing service configuration was changed.

## Prerequisites and initial health check

Use Python 3.10+ on Linux. Python dependencies are standard library only. Actual capture additionally needs an existing `ffmpeg` installation with the `v4l2` input and MJPEG encoder, and a USB/V4L2 camera accessible to the current user. The generic default is 640×480 at 10 fps; explicit input format, size and rate options support cameras with other advertised modes. CSI/libcamera cameras need a separate driver and are not supported by this adapter.

When the Pi and camera are ready, manually copy only this directory to a separate checkout or folder. Check `python3 --version`, `command -v ffmpeg` and the camera device without installing anything automatically. If a prerequisite is absent, agree the installation or driver change with the owner of the existing Pi workload first.

From the repository root:

```bash
python3 -m unittest discover -s hardware/pi -v
python3 hardware/pi/companion.py
```

The server defaults to `127.0.0.1:8765`. `GET /health` is public and returns only the service role, stopped/started state and whether a fresh frame exists. Starting the process never opens the camera. Without a token, private routes remain inaccessible; health can be checked before a camera is attached. A successful health response does not demonstrate camera readiness.

Set `SPOTTR_PI_TOKEN` privately in the process environment to enable authenticated capture. Use a random token of at least 32 characters, keep it out of the repository, and transfer it to the eventual phone settings privately. The token has no command-line flag. For a Bash shell, hidden entry is:

```bash
read -r -s -p 'Pi access token: ' SPOTTR_PI_TOKEN
export SPOTTR_PI_TOKEN
python3 hardware/pi/companion.py --device /dev/video0
```

For network access, `--host <verified-Pi-interface-address>` binds the chosen interface and refuses to run without a token. Set both `--tls-cert <certificate.pem>` and `--tls-key <private-key.pem>` for built-in HTTPS. Supplying only one TLS file fails closed. Without those options this small development server supplies plain HTTP; keep that mode on loopback or behind a private encrypted tunnel. Use a separate per-device certificate and explicitly verified certificate pin in the phone client; never disable TLS verification globally or expose the private key. No port forwarding, DNS or service configuration is included here.

The verified Elgato advertises MJPEG 1920×1080 at 30 fps, rather than the generic defaults. This mode limits ffmpeg decode/encode threads and emits smaller, lower-rate frames:

```bash
python3 hardware/pi/companion.py --device /dev/video0 \
  --input-format mjpeg --input-size 1920x1080 --input-fps 30 \
  --output-size 640x360 --output-fps 10 \
  --tls-cert /private/device-cert.pem --tls-key /private/device-key.pem
```

These options select supported modes; they do not resolve the observed USB disconnects. Do not start a second instance on the live companion's port.

## HTTP contract

Every route except exact `GET /health` requires `Authorization: Bearer <token>`. Query-string tokens are never accepted. Responses use `Cache-Control: no-store`; images are kept only in memory. There is no image upload, recording, on-disk image archive or synthetic fallback.

| Route | Behavior |
| --- | --- |
| `GET /health` | Public, no token, device path, capture ID or image content in its response. HTTP 200 indicates the adapter responds. |
| `POST /camera/start` with `{}` | Explicitly opens the configured device and waits up to 2 seconds for a complete JPEG. Returns 200 with `capture_id` and `lease_seconds: 60`, or 503 `camera_unavailable` for a missing driver, unsupported mode, camera or first frame. |
| `POST /camera/start` with `{"capture_id":"current ID"}` | Renews the current capture lease for 60 seconds. Renew before it expires, for example every 30 seconds while the user explicitly keeps capture active. This acknowledges lease renewal; check frame freshness separately. |
| `POST /camera/stop` with `{"capture_id":"current ID"}` | Closes capture and discards its frame. Stops are idempotent with `{}` when already stopped. |
| `GET /frame.jpg` | Returns the latest fresh JPEG or 503 `camera_unavailable`. |
| `GET /stream.mjpg` | Authenticated multipart MJPEG preview with the same frame metadata on each part. Sends a frame once per ID; ends on capture stop, replacement, expiry, or stale imagery. A stale stream must be reopened after fresh capture resumes. |

A start/renew/stop referring to an old capture ID returns 409 `capture_conflict`. An active capture cannot be replaced or stopped by a start/stop that omits its ID. After lease expiry, restart explicitly with `{}` and use the new returned ID. Late frames from an older capture are discarded. Control JSON accepts only an optional string `capture_id`, with a 4 KiB body limit. Unknown routes return 404; invalid controls return 400; oversized bodies return 413; missing/wrong authorization returns 401.

Private JPEG responses and every MJPEG part include:

- `X-Frame-ID`: unique capture ID plus a monotonically increasing sequence. Clients must deduplicate by ID.
- `X-Captured-At`: Pi UTC timestamp when the complete JPEG reaches this adapter. This is a host receipt estimate, not a sensor exposure timestamp; it cannot prove sensor-to-phone latency or clock synchronization.
- `X-Frame-Age-Ms`: age since receipt using the Pi's monotonic clock. Imagery older than 2 seconds is rejected. Network delay after this header is produced is additional; clients must apply their own receive deadline and reject duplicates/stale frames before inference.

FFmpeg runs only after authenticated explicit start, using a fixed argv list without a shell. The device path must match `/dev/video<digits>`. The bounded JPEG parser accepts complete JPEG marker-delimited frames from that process. Raw driver errors and access headers are not printed. A driver that stops emitting frames becomes unavailable after the freshness window; an expired lease stops capture even without another request. Ctrl-C, SIGTERM and server close also stop and reap the capture process.

An ordinary browser `<img>` URL cannot attach a bearer header. Use a client that sends the header, or an authenticated fetch client for the MJPEG parts. Do not work around that by putting the token in a preview URL.

## Native phone adapter

The new native client and manual Keychain pairing form are described in [the native handoff](NATIVE-HANDOFF.md). Phone session integration and physical iPhone acceptance remain separate from this transport implementation.

## Acceptance still needed with the real camera

The tests exercise real localhost HTTP/HTTPS and an injected capture/process boundary. Their test byte fixtures are never available in the runnable server. They establish HTTP behavior, authentication, framing, expiry, explicit camera modes and lifecycle handling. The separate live observation establishes initial 640×360 camera JPEGs and secure LAN reachability; it does not establish sustained capture, image orientation, exposure quality, sensor timing, side-view pose accuracy or iPhone ingestion.

Once the actual camera is connected, explicitly start it and verify a real JPEG, preview, timestamps, stop, missing-camera response and lease expiry. Measure end-to-end delay and dropped frames, confirm the iPhone rejects stale/duplicate side frames, and validate the side-view exercise tracking before counting reps from this source. Keep the phone's own session and inference as the authority throughout that integration.
