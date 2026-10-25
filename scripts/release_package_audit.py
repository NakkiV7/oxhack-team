#!/usr/bin/env python3
"""Read-only archive/export audit. Never builds, installs, uploads or calls providers."""
import argparse
import datetime as dt
import hashlib
import fnmatch
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import stat
import subprocess
import tempfile
import zipfile


HOST_ID = 'com.omarchoudhry.spottr'
WATCH_ID = HOST_ID + '.watchkitapp'
SDK_PATH = 'Native/Vendor/SmartSpectra.xcframework/ios-arm64/SmartSpectra.framework'
SDK_LINK = '@rpath/SmartSpectra.framework/SmartSpectra'
MODEL_NAMES = {'metrics_cpu_continuous_rest.binarypb', 'pose_detection.tflite', 'pose_landmark_lite.tflite',
               'pose_landmark_full.tflite', 'face_detection_full_range.tflite',
               'face_detection_short_range.tflite', 'face_landmark_with_attention.tflite'}
MACHO_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
PRIVATE_CONTENT = re.compile(
    rb'-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----|'
    rb'(?m:^[A-Z0-9_]*(?:API_KEY|ACCESS_TOKEN|BEARER_TOKEN|CLIENT_SECRET|PASSWORD)[ \t]*=[ \t]*["\']?[A-Za-z0-9_+/.=-]{8,})|'
    rb'["\'](?:api[_-]?key|access[_-]?token|bearer[_-]?token|client[_-]?secret|password)["\'][ \t]*:[ \t]*["\'][A-Za-z0-9_+/.=-]{8,}["\']|'
    rb'\.apiKey[ \t]*=[ \t]*["\'][A-Za-z0-9_+/.=-]{8,}["\']|'
    rb'<key>(?:API_KEY|apiKey|token|password)</key>\s*<string>[^<]{8,}</string>|'
    rb'Bearer\s+[A-Za-z0-9_+/.=-]{12,}|sk-(?:proj-|ant-|live_|test_)[A-Za-z0-9_-]{12,}', re.I)


class AuditError(Exception):
    pass


def require(condition, code):
    if not condition:
        raise AuditError(code)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_plist(path):
    require(path.is_file(), 'missing_plist')
    value = plistlib.loads(path.read_bytes())
    require(isinstance(value, dict), 'invalid_plist')
    return value


def run(args, *, code, data=None):
    try:
        result = subprocess.run(args, input=data, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        raise AuditError(code) from None
    require(result.returncode == 0, code)
    return result.stdout


def files(root):
    require(root.is_dir(), 'missing_bundle')
    paths = sorted(root.rglob('*'))
    require(not root.is_symlink() and all(not p.is_symlink() for p in paths), 'bundle_symlink_not_supported')
    return [p for p in paths if p.is_file()]


def is_macho(path):
    with path.open('rb') as stream:
        return stream.read(4) in MACHO_MAGIC


def resources(root):
    return {str(p.relative_to(root)): digest(p) for p in files(root)
            if p.name not in {'Info.plist', 'embedded.mobileprovision'}
            and not {'_CodeSignature', 'Headers', 'Modules'} & set(p.relative_to(root).parts)
            and not is_macho(p)}


def inspect_macho(path):
    raw = path.read_bytes()
    try:
        if raw[:4] in {b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}:
            wide = raw[:4] == b'\xca\xfe\xba\xbf'
            count = struct.unpack_from('>I', raw, 4)[0]
            require(1 <= count <= 8, 'invalid_macho')
            entries = [struct.unpack_from('>IIQQII' if wide else '>IIIII', raw, 8 + i * (32 if wide else 20))
                       for i in range(count)]
            slices = [raw[e[2]:e[2] + e[3]] for e in entries]
            require(all(e[2] + e[3] <= len(raw) for e in entries), 'invalid_macho')
        else:
            slices = [raw]
        result = []
        for binary in slices:
            require(binary[:4] in {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'}, 'invalid_macho')
            wide = binary[:4] == b'\xcf\xfa\xed\xfe'
            cpu, _, kind, commands, size = struct.unpack_from('<IIIII', binary, 4)
            pos = 32 if wide else 28
            end = pos + size
            require(cpu in {0x100000c, 0x200000c} and end <= len(binary), 'invalid_device_macho')
            platform, links, rpaths, identity, code_hash = None, [], [], None, None
            for _ in range(commands):
                command, length = struct.unpack_from('<II', binary, pos)
                require(length >= 8 and pos + length <= end, 'invalid_macho')
                if command == 0x32:
                    require(length >= 24, 'invalid_macho')
                    platform = struct.unpack_from('<I', binary, pos + 8)[0]
                if command == 0x1b:
                    require(length == 24, 'invalid_macho')
                    identity = binary[pos + 8:pos + 24].hex()
                if command == (0x19 if wide else 1):
                    section_count = struct.unpack_from('<I', binary, pos + (64 if wide else 48))[0]
                    for index in range(section_count):
                        section = pos + (72 if wide else 56) + index * (80 if wide else 68)
                        require(section + (80 if wide else 68) <= pos + length, 'invalid_macho')
                        if binary[section:section + 16].rstrip(b'\0') == b'__text' and \
                                binary[section + 16:section + 32].rstrip(b'\0') == b'__TEXT':
                            text_size = struct.unpack_from('<Q' if wide else '<I', binary, section + (40 if wide else 36))[0]
                            offset = struct.unpack_from('<I', binary, section + (48 if wide else 40))[0]
                            require(text_size > 0 and offset + text_size <= len(binary), 'invalid_macho')
                            code_hash = hashlib.sha256(binary[offset:offset + text_size]).hexdigest()
                if command in {0xc, 0x80000018, 0x8000001f}:
                    require(length >= 24, 'invalid_macho')
                    offset = struct.unpack_from('<I', binary, pos + 8)[0]
                    require(24 <= offset < length, 'invalid_macho')
                    links.append(binary[pos + offset:pos + length].split(b'\0')[0].decode('utf-8'))
                if command == 0x8000001c:
                    require(length >= 12, 'invalid_macho')
                    offset = struct.unpack_from('<I', binary, pos + 8)[0]
                    require(12 <= offset < length, 'invalid_macho')
                    rpaths.append(binary[pos + offset:pos + length].split(b'\0')[0].decode('utf-8'))
                pos += length
            require(pos == end, 'invalid_macho')
            require(identity is not None and code_hash is not None, 'missing_macho_uuid_or_text')
            result.append({'cpu': cpu, 'kind': kind, 'platform': platform, 'links': sorted(links), 'rpaths': sorted(rpaths),
                           'uuid': identity, 'textSHA256': code_hash})
        return result
    except (IndexError, struct.error, UnicodeError):
        raise AuditError('invalid_macho') from None


def verify_private_material(paths, private_values=()):
    for path in paths:
        require(not (path.name.lower().startswith('.env') or path.suffix.lower() in
                     {'.p8', '.p12', '.pfx', '.key', '.pem', '.keychain', '.keychain-db'}), 'bundled_private_material')
        if path.name == 'embedded.mobileprovision' or '_CodeSignature' in path.parts:
            continue
        with path.open('rb') as stream:
            overlap = b''
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                require(PRIVATE_CONTENT.search(overlap + chunk) is None, 'bundled_private_material')
                require(not any(value in overlap + chunk for value in private_values), 'bundled_private_material')
                overlap = chunk[-max([512] + [len(value) for value in private_values]):]


def verify_info(app, source, target, version, build):
    info = load_plist(app / 'Info.plist')
    identity, executable, platform = (HOST_ID, 'Spottr', 2) if target == 'host' else (WATCH_ID, 'SpottrWatch', 4)
    require(info.get('CFBundleIdentifier') == identity and info.get('CFBundleExecutable') == executable
            and info.get('CFBundlePackageType') == 'APPL', 'bundle_identity_mismatch')
    require(info.get('CFBundleShortVersionString') == version and info.get('CFBundleVersion') == build,
            'bundle_version_mismatch')
    require(info.get('ITSAppUsesNonExemptEncryption') is False, 'encryption_flag_mismatch')
    if target == 'watch':
        require(info.get('WKCompanionAppBundleIdentifier') == HOST_ID and info.get('WKApplication') is True,
                'companion_identity_mismatch')
    frozen = load_plist(source / 'Info.plist')
    keys = ['NSCameraUsageDescription'] if target == 'host' else [
        'NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription', 'NSMotionUsageDescription']
    require(all(isinstance(frozen.get(k), str) and frozen[k].strip() and info.get(k) == frozen[k] for k in keys),
            'usage_description_mismatch')
    slices = inspect_macho(app / executable)
    require(all(s['kind'] == 2 and s['platform'] == platform for s in slices), 'app_not_device_executable')
    return info, slices


def audit_layout(host, source, version, build):
    host, source = Path(host), Path(source)
    paths = files(host)
    watch = host / 'Watch/SpottrWatch.app'
    watch_paths = files(watch)
    require(not any(p.name in {'pose_landmarker_lite.task', 'MediaPipe-LICENSE.txt', 'coach-guidance.json'}
                    or 'SmartSpectra' in str(p.relative_to(watch)) or p.suffix in {'.tflite', '.binarypb'}
                    or 'MediaPipe' in str(p.relative_to(watch)) for p in watch_paths),
            'watch_contains_host_only_resource')
    verify_private_material(paths)
    host_info, host_slices = verify_info(host, source / 'Native/iOS', 'host', version, build)
    watch_info, watch_slices = verify_info(watch, source / 'Native/Watch', 'watch', version, build)
    mapping = {'PrivacyInfo.xcprivacy': 'Native/iOS/PrivacyInfo.xcprivacy',
               'Watch/SpottrWatch.app/PrivacyInfo.xcprivacy': 'Native/Watch/PrivacyInfo.xcprivacy',
               'pose_landmarker_lite.task': 'Native/Resources/pose_landmarker_lite.task',
               'MediaPipe-LICENSE.txt': 'Native/Resources/MediaPipe-LICENSE.txt',
               'coach-guidance.json': 'Shared/Core/Resources/coach-guidance.json'}
    require(all((host / dest).is_file() and (source / origin).is_file()
                and digest(host / dest) == digest(source / origin) for dest, origin in mapping.items()),
            'source_resource_mismatch')
    for privacy in [host / 'PrivacyInfo.xcprivacy', watch / 'PrivacyInfo.xcprivacy']:
        require(isinstance(load_plist(privacy).get('NSPrivacyAccessedAPITypes'), list), 'invalid_privacy_manifest')
    guidance = json.loads((host / 'coach-guidance.json').read_bytes())
    require(guidance.get('version') == 1 and bool(guidance.get('sources')), 'invalid_guidance_resource')
    sdk = host / 'Frameworks/SmartSpectra.framework'
    require(sdk.is_dir(), 'missing_smartspectra_framework')
    canonical = source / SDK_PATH
    expected = resources(canonical)
    require(MODEL_NAMES | {'PrivacyInfo.xcprivacy'} <= set(expected) and resources(sdk) == expected,
            'sdk_resources_mismatch')
    sdk_info, original_info = load_plist(sdk / 'Info.plist'), load_plist(canonical / 'Info.plist')
    require(all(sdk_info.get(k) == original_info.get(k) for k in
                ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleShortVersionString', 'CFBundleVersion'])
            and sdk_info.get('CFBundleExecutable') == 'SmartSpectra', 'sdk_identity_mismatch')
    embedded_slices = inspect_macho(sdk / 'SmartSpectra')
    require(all(s['kind'] == 6 and s['platform'] == 2 for s in embedded_slices),
            'sdk_not_device_dynamic_library')
    require(embedded_slices == inspect_macho(canonical / 'SmartSpectra'), 'sdk_code_mismatch')
    require(all(SDK_LINK in s['links'] for s in host_slices), 'host_smartspectra_link_missing')
    require(all('@executable_path/Frameworks' in s['rpaths'] for s in host_slices), 'host_framework_runpath_missing')
    require(not any('MediaPipe' in str(p.relative_to(host / 'Frameworks')) for p in files(host / 'Frameworks')),
            'static_mediapipe_unexpectedly_embedded')
    load_plist(sdk / 'PrivacyInfo.xcprivacy')
    return {'hostInfo': host_info, 'watchInfo': watch_info, 'sdkInfo': sdk_info, 'resources': resources(host),
            'hostMachO': host_slices, 'watchMachO': watch_slices, 'sdkMachO': embedded_slices,
            'canonicalSDKBinarySHA256': digest(canonical / 'SmartSpectra')}


def verify_source(repo, source, commit):
    require(re.fullmatch('[a-f0-9]{40}', commit) is not None, 'invalid_source_commit')
    names = run(['git', '-C', str(repo), 'ls-tree', '-r', '--name-only', commit, '--', 'Native', 'Shared'],
                code='source_tree_unavailable').decode().splitlines()
    require(bool(names), 'empty_source_tree')
    actual = {str(p.relative_to(source)) for directory in ['Native', 'Shared'] for p in files(source / directory)
              if not str(p.relative_to(source)).startswith('Native/Vendor/')}
    require(actual == set(names), 'source_snapshot_file_mismatch')
    for name in names:
        expected = run(['git', '-C', str(repo), 'show', commit + ':' + name], code='source_object_unavailable')
        require((source / name).read_bytes() == expected, 'source_snapshot_bytes_mismatch')
    return len(names)


def uuid_map(path):
    output = run(['xcrun', 'dwarfdump', '--uuid', str(path)], code='uuid_tool_failed').decode()
    found = re.findall(r'UUID: ([A-Fa-f0-9-]{36}) \(([^)]+)\)', output)
    require(bool(found), 'missing_binary_uuid')
    return {arch: value.upper() for value, arch in found}


def verify_vendor(vendor, previous, approved):
    current = {str(p.relative_to(vendor)): digest(p) for p in files(vendor)}
    require(bool(approved) and current == approved, 'vendor_manifest_mismatch')
    old_mediapipe = {str(p.relative_to(previous)): digest(p) for p in files(previous)
                     if p.relative_to(previous).parts[0].startswith('MediaPipe')}
    new_mediapipe = {name: value for name, value in current.items() if name.split('/')[0].startswith('MediaPipe')}
    require(bool(old_mediapipe) and new_mediapipe == old_mediapipe, 'mediapipe_changed_since_baseline')
    return len(current)


def verify_signing_material(ent, profile, certificate, identity, team, watch, now):
    require(ent.get('application-identifier') == team + '.' + identity
            and ent.get('com.apple.developer.team-identifier') == team, 'signing_identity_mismatch')
    require(not ent.get('get-task-allow', False), 'debug_entitlement_present')
    require(ent.get('com.apple.developer.healthkit', False) == watch, 'healthkit_entitlement_mismatch')
    allowed = {'application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow',
               'keychain-access-groups', 'beta-reports-active'}
    if watch:
        allowed |= {'com.apple.developer.healthkit', 'com.apple.developer.healthkit.access'}
    require(set(ent) <= allowed, 'unexpected_entitlement')
    require(profile.get('TeamIdentifier') == [team] and profile.get('Entitlements', {}).get('application-identifier')
            == team + '.' + identity, 'profile_identity_mismatch')
    permitted = profile.get('Entitlements', {})
    for key, value in ent.items():
        expected = permitted.get(key)
        if isinstance(value, list):
            require(isinstance(expected, list) and all(any(fnmatch.fnmatchcase(item, pattern) for pattern in expected)
                    for item in value), 'profile_entitlement_mismatch')
        else:
            require(value == expected or (key == 'get-task-allow' and value is False and expected is None),
                    'profile_entitlement_mismatch')
    require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices')
            and not profile.get('Entitlements', {}).get('get-task-allow', False), 'not_appstore_profile')
    require(profile['ExpirationDate'].replace(tzinfo=dt.timezone.utc) > now, 'profile_expired')
    require(certificate in profile['DeveloperCertificates'], 'signer_not_in_profile')


def signer_certificate(app):
    with tempfile.TemporaryDirectory(prefix='spottr-audit-cert-') as directory:
        prefix = Path(directory) / 'signer-'
        run(['codesign', '-d', '--extract-certificates=' + str(prefix), str(app)], code='signer_unavailable')
        certificate = Path(str(prefix) + '0').read_bytes()
        run(['openssl', 'x509', '-inform', 'DER', '-checkend', '0', '-noout'], data=certificate,
            code='signer_certificate_expired')
    return certificate


def verify_signing(app, identity, team, watch=False):
    run(['codesign', '--verify', '--deep', '--strict', str(app)], code='strict_signature_failed')
    ent = plistlib.loads(run(['codesign', '-d', '--entitlements', ':-', str(app)], code='entitlements_unavailable'))
    profile = plistlib.loads(run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')],
                                code='profile_decode_failed'))
    certificate = signer_certificate(app)
    verify_signing_material(ent, profile, certificate, identity, team, watch, dt.datetime.now(dt.timezone.utc))
    return ent


def audit_release(args):
    require(re.fullmatch(r'\d+(?:\.\d+){0,2}', args.version) and
            re.fullmatch(r'\d+(?:\.\d+){0,2}', args.build), 'invalid_version')
    count = verify_source(args.repo, args.source_root, args.source_commit)
    vendor_count = verify_vendor(args.source_root / 'Native/Vendor', args.previous_vendor_root,
                                 json.loads(args.approved_vendor_manifest.read_bytes()))
    archive_host = args.archive / 'Products/Applications/Spottr.app'
    layouts = [audit_layout(host, args.source_root, args.version, args.build) for host in [archive_host, args.export_app]]
    require(layouts[0] == layouts[1], 'archive_export_layout_mismatch')
    private_values = []
    for path in args.secret_file:
        require(path.is_file() and path.stat().st_mode & 0o777 == 0o600, 'secret_file_must_be_private')
        value = path.read_bytes().strip()
        require(8 <= len(value) <= 8192, 'invalid_secret_file')
        private_values.append(value)
    for host in [archive_host, args.export_app]:
        verify_private_material(files(host), private_values)
    signed = []
    for host in [archive_host, args.export_app]:
        rows = []
        for app, identity, name, watch in [(host, HOST_ID, 'Spottr', False),
                                          (host / 'Watch/SpottrWatch.app', WATCH_ID, 'SpottrWatch', True)]:
            rows.append(verify_signing(app, identity, args.team_id, watch))
            dsym = args.archive / f'dSYMs/{name}.app.dSYM/Contents/Resources/DWARF/{name}'
            require(uuid_map(app / name) == uuid_map(dsym), 'dsym_uuid_mismatch')
        run(['codesign', '--verify', '--strict', str(host / 'Frameworks/SmartSpectra.framework')],
            code='sdk_signature_failed')
        require(signer_certificate(host / 'Frameworks/SmartSpectra.framework') == signer_certificate(host),
                'sdk_signer_mismatch')
        sdk_ent = plistlib.loads(run(['codesign', '-d', '--entitlements', ':-', str(host / 'Frameworks/SmartSpectra.framework')],
                                    code='sdk_entitlements_unavailable') or b'<plist version="1.0"><dict/></plist>')
        require(not sdk_ent.get('get-task-allow', False), 'sdk_debug_entitlement_present')
        signed.append(rows)
    require(signed[0] == signed[1], 'archive_export_entitlements_mismatch')
    return {'status': 'passed', 'sourceCommit': args.source_commit, 'trackedNativeSharedFilesVerified': count,
            'approvedVendorFilesVerified': vendor_count,
            'version': args.version, 'build': args.build, 'resourceSHA256': layouts[0]['resources'],
            'ipaSHA256': digest(args.ipa),
            'canonicalSDKBinarySHA256': layouts[0]['canonicalSDKBinarySHA256'],
            'scope': 'Archive/export packaging, signatures, App Store profiles and app dSYM UUIDs only; '
                     'no runtime, device, provider, privacy/legal acceptance, Apple validation or upload.'}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise AuditError('invalid_arguments')


def extract_ipa(ipa, destination):
    with zipfile.ZipFile(ipa) as zipped:
        entries = zipped.infolist()
        require(bool(entries) and sum(e.file_size for e in entries) <= 1024 * 1024 * 1024, 'ipa_size_limit')
        names = set()
        for entry in entries:
            path = PurePosixPath(entry.filename)
            require(not path.is_absolute() and '..' not in path.parts and '\\' not in entry.filename
                    and ':' not in entry.filename and bool(path.parts), 'unsafe_ipa_path')
            require(not stat.S_ISLNK(entry.external_attr >> 16), 'ipa_symlink_not_supported')
            require(str(path) not in names, 'duplicate_ipa_entry')
            names.add(str(path))
        require({str(PurePosixPath(name).parts[1]) for name in names if
                 len(PurePosixPath(name).parts) > 1 and PurePosixPath(name).parts[0] == 'Payload'} == {'Spottr.app'},
                'unexpected_ipa_payload')
        zipped.extractall(destination)
    return destination / 'Payload/Spottr.app'


def main():
    try:
        parser = Parser(add_help=False)
        for name in ['archive', 'ipa', 'source-root', 'repo', 'previous-vendor-root', 'approved-vendor-manifest']:
            parser.add_argument('--' + name, required=True, type=Path)
        for name in ['source-commit', 'version', 'build', 'team-id']:
            parser.add_argument('--' + name, required=True)
        parser.add_argument('--secret-file', type=Path, action='append', default=[])
        args = parser.parse_args()
        with tempfile.TemporaryDirectory(prefix='spottr-audit-ipa-') as directory:
            args.export_app = extract_ipa(args.ipa, Path(directory))
            result = audit_release(args)
    except AuditError as error:
        result = {'status': 'failed', 'code': str(error)}
    except Exception:
        result = {'status': 'failed', 'code': 'artifact_inspection_failed'}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
