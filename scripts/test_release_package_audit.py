import importlib.util
import datetime as dt
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).with_name('release_package_audit.py')
spec = importlib.util.spec_from_file_location('release_package_audit', SCRIPT)
audit = importlib.util.module_from_spec(spec) if SCRIPT.exists() else None
if audit:
    spec.loader.exec_module(audit)


def plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value))


def macho(path, *, dynamic=False, platform=2, linked=False, code=b'synthetic-code', runpath=True):
    name = b'@rpath/SmartSpectra.framework/SmartSpectra\0'
    build = struct.pack('<IIIIII', 0x32, 24, platform, 0, 0, 0)
    load = struct.pack('<IIIIII', 0xc, 24 + len(name), 24, 0, 0, 0) + name if linked else b''
    rpath = b'@executable_path/Frameworks\0'
    search = struct.pack('<III', 0x8000001c, 12 + len(rpath), 12) + rpath if linked and runpath else b''
    identity = struct.pack('<II', 0x1b, 24) + b'\x12' * 16
    segment = bytearray(152)
    struct.pack_into('<II', segment, 0, 0x19, 152)
    struct.pack_into('<I', segment, 64, 1)
    segment[72:88] = b'__text'.ljust(16, b'\0')
    segment[88:104] = b'__TEXT'.ljust(16, b'\0')
    struct.pack_into('<QI', segment, 112, len(code), 32 + 152 + len(identity + build + load + search))
    header = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, 6 if dynamic else 2,
                         3 + bool(load) + bool(search), len(build + load + search + identity + segment), 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + build + load + search + identity + segment + code)


class ReleasePackagingBehavior(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.host = self.root / 'Spottr.app'
        self.watch = self.host / 'Watch/SpottrWatch.app'
        self.sdk = self.source / 'Native/Vendor/SmartSpectra.xcframework/ios-arm64/SmartSpectra.framework'
        self.embedded = self.host / 'Frameworks/SmartSpectra.framework'
        self.now = dt.datetime(2026, 10, 25, 8, tzinfo=dt.timezone.utc)
        self.demo = self.root / 'private-build/SpottrDemoAccess.json'
        self.demo.parent.mkdir()
        self.demo.write_text(json.dumps({'token': 'synthetic_demo_' + 'a' * 32, 'expiresAt': '2026-10-26T06:00:00.000Z'}))
        self.demo.chmod(0o600)
        privacy = {'NSPrivacyAccessedAPITypes': []}
        for target, bundle, platform in [('host', self.host, 2), ('watch', self.watch, 4)]:
            name = 'Spottr' if target == 'host' else 'SpottrWatch'
            info = {'CFBundleIdentifier': 'com.omarchoudhry.spottr' + ('.watchkitapp' if target == 'watch' else ''),
                    'CFBundleExecutable': name, 'CFBundlePackageType': 'APPL',
                    'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '6',
                    'ITSAppUsesNonExemptEncryption': False}
            if target == 'watch':
                info.update(WKApplication=True, WKCompanionAppBundleIdentifier='com.omarchoudhry.spottr')
            source_info = dict(info)
            source_info.update(NSCameraUsageDescription='Synthetic camera purpose') if target == 'host' else source_info.update(
                NSHealthShareUsageDescription='Synthetic health read', NSHealthUpdateUsageDescription='Synthetic health write',
                NSMotionUsageDescription='Synthetic motion purpose')
            info.update(source_info)
            plist(bundle / 'Info.plist', info)
            plist(self.source / f'Native/{"iOS" if target == "host" else "Watch"}/Info.plist', source_info)
            plist(bundle / 'PrivacyInfo.xcprivacy', privacy)
            plist(self.source / f'Native/{"iOS" if target == "host" else "Watch"}/PrivacyInfo.xcprivacy', privacy)
            macho(bundle / name, platform=platform)
        for name, data in [('pose_landmarker_lite.task', b'synthetic-model'), ('MediaPipe-LICENSE.txt', b'synthetic-license')]:
            file = self.source / 'Native/Resources' / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            (self.host / name).write_bytes(data)
        guidance = self.source / 'Shared/Core/Resources/coach-guidance.json'
        guidance.parent.mkdir(parents=True)
        guidance.write_text(json.dumps({'version': 1, 'sources': ['synthetic']}))
        shutil.copy(guidance, self.host / guidance.name)
        shutil.copy(self.demo, self.host / self.demo.name)
        plist(self.sdk / 'Info.plist', {'CFBundleExecutable': 'SmartSpectra', 'CFBundleIdentifier': 'com.presage.SmartSpectra',
                                      'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': '3.4.0'})
        plist(self.sdk / 'PrivacyInfo.xcprivacy', privacy)
        for name in ['metrics_cpu_continuous_rest.binarypb', 'pose_detection.tflite', 'pose_landmark_lite.tflite',
                     'pose_landmark_full.tflite', 'face_detection_full_range.tflite',
                     'face_detection_short_range.tflite', 'face_landmark_with_attention.tflite']:
            (self.sdk / name).write_bytes(b'synthetic-' + name.encode())
        macho(self.sdk / 'SmartSpectra', dynamic=True)

    def inspect(self):
        self.assertIsNotNone(audit, 'The reusable packaging audit is not implemented')
        return audit.audit_layout(self.host, self.source, '0.1', '6', self.demo, self.now)

    def reject(self, code):
        self.assertIsNotNone(audit, 'The reusable packaging audit is not implemented')
        with self.assertRaises(audit.AuditError) as caught:
            self.inspect()
        self.assertEqual(str(caught.exception), code)

    def edit_info(self, app, **values):
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        plist(app / 'Info.plist', {**info, **values})

    def test_accepts_default_release_without_smartspectra_and_returns_deterministic_hashes(self):
        result = self.inspect()
        self.assertEqual(result, self.inspect())
        self.assertFalse(result['presageEnabled'])
        self.assertIn('Watch/SpottrWatch.app/PrivacyInfo.xcprivacy', result['resources'])

    def test_release_rejects_complete_or_incomplete_experimental_smartspectra_bundle(self):
        shutil.copytree(self.sdk, self.embedded)
        self.reject('smartspectra_release_blocked')
        (self.embedded / 'PrivacyInfo.xcprivacy').unlink()
        self.reject('smartspectra_release_blocked')

    def test_release_rejects_direct_or_weak_sdk_link_even_without_embedding(self):
        macho(self.host / 'Spottr', linked=True)
        self.reject('smartspectra_release_blocked')

        raw = bytearray((self.host / 'Spottr').read_bytes())
        struct.pack_into('<I', raw, 56, 0x80000018)
        (self.host / 'Spottr').write_bytes(raw)
        self.reject('smartspectra_release_blocked')

    def test_release_rejects_transitive_smartspectra_dependency_in_another_framework(self):
        macho(self.host / 'Frameworks/Other.framework/Other', dynamic=True, linked=True)
        self.reject('smartspectra_release_blocked')

    def test_release_rejects_leftover_sdk_models_and_graphs(self):
        for name in ['pose_detection.tflite', 'metrics_cpu_continuous_rest.binarypb']:
            with self.subTest(name=name):
                file = self.host / name
                file.write_bytes(b'leftover-synthetic-sdk-resource')
                self.reject('smartspectra_release_blocked')
                file.unlink()

    def test_default_release_preserves_static_mediapipe_boundary(self):
        macho(self.host / 'Frameworks/MediaPipeTasksVision.framework/MediaPipeTasksVision', dynamic=True)
        self.reject('static_mediapipe_unexpectedly_embedded')

    def test_rejects_watch_identity_version_companion_and_encryption_drift(self):
        for field, value, code in [('CFBundleIdentifier', 'wrong', 'bundle_identity_mismatch'),
                                   ('CFBundleVersion', '5', 'bundle_version_mismatch'),
                                   ('WKCompanionAppBundleIdentifier', 'wrong', 'companion_identity_mismatch'),
                                   ('ITSAppUsesNonExemptEncryption', True, 'encryption_flag_mismatch')]:
            with self.subTest(field=field):
                original = (self.watch / 'Info.plist').read_bytes()
                self.edit_info(self.watch, **{field: value})
                self.reject(code)
                (self.watch / 'Info.plist').write_bytes(original)

    def test_rejects_app_resources_or_sdk_accidentally_bundled_in_watch(self):
        for name in ['pose_landmarker_lite.task', 'coach-guidance.json', 'SmartSpectra.key']:
            with self.subTest(name=name):
                file = self.watch / name
                file.write_bytes(b'synthetic')
                self.reject('watch_contains_host_only_resource')
                file.unlink()
        shutil.copytree(self.sdk, self.watch / 'Frameworks/SmartSpectra.framework')
        self.reject('watch_contains_host_only_resource')

    def test_rejects_missing_or_changed_first_party_privacy_guidance_and_mediapipe(self):
        for name in ['PrivacyInfo.xcprivacy', 'coach-guidance.json', 'pose_landmarker_lite.task', 'MediaPipe-LICENSE.txt']:
            with self.subTest(name=name):
                file = self.host / name
                original = file.read_bytes()
                file.write_bytes(b'changed')
                self.reject('source_resource_mismatch')
                file.write_bytes(original)

    def test_rejects_usage_disclosure_drift(self):
        self.edit_info(self.host, NSCameraUsageDescription='All processing is local')
        self.reject('usage_description_mismatch')

    def test_rejects_bundled_secrets_without_disclosing_values(self):
        for name, value in [('config.txt', b'PRESAGE_API_KEY=synthetic-private-value'),
                            ('secret.p8', b'synthetic'), ('.env.production', b'synthetic'),
                            ('notes.txt', b'-----BEGIN PRIVATE KEY-----\nsynthetic'),
                            ('config.json', b'{"apiKey":"synthetic-private-value"}')]:
            with self.subTest(name=name):
                file = self.host / name
                file.write_bytes(value)
                self.reject('bundled_private_material')
                file.unlink()

    def replace_demo(self, data):
        raw = json.dumps(data).encode() if isinstance(data, dict) else data
        self.demo.write_bytes(raw)
        (self.host / self.demo.name).write_bytes(raw)

    def test_demo_access_requires_exact_shape_token_format_and_bounded_canonical_expiry(self):
        valid = json.loads(self.demo.read_bytes())
        variants = [({**valid, 'ownerToken': 'not-allowed'}, 'invalid_demo_access'),
                    ({'token': valid['token']}, 'invalid_demo_access'),
                    ({**valid, 'token': 'short'}, 'invalid_demo_access'),
                    ({**valid, 'token': 'x' * 257}, 'invalid_demo_access'),
                    ({**valid, 'token': 'non-url-safe/' + 'x' * 32}, 'invalid_demo_access'),
                    ({**valid, 'expiresAt': '2026-10-25T07:00:00.000Z'}, 'demo_access_expired_or_overlong'),
                    ({**valid, 'expiresAt': '2026-10-26T08:00:00.001Z'}, 'demo_access_expired_or_overlong'),
                    ({**valid, 'expiresAt': '2026-10-26T06:48:00.000Z'}, 'demo_access_past_teardown'),
                    ({**valid, 'expiresAt': '2026-10-26T06:00:00Z'}, 'invalid_demo_access'),
                    (b'{"token":"duplicate","token":"duplicate","expiresAt":"2026-10-26T06:00:00.000Z"}',
                     'invalid_demo_access')]
        for value, code in variants:
            with self.subTest(code=code, value_type=type(value).__name__):
                self.replace_demo(value)
                self.reject(code)

    def test_demo_access_input_must_be_private_and_exactly_match_the_iphone_resource(self):
        self.demo.chmod(0o644)
        self.reject('demo_access_input_must_be_private')
        self.demo.chmod(0o600)
        (self.host / self.demo.name).write_text('{}')
        self.reject('demo_access_resource_mismatch')
        (self.host / self.demo.name).unlink()
        self.reject('demo_access_resource_mismatch')

    def test_demo_access_cannot_leak_to_watch_or_another_resource(self):
        shutil.copy(self.demo, self.watch / self.demo.name)
        self.reject('watch_contains_host_only_resource')
        (self.watch / self.demo.name).unlink()
        token = json.loads(self.demo.read_bytes())['token']
        (self.host / 'unexpected.bin').write_bytes(token.encode())
        self.reject('bundled_private_material')

    def test_demo_access_never_exempts_known_owner_or_provider_values(self):
        token = json.loads(self.demo.read_bytes())['token'].encode()
        self.assertIsNotNone(audit)
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_private_material([self.host / self.demo.name], [token])
        self.assertEqual(str(caught.exception), 'bundled_private_material')

    def test_owner_and_provider_inputs_are_read_privately_and_cannot_be_the_demo_token(self):
        self.assertIsNotNone(audit)
        owner = self.root / 'private-owner-token.txt'
        owner.write_text(json.loads(self.demo.read_bytes())['token'])
        owner.chmod(0o600)
        values = audit.private_values([owner])
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_private_material([self.host / self.demo.name], values)
        self.assertEqual(str(caught.exception), 'bundled_private_material')
        owner.chmod(0o644)
        with self.assertRaises(audit.AuditError) as caught:
            audit.private_values([owner])
        self.assertEqual(str(caught.exception), 'secret_file_must_be_private')

    def test_allows_nonsecret_sdk_graph_identifiers_and_public_api_declarations(self):
        (self.host / 'synthetic-graph.txt').write_bytes(
            b'input_side_packet: "api_key:api_key"\npublic var apiKey: Swift.String?\n')
        self.inspect()

    def test_rejects_exact_private_input_even_without_a_known_key_prefix(self):
        file = self.host / 'raw.bin'
        file.write_bytes(b'prefix\0synthetic-opaque-private-value\0suffix')
        self.assertIsNotNone(audit)
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_private_material([file], [b'synthetic-opaque-private-value'])
        self.assertEqual(str(caught.exception), 'bundled_private_material')

    def test_signing_material_requires_profile_team_identity_distribution_and_certificate(self):
        self.assertIsNotNone(audit)
        import datetime as dt
        now = dt.datetime(2026, 10, 25, tzinfo=dt.timezone.utc)
        identity = 'com.omarchoudhry.spottr'
        ent = {'application-identifier': 'SYNTHETIC.' + identity,
               'com.apple.developer.team-identifier': 'SYNTHETIC', 'get-task-allow': False,
               'beta-reports-active': True}
        profile = {'TeamIdentifier': ['SYNTHETIC'], 'Entitlements': dict(ent),
                   'ExpirationDate': dt.datetime(2027, 1, 1), 'DeveloperCertificates': [b'synthetic-cert']}
        audit.verify_signing_material(ent, profile, b'synthetic-cert', identity, 'SYNTHETIC', False, now)
        variants = [({**profile, 'TeamIdentifier': ['OTHER']}, ent, 'profile_identity_mismatch'),
                    ({**profile, 'ProvisionedDevices': ['synthetic']}, ent, 'not_appstore_profile'),
                    ({**profile, 'ExpirationDate': dt.datetime(2025, 1, 1)}, ent, 'profile_expired'),
                    ({**profile, 'DeveloperCertificates': [b'other']}, ent, 'signer_not_in_profile'),
                    (profile, {**ent, 'get-task-allow': True}, 'debug_entitlement_present'),
                    (profile, {**ent, 'com.apple.security.application-groups': ['unexpected']}, 'unexpected_entitlement')]
        for changed_profile, changed_ent, code in variants:
            with self.subTest(code=code), self.assertRaises(audit.AuditError) as caught:
                audit.verify_signing_material(changed_ent, changed_profile, b'synthetic-cert', identity, 'SYNTHETIC', False, now)
            self.assertEqual(str(caught.exception), code)

    def test_rejects_symlinks_in_bundle(self):
        (self.host / 'alias').symlink_to(self.source)
        self.reject('bundle_symlink_not_supported')

    def test_archive_export_comparison_allows_resigning_but_not_resource_changes(self):
        first = self.inspect()
        signature = self.host / '_CodeSignature/CodeResources'
        signature.parent.mkdir()
        signature.write_text('synthetic-resigned')
        self.assertEqual(first, self.inspect())
        (self.host / 'Assets.car').write_bytes(b'new-resource')
        self.assertNotEqual(first['resources'], self.inspect()['resources'])

    def test_cli_requires_frozen_release_inputs_and_sanitizes_failure(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout), {'status': 'failed', 'code': 'invalid_arguments'})
        self.assertEqual(result.stderr, '')

    def test_ipa_extraction_rejects_traversal_duplicate_and_symlink_entries(self):
        self.assertIsNotNone(audit)
        import warnings
        for variant in ['../escape', 'duplicate', 'symlink']:
            with self.subTest(variant=variant):
                ipa = self.root / 'bad.ipa'
                with zipfile.ZipFile(ipa, 'w') as zipped, warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    if variant == 'duplicate':
                        zipped.writestr('Payload/Spottr.app/Info.plist', 'a')
                        zipped.writestr('Payload/Spottr.app/Info.plist', 'b')
                    elif variant == 'symlink':
                        entry = zipfile.ZipInfo('Payload/Spottr.app/link')
                        entry.external_attr = 0o120777 << 16
                        zipped.writestr(entry, '../outside')
                    else:
                        zipped.writestr(variant, 'a')
                with self.assertRaises(audit.AuditError):
                    audit.extract_ipa(ipa, self.root / 'extracted')
                self.assertFalse((self.root / 'escape').exists())

    def test_actual_ipa_extraction_preserves_the_audited_bundle(self):
        self.assertIsNotNone(audit)
        ipa = self.root / 'synthetic.ipa'
        with zipfile.ZipFile(ipa, 'w') as zipped:
            for file in self.host.rglob('*'):
                if file.is_file():
                    zipped.write(file, 'Payload/Spottr.app/' + str(file.relative_to(self.host)))
        extracted = audit.extract_ipa(ipa, self.root / 'extracted-valid')
        self.assertEqual(audit.audit_layout(extracted, self.source, '0.1', '6', self.demo, self.now), self.inspect())

    def test_ipa_rejects_private_file_names_even_outside_the_app_payload(self):
        self.assertIsNotNone(audit)
        for name in ['Symbols/private.p8', 'SwiftSupport/.env.production']:
            with self.subTest(name=name):
                ipa = self.root / 'private-file.ipa'
                with zipfile.ZipFile(ipa, 'w') as zipped:
                    zipped.writestr('Payload/Spottr.app/Info.plist', 'synthetic')
                    zipped.writestr(name, 'synthetic')
                with self.assertRaises(audit.AuditError) as caught:
                    audit.extract_ipa(ipa, self.root / 'private-extraction')
                self.assertEqual(str(caught.exception), 'unexpected_private_file')

    def test_vendor_inputs_preserve_mediapipe_and_require_approved_manifest(self):
        self.assertIsNotNone(audit)
        vendor = self.source / 'Native/Vendor'
        old = self.root / 'previous-vendor'
        old.mkdir()
        (old / 'MediaPipeTasksVision.xcframework').mkdir()
        library = old / 'MediaPipeTasksVision.xcframework/library.a'
        library.write_bytes(b'synthetic-static-mediapipe')
        shutil.copytree(library.parent, vendor / library.parent.name)
        manifest = {str(p.relative_to(vendor)): audit.digest(p) for p in audit.files(vendor)}
        audit.verify_vendor(vendor, old, manifest)
        (vendor / library.parent.name / library.name).write_bytes(b'changed')
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_vendor(vendor, old, manifest)
        self.assertEqual(str(caught.exception), 'vendor_manifest_mismatch')
        changed = {str(p.relative_to(vendor)): audit.digest(p) for p in audit.files(vendor)}
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_vendor(vendor, old, changed)
        self.assertEqual(str(caught.exception), 'mediapipe_changed_since_baseline')

    def test_frozen_source_must_match_commit_bytes_and_exact_tracked_file_set(self):
        self.assertIsNotNone(audit)
        repo = self.root / 'repo'
        repo.mkdir()
        def git(*args):
            return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True).stdout.decode().strip()
        git('init', '-q')
        (repo / 'Native').mkdir()
        (repo / 'Shared').mkdir()
        (repo / 'Native/app.swift').write_text('synthetic source')
        (repo / 'Shared/core.swift').write_text('synthetic core')
        git('add', 'Native', 'Shared')
        git('-c', 'user.name=Synthetic Fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Synthetic source')
        commit = git('rev-parse', 'HEAD')
        frozen = self.root / 'frozen'
        shutil.copytree(repo / 'Native', frozen / 'Native')
        shutil.copytree(repo / 'Shared', frozen / 'Shared')
        self.assertEqual(audit.verify_source(repo, frozen, commit), 2)
        (frozen / 'Native/app.swift').write_text('changed')
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_source(repo, frozen, commit)
        self.assertEqual(str(caught.exception), 'source_snapshot_bytes_mismatch')
        (frozen / 'Native/untracked.swift').write_text('extra')
        with self.assertRaises(audit.AuditError) as caught:
            audit.verify_source(repo, frozen, commit)
        self.assertEqual(str(caught.exception), 'source_snapshot_file_mismatch')


if __name__ == '__main__':
    unittest.main()
