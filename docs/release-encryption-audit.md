# Build 1 encryption audit

Checked 24 October 2026 for Spottr **0.1 (1)**, including its embedded Watch app. Using this technical basis, the release operator classifies the frozen app as using **no non-exempt encryption**. This records a build-specific release decision, not legal advice or a Google/vendor attestation. App Store Connect declaration changes are a separate operator action; this audit changed no app metadata.

## Frozen artifacts

Inspected the private, ignored archive `.local/release/mvp-build-1/Spottr.xcarchive` and exported `.local/release/mvp-build-1/export/Spottr.ipa`. The archive contains only two Mach-O executables: the iPhone app and Watch app. Their dynamic dependencies are Apple/system libraries. Archive and IPA executable bytes differ after export/signing, but each slice has an identical Mach-O UUID and SHA-256 of its `__TEXT,__text` code section. The archive’s dSYM UUIDs also match.

| Executable / slice | UUID | Code-section SHA-256, equal in archive and IPA |
| --- | --- | --- |
| iPhone / arm64 | `1309800F-A473-3F0E-9A3E-12DF58EAC1A2` | `63aad2551f1fbdac1d377db37f751865b4823dddd0087216737be27b3beb92db` |
| Watch / arm64 | `9EF8463F-88A7-333E-AB67-F4613C1B61CC` | `da826069b1b8fe92a06c44ba9055909f3fe8b4e18e7120d21d939e52f1069a79` |
| Watch / arm64_32 | `5F470470-44FA-3737-8E09-03D18D42FD8C` | `f57192535921fe8186c1cd67a4130d308992a7925b57633f3ce88c29fa1caf7a` |

## App-owned use

- Gateway coaching and workout sync use Apple `URLSession` HTTPS: [CoachGateway](../Shared/Core/CoachGateway.swift), [WorkoutSync](../Shared/Core/WorkoutSync.swift).
- Pi camera transport also uses `URLSession`. Certificate pinning hashes the certificate with Apple CryptoKit `SHA256`, then evaluates hostname, dates and trust through Security APIs: [SecondaryCameraTLS](../Native/iOS/SecondaryCameraTLS.swift). This is certificate verification, not an app-supplied cipher.
- Gateway tokens and camera pairing use Apple Keychain `SecItem` APIs: [CoachModel](../Native/iOS/CoachModel.swift), [SecondaryCameraSettings](../Native/iOS/SecondaryCameraSettings.swift). No credential values were read for this audit.

The host imports OS CryptoKit SHA-256 and Security `SecItem`/`SecTrust` symbols. The Watch has no scanned crypto imports. No app-owned custom cipher or key-generation implementation was found.

## MediaPipe 1.1.1: archive contents versus retained code

All three pinned device payloads are static archives. Common/Vision had no scanned crypto symbols. Graphs contains Rust ChaCha RNG/cipher/digest objects and Abseil AES-based Randen objects, but their ChaCha/Randen/crypto-common/SHA-1/MD5/cipher names are absent from the matching Release dSYM. No concrete OpenSSL/BoringSSL, mbedTLS, libsodium or other non-OS cipher implementation was identified in the retained code.

Three `drishti::aimatter::DecryptTfLiteModel` overloads and a registry **are retained**. A bounded reference/disassembly check characterizes these as a dispatch extension point:

- Registry data at `0x101ad36f0` starts zeroed. Its lazy initializer at `0x101511954` initializes an empty map under a guard; it inserts no decryptor.
- `dyld_info` identifies exactly two registry/guard GOT slots (`0x101ab6968`, `0x101ab3450`). Their five code references are confined to the getter and empty initializer. The getter’s sole direct caller is the key-enumeration reader. No registration/mutator path or concrete decryptor/vtable target was identified. Linker-folded cold/error helpers were excluded from caller attribution.
- The buffer overload at `0x10021ec98` calls `VerifyBufferFromStart<tflite::Model>` with literal `TFL3`. Valid plaintext takes the branch to `0x10021ed74`, returns the original buffer and bypasses decryption. Both shipped model files, `pose_detector.tflite` and `pose_landmarks_detector.tflite`, have plain `TFL3` identifiers. App configuration loads this pose task, with no encrypted-model/key configuration.

The dispatcher’s name alone therefore does not establish a bundled encryption implementation or encryption use by the shipped model path.

## Method and limits

Read-only source inspection, bounded `ar` member extraction, `nm`, `otool`, `llvm-objdump`, `dyld_info`, `dwarfdump`, and Mach-O section hashing were used. No app/device execution, build, secret access or metadata change occurred. Static inspection is not exhaustive formal verification; symbol absence alone was not treated as proof. Findings apply to these exact artifacts and configured model path. Re-audit changed SDKs, models or cryptographic features.

Apple says OS-provided encryption such as `URLSession` HTTPS is typically exempt from documentation upload requirements, and its determination includes linked third-party libraries: [encryption guidance](https://developer.apple.com/documentation/Security/complying-with-encryption-export-regulations), [documentation categories](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/), [Info.plist key meaning](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption). These sources inform the operator’s classification; they do not provide a build-specific Apple or vendor attestation.
