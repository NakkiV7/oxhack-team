#!/usr/bin/env python3
"""Opt-in bounded native QA. Inputs and traces remain outside the checkout."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=pathlib.Path, required=True)
parser.add_argument('--derived-data', type=pathlib.Path, required=True)
parser.add_argument('--split', choices=['development', 'heldOut'], required=True)
parser.add_argument('--tag', required=True)
parser.add_argument('--fps', type=float, default=10)
parser.add_argument('--sampling', choices=['minimumInterval', 'grid'], default='minimumInterval')
parser.add_argument('--trial', action='append')
parser.add_argument('--include-supplement', action='store_true')
parser.add_argument('--sensitivity-reference', type=pathlib.Path)
parser.add_argument('--candidate-freeze', default='candidate-freeze.json')
parser.add_argument('--promoted-development', action='store_true')
parser.add_argument('--resolution', choices=['640', '720p'], default='640')
args = parser.parse_args()
if not 5 <= args.fps <= 30 or pathlib.Path(args.tag).name != args.tag:
    parser.error('Use 5–30 fps and a simple new output tag')
root = args.root.resolve()
freeze_path = root / 'task4' / args.candidate_freeze
if pathlib.Path(args.candidate_freeze).name != args.candidate_freeze:
    parser.error('Use a simple candidate freeze filename')
if args.promoted_development:
    promotion = json.loads((root / 'task4/candidate2-promotions.json').read_text())
    if args.split != 'heldOut' or not args.trial or not set(args.trial) <= set(promotion['promotedTrialIDs']):
        parser.error('Consumed development replay must explicitly select only promoted trials')
if args.split == 'heldOut' and not args.promoted_development:
    if not freeze_path.exists():
        parser.error('Freeze the candidate before consuming held-out sources')
    frozen = json.loads(freeze_path.read_text())
    for name, digest in frozen['sourceCodeSHA256'].items():
        if hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() != digest:
            parser.error('Candidate source differs from the pre-held-out freeze: ' + name)
    if args.include_supplement or args.fps != frozen['primaryFPSCap'] or args.sampling != frozen['primarySampling']:
        parser.error('Held-out primary replay must use the frozen production cadence and original sources')
sensitivity = json.loads(args.sensitivity_reference.read_text()) if args.sensitivity_reference else None
if sensitivity and (args.trial != [sensitivity['originalTrialID']] or not (args.promoted_development or args.split == 'development')):
    parser.error('A sensitivity reference requires one original or explicitly promoted development trial')
output = root / 'task4' / args.tag
output.mkdir(parents=True, exist_ok=False)
config = dict(root=str(root), output=str(output), split=args.split, fps=args.fps, trialIDs=args.trial, includeSupplement=args.include_supplement,
              inputWidth=1280 if args.resolution == '720p' else 640,
              sensitivityWindow=sensitivity, inputHeight=720 if args.resolution == '720p' else 640, sampling=args.sampling)
config_path = output / 'config.json'
config_path.write_text(json.dumps(config, indent=2) + '\n')
sha = lambda data: hashlib.sha256(data).hexdigest()
files = sorted(str(p) for p in pathlib.Path('Shared/Core').glob('*.swift')) + [
    'Native/iOS/PoseDetector.swift', 'Native/iOS/VisionWorker.swift', 'Native/iOS/TrainingStore.swift',
    'Tests/iOS/PoseDetectorTests.swift', 'scripts/validate-public-videos.py']
input_hashes = {p: sha(pathlib.Path(p).read_bytes()) for p in files}
build_command = ['xcodebuild', 'build-for-testing', '-project', 'Spottr.xcodeproj', '-scheme', 'Spottr',
    '-destination', 'platform=iOS Simulator,id=BF27AFBA-FF1E-4484-A3BD-42916CEB1170',
    '-derivedDataPath', str(args.derived_data.resolve()), '-jobs', '2', '-parallel-testing-enabled', 'NO',
    'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO']
with (output / 'build.log').open('w') as log:
    build_status = subprocess.run(build_command, stdout=log, stderr=subprocess.STDOUT).returncode
if build_status:
    raise SystemExit(build_status)
if input_hashes != {p: sha(pathlib.Path(p).read_bytes()) for p in files}:
    raise SystemExit('Source changed during build; reject ambiguous binary provenance')
products = args.derived_data.resolve() / 'Build' / 'Products'
original = max(products.glob('Spottr_*.xctestrun'), key=lambda p: p.stat().st_mtime)
plan = plistlib.loads(original.read_bytes())
targets = [target for group in plan.get('TestConfigurations', []) for target in group['TestTargets']] if 'TestConfigurations' in plan else [plan['SpottrTests']]
for target in targets:
    if target['BlueprintName'] == 'SpottrTests':
        target.setdefault('EnvironmentVariables', {})['SPOTTR_PUBLIC_VIDEO_CONFIG'] = str(config_path)
run_file = products / ('PublicVideo-' + args.tag + '.xctestrun')
run_file.write_bytes(plistlib.dumps(plan))
command = ['xcodebuild', 'test-without-building', '-xctestrun', str(run_file), '-destination',
           'platform=iOS Simulator,id=BF27AFBA-FF1E-4484-A3BD-42916CEB1170', '-jobs', '2',
           '-parallel-testing-enabled', 'NO', '-only-testing:SpottrTests/PublicVideoValidationTests',
           '-resultBundlePath', str(output / 'native.xcresult'),
           'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO']
receipt = dict(command=command, buildCommand=build_command, compiledSourceSHA256=input_hashes,
    compiledBinarySHA256={str(p): sha(p.read_bytes()) for p in [products / 'Debug-iphonesimulator/Spottr.app/Spottr', products / 'Debug-iphonesimulator/Spottr.app/Spottr.debug.dylib', products / 'Debug-iphonesimulator/Spottr.app/PlugIns/SpottrTests.xctest/SpottrTests']}, codeHEAD=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    dirtyDiffSHA256=sha(subprocess.check_output(['git', 'diff', 'HEAD'])),
    sourceCodeSHA256={p: sha(pathlib.Path(p).read_bytes()) for p in files},
    sdkBinarySHA256=sha(pathlib.Path('Native/Vendor/MediaPipeTasksVision.xcframework/ios-arm64-simulator/MediaPipeTasksVision.framework/MediaPipeTasksVision').read_bytes()),
    xcode=subprocess.check_output(['xcodebuild', '-version'], text=True),
    configSHA256=sha(config_path.read_bytes()), xctestrunSHA256=sha(run_file.read_bytes()),
    candidateFreezeSHA256=sha(freeze_path.read_bytes()) if freeze_path.exists() and not args.promoted_development else None,
    evaluationStatus='consumed development' if args.promoted_development else 'frozen candidate re-evaluation',
    sensitivityReferenceSHA256=sha(args.sensitivity_reference.read_bytes()) if args.sensitivity_reference else None,
    promotionManifestSHA256=sha((root / 'task4/candidate2-promotions.json').read_bytes()) if (root / 'task4/candidate2-promotions.json').exists() else None)
(output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
with (output / 'native.log').open('w') as log:
    status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
receipt['exitCode'] = status
results_path = output / 'results.json'
if status == 0:
    if not results_path.exists():
        raise SystemExit('Native command returned success without replay results; NOT acceptance')
    results = json.loads(results_path.read_text())['results']
    if not results or sum(row['frames'] for row in results) == 0:
        raise SystemExit('No clips/frames replayed; NOT acceptance')
    receipt['completedTrials'] = len(results)
    receipt['processedFrames'] = sum(row['frames'] for row in results)
(output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ['exitCode', 'completedTrials', 'processedFrames'] if k in receipt}))
raise SystemExit(status)
