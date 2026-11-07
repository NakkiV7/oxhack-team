import test from 'node:test';
import assert from 'node:assert/strict';
import site from '../src/index.ts';
import { fixture, origin } from './native-fixture.ts';

const week = () => { const d = new Date(); d.setUTCHours(0,0,0,0); d.setUTCDate(d.getUTCDate() - (d.getUTCDay()+6)%7); return d.toISOString().slice(0,10); };
const snapshot = () => ({version:1,sequence:1,kind:'workout',week:week(),tag:crypto.randomUUID(),counts:{sessions:2,sets:6,reps:40,minutes:10,squat:2,manual:2,effortModerate:6}});
test('consented coarse weekly statistics reach the separate no-auth endpoint without cookies', async () => {
 const f = await fixture(); try {
 const response = await site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(snapshot())}),{...f.env,ASSETS:{fetch:async()=>new Response('missing',{status:404})}});
 assert.equal(response.status,202); assert.deepEqual(await response.json(),{accepted:true}); assert.equal(response.headers.has('Set-Cookie'),false);
 } finally {await f.mf.dispose();}
});

test('analytics rejects sensitive extra fields, credentials, invalid weeks, excessive counters and byte bodies', async () => {
 const f = await fixture(); try {
 const env={...f.env,ASSETS:{fetch:async()=>new Response('missing',{status:404})}};
 for (const body of [{...snapshot(),accountID:'private'}, {...snapshot(),counts:{sessions:1,heartRate:90}}, {...snapshot(),counts:{sessions:90000}}, {...snapshot(),week:'2020-01-06'}]) {
 const r=await site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}),env); assert.equal(r.status,400);
 }
 for (const header of ['Authorization','Cookie','X-Spottr-Proof']) {
 const r=await site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json',[header]:'secret'},body:JSON.stringify(snapshot())}),env); assert.equal(r.status,400);
 }
 const huge=await site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json'},body:' '.repeat(4097)}),env);assert.equal(huge.status,413);
 assert.equal((await site.fetch(new Request(origin+'/api/analytics/v1/raw'),env)).status,404);
 }finally{await f.mf.dispose();}
});

test('ten installation tags qualify each bucket independently, replacements never double count and older snapshots cannot overwrite', async () => {
 const {surfacedAnalytics}=await import('../src/analytics.ts');const f=await fixture();try{
 const env={...f.env,ASSETS:{fetch:async()=>new Response('missing',{status:404})}};
 const send=(body:unknown)=>site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}),env);
 const samples=Array.from({length:10},()=>snapshot());
 for(const [i,sample] of samples.entries()){await send({...sample,sequence:1,counts:{sessions:2,sets:6,...i===0?{squat:2}:{}}});}
 assert.deepEqual(await surfacedAnalytics(f.db,week(),'workout'),{sessions:{total:20,contributors:10},sets:{total:60,contributors:10}});
 const first=samples[0];assert.ok(first);
 assert.equal((await send({...first,sequence:3,counts:{sessions:3,sets:7}})).status,202);
 assert.equal((await send({...first,sequence:2,counts:{sessions:100,sets:100}})).status,202);
 assert.equal((await surfacedAnalytics(f.db,week(),'workout'))['sessions']?.total,21);
 for(let i=0;i<20;i++)await send({...first,sequence:4+i,counts:{sessions:3}});
 assert.equal((await send({...first,sequence:100,counts:{sessions:3}})).status,429);
 }finally{await f.mf.dispose();}
});

test('public summary exposes only the completed week and thresholded buckets without tags or raw snapshots', async()=>{
 const f=await fixture();try{
 const env={...f.env,ASSETS:{fetch:async()=>new Response('missing',{status:404})}};
 const previous=new Date(Date.parse(week()+'T00:00:00Z')-7*86400000).toISOString().slice(0,10);
 for(let i=0;i<10;i++) {
 const input={...snapshot(),week:previous,counts:{sessions:2,...i===0?{squat:1}:{}}};
 assert.equal((await site.fetch(new Request(origin+'/api/analytics/v1/weekly',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)}),env)).status,202);
 }
 const response=await site.fetch(new Request(origin+'/api/analytics/v1/summary'),env);
 assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{week:previous,workout:{sessions:{total:20,contributors:10}},usage:{}});
 assert.equal((await site.fetch(new Request(origin+'/api/analytics/v1/summary?tag=private'),env)).status,404);
 }finally{await f.mf.dispose();}
});
