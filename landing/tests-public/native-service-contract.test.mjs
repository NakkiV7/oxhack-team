import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = file => readFile(new URL('../../'+file,import.meta.url),'utf8');
test('native passkey entitlement is scoped to exact webcredentials domain with Apple sign-in',async()=>{
 const value=await source('Native/iOS/Spottr.entitlements');
 assert.match(value,/webcredentials:spottr\.omarchoudhry\.co\.uk/);
 assert.match(value,/com\.apple\.developer\.applesignin/);
 assert.doesNotMatch(value,/applinks:/);
 assert.match(await source('scripts/generate-project.rb'),/com\.apple\.SignInWithApple/);
});
test('privacy manifest declares actually collected identifiers, coarse fitness and usage without tracking',async()=>{
 const value=await source('Native/iOS/PrivacyInfo.xcprivacy');
 for(const type of ['EmailAddress','UserID','DeviceID','Fitness','ProductInteraction'])assert.ok(value.includes('NSPrivacyCollectedDataType'+type),type);
 assert.match(value,/<key>NSPrivacyTracking<\/key>\s*<false\/>/);
 assert.doesNotMatch(value,/NSPrivacyCollectedDataTypeHealth|NSPrivacyCollectedDataTypePreciseLocation|NSPrivacyCollectedDataTypePurchaseHistory/);
});
test('ordinary native suite separates human-operated acceptance without hiding StoreKit platform failures',async()=>{
 const scheme=await source('Spottr.xcodeproj/xcshareddata/xcschemes/Spottr.xcscheme');
 assert.match(scheme, /SkippedTests/);
 for(const name of ['testExternalJuniorMembershipRestoreRequiresGuardian','testPublicCoachAdjustmentAndActualInsightsTab','testExternalWholeWorkoutCameraManualEffortAndFinished'])assert.ok(scheme.includes(name));
 assert.doesNotMatch(scheme.match(/<SkippedTests>[\s\S]*?<\/SkippedTests>/)?.[0]??'', /MembershipStoreKitTests/);
 const operator=await source('Spottr.xcodeproj/xcshareddata/xcschemes/SpottrExternalAcceptance.xcscheme');
 assert.match(operator,/SelectedTests/);assert.match(operator,/testExternalJuniorMembershipRestoreRequiresGuardian/);
});
