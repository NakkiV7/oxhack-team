import { z } from 'zod';
import type { Database } from './auth.ts';
const count = z.number().int().min(0).max(2000).optional();
const workoutCounts = z.object({sessions:count,sets:count,reps:z.number().int().min(0).max(20000).multipleOf(10).optional(),minutes:z.number().int().min(0).max(10000).multipleOf(5).optional(),squat:count,push:count,core:count,cardio:count,mobility:count,balance:count,camera:count,manual:count,watch:count,trackingRecoveries:count,effortEasy:count,effortModerate:count,effortHard:count}).strict();
const usageCounts = z.object({today:count,programme:count,practice:count,insights:count,coach:count,quests:count}).strict();
const common = {version:z.literal(1),week:z.iso.date(),tag:z.uuid(),sequence:z.number().int().min(1).max(1000000)};
export const analyticsSchema = z.discriminatedUnion('kind',[
 z.object({...common,kind:z.literal('workout'),counts:workoutCounts}).strict(),
 z.object({...common,kind:z.literal('usage'),counts:usageCounts}).strict()
]);
export type AnalyticsSnapshot = z.infer<typeof analyticsSchema>;
const WEEK=7*86400000;
export function analyticsWeek(now:number):string {
 const date=new Date(now);date.setUTCHours(0,0,0,0);date.setUTCDate(date.getUTCDate()-(date.getUTCDay()+6)%7);return date.toISOString().slice(0,10);
}
async function boundedJSON(request:Request):Promise<unknown> {
 const reader=request.body?.getReader();if(!reader) throw new Error('invalid');
 const chunks:Uint8Array[]=[];let size=0;
 while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>4096){await reader.cancel();throw new RangeError('large');}chunks.push(next.value);}
 const body=new Uint8Array(size);let offset=0;for(const chunk of chunks){body.set(chunk,offset);offset+=chunk.length;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(body));
}
export async function analyticsRequest(request:Request,db:Database,now=Date.now()):Promise<Response> {
 const url=new URL(request.url);
 if(url.search)return Response.json({error:'not_found'},{status:404});
 if(url.pathname==='/api/analytics/v1/summary'&&request.method==='GET') {
  if(['Authorization','Cookie','X-Spottr-Proof'].some(key=>request.headers.has(key)))return Response.json({error:'invalid_request'},{status:400});
  const week=analyticsWeek(now-WEEK);
  try {return Response.json({week,workout:await surfacedAnalytics(db,week,'workout',now),usage:await surfacedAnalytics(db,week,'usage',now)});}
  catch{return Response.json({error:'unavailable'},{status:503});}
 }
 if(url.pathname!='/api/analytics/v1/weekly'||request.method!=='POST')return Response.json({error:'not_found'},{status:404});
 if(['Authorization','Cookie','X-Spottr-Proof'].some(key=>request.headers.has(key)))return Response.json({error:'invalid_request'},{status:400});
 if(request.headers.get('Content-Type')!=='application/json')return Response.json({error:'invalid_request'},{status:400});
 let input:AnalyticsSnapshot;
 try {input=analyticsSchema.parse(await boundedJSON(request));}
 catch(error){return Response.json({error:'invalid_request'},{status:error instanceof RangeError?413:400});}
 const start=Date.parse(input.week+'T00:00:00Z');
 if(analyticsWeek(start)!==input.week||start>Date.parse(analyticsWeek(now))||start<Date.parse(analyticsWeek(now))-WEEK)return Response.json({error:'invalid_request'},{status:400});
 try {
 const prior=await db.prepare('SELECT sequence FROM analytics_weekly WHERE week=? AND kind=? AND tag=?').bind(input.week,input.kind,input.tag).first<{sequence:number}>();
 if(prior && prior.sequence>=input.sequence)return Response.json({accepted:true},{status:202});
 const day=new Date(now).toISOString().slice(0,10);
 const result=await db.prepare(`INSERT INTO analytics_weekly(week,kind,tag,counts,updates,expires_at,last_day,sequence) SELECT ?,?,?,?,1,?,?,? WHERE (SELECT COALESCE(SUM(updates),0) FROM analytics_weekly WHERE last_day=?)<3000 AND (SELECT COUNT(*) FROM analytics_weekly)<10000 ON CONFLICT(week,kind,tag) DO UPDATE SET counts=excluded.counts,updates=analytics_weekly.updates+1,last_day=excluded.last_day,sequence=excluded.sequence WHERE analytics_weekly.updates<16 AND analytics_weekly.sequence<excluded.sequence`).bind(input.week,input.kind,input.tag,JSON.stringify(input.counts),start+4*WEEK,day,input.sequence,day).run();
 if(result.meta.changes!==1)return Response.json({error:'quota'},{status:429});
 return Response.json({accepted:true},{status:202});
 }catch{return Response.json({error:'unavailable'},{status:503});}
}
export async function surfacedAnalytics(db:Database,week:string,kind:'workout'|'usage',now=Date.now()):Promise<Record<string,{total:number;contributors:number}>> {
 const rows=await db.prepare(`SELECT j.key AS metric,SUM(j.value) AS total,COUNT(*) AS contributors FROM analytics_weekly w,json_each(w.counts) j WHERE w.week=? AND w.kind=? AND w.expires_at>? AND j.value>0 GROUP BY j.key HAVING COUNT(*)>=10`).bind(week,kind,now).all<{metric:string;total:number;contributors:number}>();
 const allowed=kind==='workout'?Object.keys(workoutCounts.shape):Object.keys(usageCounts.shape);
 return Object.fromEntries(rows.results.filter(row=>allowed.includes(row.metric)).map(row=>[row.metric,{total:row.total,contributors:row.contributors}]));
}
export async function cleanupAnalytics(db:Database,now=Date.now()):Promise<void>{await db.prepare('DELETE FROM analytics_weekly WHERE expires_at<=?').bind(now).run();}
