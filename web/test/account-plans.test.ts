import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './native-fixture.ts';
export const preferences={goals:['balance','weightManagement'],weekdays:[1,3,5],minutesPerSession:20,preferredLocalHour:18,availableSupport:['Wall','Stable chair'],allowsFloorWork:false,excludedExerciseIDs:['wallSit'],startingPoint:'somePractice'};
test('adult consent, strict sanitized preferences, per-account/profile isolation and revision CAS govern cloud plans',async()=>{
 const f=await fixture();try{
 const a=await f.seed(),b=await f.seed(),profileSlot=crypto.randomUUID();
 const body={profileSlot,adultEligible:true,cloudPlanSync:true,expectedRevision:0,preferences,programme:null};
 const saved=await f.signed('/plans/write',body,a.accessToken,a.keys);assert.equal(saved.response.status,200);assert.equal(saved.json['revision'],1);
 assert.equal((await f.signed('/plans/write',body,a.accessToken,a.keys)).response.status,409);
 const query={profileSlot,adultEligible:true,cloudPlanSync:true};
 assert.deepEqual((await f.signed('/plans/read',query,a.accessToken,a.keys)).json['preferences'],preferences);
 assert.equal((await f.signed('/plans/read',query,b.accessToken,b.keys)).response.status,404);
 assert.equal((await f.signed('/plans/read',{...query,profileSlot:crypto.randomUUID()},a.accessToken,a.keys)).response.status,404);
 for(const bad of [{...body,adultEligible:false},{...body,cloudPlanSync:false},{...body,ageContext:{ageYears:30}},{...body,preferences:{...preferences,ageContext:{ageYears:30}}},{...body,preferences:{...preferences,notes:'health note'}},{...body,preferences:{...preferences,availableSupport:['private health note']}}]) assert.equal((await f.signed('/plans/write',bad,a.accessToken,a.keys)).response.status,400);
 assert.equal((await f.signed('/plans/withdraw',{profileSlot,expectedRevision:1},a.accessToken,a.keys)).response.status,200);
 assert.equal((await f.signed('/plans/read',query,a.accessToken,a.keys)).response.status,404);
 }finally{await f.mf.dispose();}
});

test('saved programmes use ISO dates and bounded catalogue DTOs without rationale, history or health content',async()=>{
 const f=await fixture();try{
 const a=await f.seed(),profileSlot=crypto.randomUUID();
 const programme={id:'week:Europe/London:2026-11-02',timeZoneID:'Europe/London',revision:1,days:Array.from({length:7},(_,i)=>({id:`programme:Europe/London:2026-11-0${i+2}`,localDate:`2026-11-0${i+2}`,date:`2026-11-0${i+2}T18:00:00Z`,kind:i===0?'workout':'rest',plan:i===0?{approvedAt:'2026-11-02T10:00:00Z',items:[{exerciseID:'wallPushup',sets:2,target:8,unit:'reps',restSeconds:30}]}:null}))};
 const body={profileSlot,adultEligible:true,cloudPlanSync:true,expectedRevision:0,preferences,programme};
 assert.equal((await f.signed('/plans/write',body,a.accessToken,a.keys)).response.status,200);
 const restored=await f.signed('/plans/read',{profileSlot,adultEligible:true,cloudPlanSync:true},a.accessToken,a.keys);assert.deepEqual(restored.json['programme'],programme);
 for(const invalid of [{...programme,history:[]},{...programme,rationale:'private note'},{...programme,days:[{...programme.days[0],date:12345}]}]) assert.equal((await f.signed('/plans/write',{...body,expectedRevision:1,programme:invalid},a.accessToken,a.keys)).response.status,400);
 }finally{await f.mf.dispose();}
});
test('simultaneous same-revision writes have one winner and withdrawal tombstones prevent stale resurrection',async()=>{
 const f=await fixture();try{
 const a=await f.seed(),profileSlot=crypto.randomUUID(),body={profileSlot,adultEligible:true,cloudPlanSync:true,expectedRevision:0,preferences,programme:null};
 const outcomes=await Promise.all([f.signed('/plans/write',body,a.accessToken,a.keys),f.signed('/plans/write',body,a.accessToken,a.keys)]);
 assert.deepEqual(outcomes.map(v=>v.response.status).sort(),[200,409]);
 assert.equal((await f.signed('/plans/withdraw',{profileSlot,expectedRevision:1},a.accessToken,a.keys)).response.status,200);
 assert.equal((await f.signed('/plans/write',{...body,expectedRevision:1},a.accessToken,a.keys)).response.status,409);
 assert.equal((await f.signed('/plans/write',{...body,expectedRevision:2},a.accessToken,a.keys)).response.status,200);
 }finally{await f.mf.dispose();}
});
