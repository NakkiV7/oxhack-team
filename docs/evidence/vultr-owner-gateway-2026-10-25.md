# Vultr owner gateway — 25 October 2026

Checkpoint **06:57 UTC**. The approved London `vc2-1c-1gb` Ubuntu 24.04 VM hosts [the owner gateway](https://spottr.omarchoudhry.co.uk/health) behind Caddy and trusted public TLS. Access is restricted to the operator's verified public egress; this is not an unrestricted tester endpoint.

The gateway image comes from **`4eebd6d4b6ec2ec106b933909938b38b48843163`**. A separately reviewed two-line Compose correction quotes both tmpfs entries: the original YAML split each comma into a second mount, producing actual runtime RED (`invalid mount path: mode=1777`). After correction, Compose and Caddy validation and both running mounts passed. Caddy reports one existing formatting warning at line 2.

- Actual **Linux/AMD64** build: `sha256:791cf4513b34cee9fcb7dc46da370c7f2a77d82cab9c8e1790d33748f18eb525`, 344,640,065 bytes; 81.96 kB context. All **23 runtime file hashes** match the frozen source, including catalogue/guidance. Node 24.22.1; UID 1000.
- Gateway: healthy, read-only, capabilities dropped, no-new-privileges, 256 MB limit, one `/tmp` tmpfs, no published port. Caddy publishes only TCP 80/443; SSH is restricted to operator egress. External 8787/2019/5432 were unreachable from the Mac.
- Trusted HTTPS health **200**; all four AI routes without auth **401**; wrong token **401**; authenticated malformed JSON **400**; invalid weekly input **422**; unknown route **404**. An unlisted VM source received **403**, including with a spoofed forwarding header.
- **Zero AI provider requests** during acceptance. Existing owner/Gemini settings were transferred privately; Tiger and installation ID remain blank. Shared owner-demo allowance: **20 attempts per process**, one active request, expiry **26 October 06:47 UTC**. Restart resets the in-memory count; this is not a monetary guarantee. Phone allowlist/TLS and deliberate hosted provider acceptance remain separate.

Approved infrastructure ceiling: **$1**; target destruction **26 October 06:47 UTC**. The quoted $0.007/hour plus 20% VAT is about $0.202 for 24 hours before extras, not a measured bill. Stopping containers or the VM does not stop billing; [the VM must be destroyed](https://docs.vultr.com/support/platform/billing/how-am-i-billed-for-my-servers).

Sanitized private receipts: hosted-check SHA256 `7c212004ddce33794cdaf6447e9e4f201cf4a40e984c6578f1451955726b7eac`; runtime-check `fa810bcc13b9be6cd5a868006ae82d7b201af3a4b8ff1921aaa4d926c11f42ea`. No credentials, request bodies or operator IPs are published.
