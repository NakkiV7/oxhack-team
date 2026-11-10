import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const source = file => readFile(new URL('../../'+file,import.meta.url),'utf8');
const privacyManifest = () => JSON.parse(execFileSync('plutil', [
 '-convert','json','-o','-',fileURLToPath(new URL('../../Native/iOS/PrivacyInfo.xcprivacy',import.meta.url))
], {encoding:'utf8'}));
const collectedPurposes = {
 EmailAddress: ['AppFunctionality'],
 UserID: ['AppFunctionality'],
 DeviceID: ['AppFunctionality','Analytics'],
 Fitness: ['AppFunctionality','ProductPersonalization','Analytics'],
 ProductInteraction: ['Analytics'],
 CustomerSupport: ['AppFunctionality']
};
test('native passkey entitlement is scoped to exact webcredentials domain with Apple sign-in',async()=>{
 const value=await source('Native/iOS/Spottr.entitlements');
 assert.match(value,/webcredentials:spottr\.omarchoudhry\.co\.uk/);
 assert.match(value,/com\.apple\.developer\.applesignin/);
 assert.doesNotMatch(value,/applinks:/);
 assert.match(await source('scripts/generate-project.rb'),/com\.apple\.SignInWithApple/);
});
test('privacy manifest declares exactly six linked data types without tracking',()=>{
 const manifest=privacyManifest();
 assert.equal(manifest.NSPrivacyTracking,false);
 const entries=manifest.NSPrivacyCollectedDataTypes;
 assert.deepEqual(entries.map(entry=>entry.NSPrivacyCollectedDataType).sort(),
  Object.keys(collectedPurposes).map(type=>'NSPrivacyCollectedDataType'+type).sort());
 for(const entry of entries){
  assert.equal(entry.NSPrivacyCollectedDataTypeLinked,true,entry.NSPrivacyCollectedDataType);
  assert.equal(entry.NSPrivacyCollectedDataTypeTracking,false,entry.NSPrivacyCollectedDataType);
 }
});
test('privacy manifest assigns the exact supported purposes to each data type',()=>{
 const entries=privacyManifest().NSPrivacyCollectedDataTypes;
 for(const [type,purposes] of Object.entries(collectedPurposes)){
  const name='NSPrivacyCollectedDataType'+type;
  const entry=entries.find(entry=>entry.NSPrivacyCollectedDataType===name);
  assert.ok(entry,`Missing ${name}`);
  assert.deepEqual([...entry.NSPrivacyCollectedDataTypePurposes].sort(),
   purposes.map(purpose=>'NSPrivacyCollectedDataTypePurpose'+purpose).sort(),name);
 }
});
test('ordinary native suite separates human-operated acceptance without hiding StoreKit platform failures',async()=>{
 const scheme=await source('Spottr.xcodeproj/xcshareddata/xcschemes/Spottr.xcscheme');
 assert.match(scheme, /SkippedTests/);
 for(const name of ['testExternalJuniorMembershipRestoreRequiresGuardian','testPublicCoachAdjustmentAndActualInsightsTab','testExternalWholeWorkoutCameraManualEffortAndFinished'])assert.ok(scheme.includes(name));
 assert.doesNotMatch(scheme.match(/<SkippedTests>[\s\S]*?<\/SkippedTests>/)?.[0]??'', /MembershipStoreKitTests/);
 const operator=await source('Spottr.xcodeproj/xcshareddata/xcschemes/SpottrExternalAcceptance.xcscheme');
 assert.match(operator,/SelectedTests/);assert.match(operator,/testExternalJuniorMembershipRestoreRequiresGuardian/);
});
