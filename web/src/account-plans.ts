import { z } from 'zod';
import { NativeError, isoDateSchema, deviceGuard, deviceArgs, type Context, type Device } from './native-sessions.ts';
export const exerciseIDSchema=z.enum(["wallPushup", "inclinePushup", "kneePushup", "pushup", "closeGripPushup", "gluteBridge", "squat", "halfSquat", "supportedSquat", "wideSquat", "reverseLunge", "splitSquat", "assistedSquat", "deadBug", "plank", "sidePlank", "stepJack", "highKnees", "mountainClimber", "catCow", "hipFlexorStretch", "singleLegBalance", "tempoSquat", "pausedSquat", "tempoPushup", "pausedPushup", "widePushup", "diamondPushup", "wallSit", "calfRaise", "birdDog", "seatedKneeExtension", "quarterSquat", "sitToStand", "narrowSquat", "tempoHalfSquat", "pausedHalfSquat", "forwardLunge", "lateralLunge", "supportedSplitSquat", "standingKneeRaise", "seatedMarch", "standingHipAbduction", "standingHipExtension", "kneePlank", "highPlank", "wallPlank", "kneeSidePlank", "tandemBalance", "frontArmRaise", "lateralArmRaise", "standingBicepsCurl", "wallSlide"]);
const unique=<T>(values:T[])=>new Set(values).size===values.length;
export const networkPreferencesSchema=z.object({
 goals:z.array(z.enum(['strength','stamina','mobility','balance','weightManagement'])).min(1).max(5).refine(unique),
 weekdays:z.array(z.number().int().min(1).max(7)).min(1).max(7).refine(unique),
 minutesPerSession:z.union([z.literal(10),z.literal(20),z.literal(30),z.literal(45)]),
 preferredLocalHour:z.number().int().min(0).max(23),
 availableSupport:z.array(z.enum(['Wall','Stable chair','Stable sofa or counter','Stable support'])).max(4).refine(unique),
 allowsFloorWork:z.boolean(),excludedExerciseIDs:z.array(exerciseIDSchema).max(53).refine(unique),
 startingPoint:z.enum(['startingOut','somePractice','regularPractice','experienced']).nullable()
}).strict();
const localDate=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v=>!Number.isNaN(Date.parse(v))&&new Date(v).toISOString().slice(0,10)===v);
const timeZone=z.string().max(64).refine(value=>{try{new Intl.DateTimeFormat('en',{timeZone:value});return true;}catch{return false;}});
const item=z.object({exerciseID:exerciseIDSchema,sets:z.number().int().min(1).max(10),target:z.number().int().min(1).max(600),unit:z.enum(['reps','seconds']),restSeconds:z.number().int().min(0).max(600)}).strict().refine(v=>v.unit==='seconds'||v.target<=200);
const plan=z.object({items:z.array(item).min(1).max(12).refine(v=>unique(v.map(i=>i.exerciseID))),approvedAt:isoDateSchema}).strict();
const day=z.object({id:z.string().max(128),localDate,date:isoDateSchema,kind:z.enum(['workout','rest','recovery']),plan:plan.nullable()}).strict().refine(v=>v.kind==='rest'?v.plan===null:v.plan!==null);
export const networkProgrammeSchema=z.object({id:z.string().max(128),timeZoneID:timeZone,revision:z.number().int().positive(),days:z.array(day).length(7)}).strict().refine(v=>{
 const first=v.days[0];if(!first||v.id!==`week:${v.timeZoneID}:${first.localDate}`) return false;
 return v.days.every((d,i)=>d.id===`programme:${v.timeZoneID}:${d.localDate}`&&Date.parse(d.localDate)===Date.parse(first.localDate)+i*86400000);
});
const slot=z.object({profileSlot:z.uuid()}).strict();
const consent=slot.extend({adultEligible:z.literal(true),cloudPlanSync:z.literal(true)});
export async function plans(c:Context,d:Device,path:string,input:unknown) {
 if(path==='/plans/read') {
 const value=consent.parse(input);
 const row=await c.sql(`SELECT revision,preferences,programme,updated_at FROM native_plans WHERE user_id=? AND profile_slot=? AND preferences IS NOT NULL AND ${deviceGuard}`,d.user_id,value.profileSlot,...deviceArgs(c,d)).first<{revision:number;preferences:string;programme:string;updated_at:string}>();
 if(!row) throw new NativeError(404,'not_found');
 return {profileSlot:value.profileSlot,revision:row.revision,preferences:JSON.parse(row.preferences),programme:JSON.parse(row.programme),updatedAt:row.updated_at};
 }
 if(path==='/plans/withdraw') {
 const value=slot.extend({expectedRevision:z.number().int().positive()}).parse(input);
 const row=await c.sql(`UPDATE native_plans SET preferences=NULL,programme=NULL,revision=revision+1,updated_at=? WHERE user_id=? AND profile_slot=? AND revision=? AND ${deviceGuard} RETURNING revision`,new Date(c.now()).toISOString(),d.user_id,value.profileSlot,value.expectedRevision,...deviceArgs(c,d)).first<{revision:number}>();
 if(!row) throw new NativeError(409,'revision_conflict');
 return {withdrawn:true,revision:row.revision};
 }
 const value=consent.extend({expectedRevision:z.number().int().nonnegative(),preferences:networkPreferencesSchema,programme:networkProgrammeSchema.nullable()}).parse(input);
 const updatedAt=new Date(c.now()).toISOString();
 const row=await c.sql(`INSERT INTO native_plans(user_id,profile_slot,revision,preferences,programme,updated_at) SELECT ?,?,1,?,?,? WHERE ${deviceGuard} AND (?=0 OR EXISTS(SELECT 1 FROM native_plans WHERE user_id=? AND profile_slot=?)) ON CONFLICT(user_id,profile_slot) DO UPDATE SET revision=revision+1,preferences=excluded.preferences,programme=excluded.programme,updated_at=excluded.updated_at WHERE native_plans.revision=? RETURNING revision`,d.user_id,value.profileSlot,JSON.stringify(value.preferences),JSON.stringify(value.programme),updatedAt,...deviceArgs(c,d),value.expectedRevision,d.user_id,value.profileSlot,value.expectedRevision).first<{revision:number}>();
 if(!row) throw new NativeError(409,'revision_conflict');
 return {profileSlot:value.profileSlot,revision:row.revision,updatedAt};
}
