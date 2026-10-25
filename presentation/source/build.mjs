import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {Presentation,PresentationFile,FileBlob} from '@oai/artifact-tool';
const repo='/Users/scsoc/dev/AI PT';
const workspaceDir=path.join(repo,'presentation');
const SKILL_DIR='/Users/scsoc/.codex/plugins/cache/openai-primary-runtime/presentations/26.1020.11348/skills/presentations';
const RUNTIME_PYTHON='/Users/scsoc/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3';
const {resolvePresentationFont,applyPresentationChartFont,finalizePresentation}=await import(pathToFileURL(path.join(SKILL_DIR,'container_tools/artifact_tool_utils.mjs')).href);
const FONT=resolvePresentationFont();
const C={black:'#141414',gray:'#5D6560',mint:'#86E8B0',green:'#216B49',line:'#DCE4DF',white:'#FFFFFF'};
const deck=Presentation.create({slideSize:{width:1280,height:720}});
deck.theme.defaultFont=FONT;
let names=0;
function text(s,value,x,y,w,h,size=28,bold=false,color=C.black,extra={}){
 const a=s.shapes.add({geometry:'textbox',name:`text-${++names}`,position:{left:x,top:y,width:w,height:h},fill:'none',line:{fill:'none',width:0}});
 a.text=value;a.text.style={typeface:FONT,fontSize:size,bold,color,wrap:'square',autoFit:'none',insets:0,verticalAlignment:'top',...extra};return a;
}
function slide(title,notes=''){
 const s=deck.slides.add();s.background.fill=C.white;
 text(s,title,76,58,1128,100,48,true);
 text(s,String(deck.slides.items.length).padStart(2,'0'),1150,672,54,24,19,false,C.gray,{alignment:'right'});
 s.speakerNotes.text=notes;return s;
}
function label(s,value,x,y,w=1100){return text(s,value,x,y,w,40,24,true,C.green);}
function body(s,value,x,y,w,h,size=28){return text(s,value,x,y,w,h,size,false,C.gray);}
async function image(s,file,x,y,w,h,alt){const b=await fs.readFile(path.join(workspaceDir,'assets',file));s.images.add({blob:b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength),contentType:file.endsWith('.jpg')?'image/jpeg':'image/png',alt,fit:'contain',position:{left:x,top:y,width:w,height:h}});}
function node(s,value,x,y,w,h){const a=s.shapes.add({geometry:'rect',name:`diagram-${++names}`,position:{left:x,top:y,width:w,height:h},fill:C.white,line:{fill:C.line,width:1.5}});a.text=value;a.text.style={typeface:FONT,fontSize:27,bold:true,color:C.black,alignment:'center',verticalAlignment:'middle',insets:12};return a;}
function connect(s,a,b,from='right',to='left'){s.shapes.connect(a,b,{kind:'elbow',fromSide:from,toSide:to,line:{fill:C.green,width:2.5},tail:{type:'triangle',width:'sm',length:'sm'}});}
const revision='20261025T0036Z-final';
const stagingDir=path.join(workspaceDir,'.build',revision);
await fs.mkdir(path.join(stagingDir,'final'),{recursive:true});
const snapshot='Evidence snapshot 25 October 2026, 00:36 UTC';
// 1
{
 const s=deck.slides.add();s.background.fill=C.white;
 text(s,'Spottr',76,105,650,120,100,true);
 text(s,'Bodyweight coaching\non iPhone and Watch',80,268,680,160,52,true);
 body(s,'Short workout feedback needs fresh evidence.\nThe user stays in control of the set.',82,470,650,110,29);
 label(s,'OxHack 2026',82,628,500);
 await image(s,'today-simulator.jpg',860,65,284,570,'Actual Today screen captured in the iPhone simulator, showing zero streak and zero of three training days');
 body(s,'iPhone simulator',856,648,350,28,21);
 s.speakerNotes.text=`Opening: Spottr is an implemented native bodyweight workout prototype. The motivation is short, timely feedback with an explicit evidence boundary, not a clinical or physical-capacity claim. The image is an actual iPhone simulator screenshot approved by the owner, with missing/unearned progress shown honestly. ${snapshot}. Sources: ${repo}/docs/app-guide.md; ${repo}/docs/integration-readiness.md. Asset source and SHA256 are in presentation/source/assets.json.`;
}
// 2
{
 const s=slide('The workout flow',`${snapshot}. Implemented native flow, not a measured rep-accuracy claim. Manual/timed workouts work without cloud credentials. A real camera path exists for push-ups and squats; physical accuracy/error/abstention evaluation remains pending. Local speech is opt-in, fake-playback tested, with audible phone acceptance pending. Sources: ${repo}/docs/app-guide.md; ${repo}/docs/voice-feedback.md; ${repo}/docs/integration-readiness.md.`);
 const steps=[['01','Choose the work','Goals, weekly target and an approved workout.'],['02','Track the set','Camera cycles for push-ups and squats. Manual logs and hold timers for the wider library.'],['03','Respond in the moment','A concise cue, visible controls and optional local voice. Pause or stop at any time.'],['04','Review the record','Actual sets, source labels and timings. Ask for an AI summary with an explicit tap.']];
 steps.forEach(([n,h,b],i)=>{const y=184+i*116;text(s,n,80,y,72,56,40,true,C.green);text(s,h,185,y,340,48,31,true);body(s,b,560,y,620,82,27);});
}
// 3
{
 const s=slide('Phone, Watch and optional side camera',`${snapshot}. Editable architecture. Phone owns MediaPipe inference, session state and deterministic policy. Watch adapter forwards latest-value timestamped heart/motion signals, not raw lossless vectors. Simulator transport/visual evidence and unsigned device compilation are separate from physical Watch recording. Pi real HTTPS pairing/start/frame/stop tests succeeded, then USB disconnected after around two seconds. No Pi inference or sustained capture is claimed. Sources: ${repo}/docs/watch-telemetry.md; ${repo}/docs/watch-simulator-acceptance.md; ${repo}/hardware/pi/EVIDENCE-2026-10-24.md; ${repo}/hardware/pi/NATIVE-HANDOFF.md.`);
 const watch=node(s,'Watch',80,190,240,76);const phone=node(s,'iPhone',470,190,330,76);const pi=node(s,'Pi side camera',950,190,250,76);connect(s,watch,phone);connect(s,pi,phone,'left','right');
 await image(s,'watch-simulator.jpg',92,320,222,265,'Actual compact Watch simulator UI with no heart-rate measurement, pause/end controls, and show your full body cue');
 body(s,'Simulator capture\nPhysical sensors pending',80,604,325,70,23);
 label(s,'Session authority',470,330,360);body(s,'On-device pose inference\nRep and rest timing\nCue priority and expiry\nLocal workout history',470,384,390,210,29);
 label(s,'Capture companion',930,330,320);body(s,'HTTPS pairing verified\nReal initial frames\nUSB disconnect blocks\nsustained capture',930,384,285,210,26);
}
// 4
{
 const s=slide('Timing decisions use observed evidence',`${snapshot}. These are deterministic implementation rules, not calibrated physiological thresholds or a measurement of rep-count accuracy. RepCounter requires confidence>=0.6 and a complete top-bottom-top cycle, resets on gaps>0.75s or nonmonotonic time, uses0.15s zone stability and accepts0.6–15s cycle duration. CoachingPolicy compares a new valid rep with at least five prior valid durations using mean+max(sampleSD,0.25s). Reported discomfort has an exercise-independent stop decision, including manual reps and holds. PR #64 passed 23 native checks, 26 core checks and a Watch simulator build; fake playback does not establish audible acceptance. Stop identity persists across ticks; repeated stop does not cut itself off or replay after background return. Lifecycle invalidation prevents old cues/sensor callbacks entering a new state. Sources: ${repo}/Shared/Core/RepCounter.swift; ${repo}/Shared/Core/CoachingPolicy.swift; ${repo}/docs/watch-telemetry.md; ${repo}/docs/voice-feedback.md. Phase images are existing illustrations, not captured workout evidence.`);
 const rows=[['Complete cycles count','Top, bottom, then top. A gap above0.75s resets movement.'],['Pacing uses prior reps','After five valid reps, flag duration above\nmean + max(sample SD,0.25s).'],['Stop takes priority','Reported discomfort overrides ordinary cues.\nPause and end cancel speech and old cues.'],['Sensor time stays explicit','Missing or stale Watch readings remain unavailable.']];
 rows.forEach(([h,b],i)=>{const y=178+i*119;label(s,h,80,y,660);body(s,b.replace('above0.75s','above 0.75s').replace('SD,0.25s','SD, 0.25s'),80,y+41,670,75,27);});
 await image(s,'pushup-top.png',865,175,290,135,'Existing illustration of push-up top position');
 await image(s,'pushup-mid.png',865,330,290,135,'Existing illustration of push-up middle position');
 await image(s,'pushup-bottom.png',865,485,290,135,'Existing illustration of push-up bottom position');
 body(s,'Illustrated phases',875,638,320,30,22);
}
// 5
{
 const s=slide('Skills make recorded progress visible',`${snapshot}. The current app has19 catalogue entries and connected tree/linear options. This diagram shows the exact immediate prerequisite example for pushup: kneePushup and plank. Earlier prerequisites of those nodes are omitted. Node completion needs three qualifying sets across two days after all immediate prerequisites complete. Manual/camera evidence can qualify; video replay and discomfort stops do not. Game points are not physical capacity. Sources: ${repo}/Shared/Core/SkillProgress.swift; ${repo}/Shared/Core/ExerciseCatalog.swift; ${repo}/Native/iOS/SkillsViews.swift; ${repo}/docs/app-guide.md. Exercise artwork is existing PNG content, with source hashes in assets.json.`);
 body(s,'19 exercises. Connected tree or linear list.',80,154,1100,50,29);
 const knee=node(s,'Knee push-ups',80,240,260,68);const plank=node(s,'Forearm plank',80,475,260,68);const push=node(s,'Push-ups',540,355,235,80);connect(s,knee,push);connect(s,plank,push);
 label(s,'One unlock example',80,621,600);
 text(s,'3 qualifying sets\nacross2 days',865,238,330,100,35,true);body(s,'All prerequisites complete.\nPractice remains open.\nSources stay visible.',865,375,330,150,27);
 body(s,'Replay and discomfort\ndo not earn completion.',865,550,330,83,24);
 // Preserve natural spacing in editable text.
 for(const a of s.shapes.items ?? []){if(typeof a.text?.toString==='function'){} }
}
// 6
{
 const s=slide('Four Gemini requests share a grounded contract',`${snapshot}. Local gateway returned actual200 responses for chat/session/weekly/proposal using synthetic inputs. Two signed-simulator native chats reached Google. The second accepted the server-owned capability context: base push-ups and squats support camera tracking; other rep exercises use manual logging and seconds exercises use an active hold timer. After a provider-only maxItems schema projection, three explicit native production actions accepted a proposal, weekly summary and session summary with isolated synthetic inputs. The full original output validator remains enforced. The proposal offered Squats, Knee push-ups and Forearm plank; only Squats was selected, with no approval or saved plan. The reports described one synthetic manual session/set with two Squats reps and no Watch data/profile. Physical phone networking and real-user coaching quality remain pending. Separate native fixture checks exercise structured-response display without a provider call. Automatic facts include selected goals and weekly target, omit optional name, and retain sources. Schema/evidence validation rejects missing/unknown fact IDs; generation identity rejects late context. Plans require explicit user selection/approval and proposed targets never count as completed work. No raw camera video or sensor stream is automatically supplied here. Sources: ${repo}/docs/evidence/native-gemini-chat-2026-10-24.md; ${repo}/docs/evidence/gemini-structured-compatibility-2026-10-25.md; ${repo}/docs/coach-goals.md; ${repo}/Shared/Core/CoachContracts.swift; ${repo}/Shared/Core/CoachGrounding.swift; ${repo}/docs/integration-readiness.md.`);
 ['Chat','Workout proposal','Session summary','Weekly summary'].forEach((h,i)=>{text(s,String(i+1).padStart(2,'0'),80,194+i*91,70,50,35,true,C.green);text(s,h,176,194+i*91,390,56,32,true);});
 label(s,'Explicit facts and preferences',640,194,550);body(s,'Recorded sets and source labels\nSelected goals and weekly target\nCanonical catalogue capabilities',640,245,550,155,28);
 label(s,'Checked before use',640,426,550);body(s,'Fact IDs and typed quantities\nCurrent generation only\nUser approval before a plan starts',640,476,550,150,28);
 body(s,'All four types accepted in the signed simulator with synthetic inputs.\nPhysical phone networking and real-user coaching remain unverified.',80,632,1100,66,23);
}
// 7
{
 const s=slide('Operational data and batch analysis',`${snapshot}. Operational Tiger storage and Snowflake retrospective public-data evaluation are separate. Authenticated Tiger Explorer accepted the exact gateway migration: two empty tables, 15 columns, seven validated PK/CHECK constraints, a one-day scalar hypertable and four usable indexes. No workout or sensor rows were inserted. The separate Node connection still fails strict TLS with SELF_SIGNED_CERT_IN_CHAIN; no gateway ingestion, replay/readback, rollup or standalone prototype database acceptance is claimed. Snowflake pinned public PAMAP2 import/reconciliation and bounded SQL transport are tested offline; dry-run is default and live public-data execution requires explicit opt-in. No actual warehouse statement/result is accepted. Local history and explicit optional sync remain distinct. Sources: ${repo}/docs/integration-readiness.md; ${repo}/docs/tiger-live-readiness.md; ${repo}/docs/ISSUES.md; ${repo}/docs/personal-learning.md; ${repo}/docs/evidence/tiger-console-2026-10-24.md.`);
 text(s,'Tiger Data',80,192,520,65,44,true);label(s,'Operational history',80,274,520);body(s,'Implemented snapshot adapter\nTimestamped Watch scalars\nExplicit optional upload',80,330,510,150,30);body(s,'Console schema accepted; zero rows.\nNode TLS and ingestion pending.',80,537,510,100,27);
 text(s,'Snowflake',710,192,500,65,44,true);label(s,'Batch evaluation',710,274,490);body(s,'Implemented public-data batch\nPinned forecast lineage\nand error reconciliation',710,330,490,150,30);body(s,'Dry-run import/evaluation tested.\nLive warehouse acceptance pending.',710,537,490,100,27);
}
// 8
{
 const r=JSON.parse(await fs.readFile(path.join(repo,'research/hr_forecast/results/report.json'),'utf8'));
 const metric=(h,k)=>Math.round(r.test_results[h].selected_primary_same_origins[k].participant_macro_mae*1000)/1000;
 const s=slide('An HR forecast with a locked participant test',`${snapshot}. Actual offline PAMAP2 run2026-10-24T20:43:51–20:43:59UTC. Source: Reiss,A.(2012), PAMAP2 Physical Activity Monitoring, UCI DOI10.24432/C5NW2H, CC BY4.0. Changes: causal features/ridge/figures/evaluation. Official source https://archive.ics.uci.edu/dataset/231/pamap2+physical+activity+monitoring. Train101–105,validation106–107,test108–109. Future target: mean of five observed1s HR-bin means ending10/30s after origin; input history60s. No interpolation, future covariates or test normalization. Validation selected HR-only ridge alpha0.1, not wrist candidates. Test108:80310s and79930s forecasts. Test109:only410s and030s forecasts from84.76s recording. Macro10s gives both participants equal weight despite tiny109 count. At30s only108 contributes. Fixed prequential bias adapter worsened full-run error. No calibrated intervals, Watch transfer, recovery, failure/RIR prediction, or app integration.13 contract tests pass. Sources: ${repo}/research/hr_forecast/protocol.json; ${repo}/research/hr_forecast/results/report.json; ${repo}/research/hr_forecast/results/inventory.json; ${repo}/docs/public-data-benchmark.md. Original plots copied unchanged into presentation/assets/ for supplementary evidence. Native chart values round the recorded metrics to three decimal places for editable workbook compatibility.`);
 body(s,'Future 5s mean HR, using the previous 60 seconds',80,153,760,38,24);
 const chart=s.charts.add('bar',{position:{left:75,top:200,width:735,height:385},categories:['10s horizon','30s horizon'],series:[{name:'Last value',values:[metric('10','persistence'),metric('30','persistence')],fill:C.black},{name:'Frozen ridge',values:[metric('10','frozen'),metric('30','frozen')],fill:C.mint},{name:'Adaptive bias',values:[metric('10','adaptive'),metric('30','adaptive')],fill:'#A1A7A3'}],barOptions:{direction:'column',grouping:'clustered',gapWidth:95},hasLegend:true,legend:{position:'bottom',overlay:false,textStyle:{fontSize:22,fill:C.black}},xAxis:{textStyle:{fontSize:23,fill:C.black},majorGridlines:null,line:{fill:C.line,width:1}},yAxis:{min:0,max:9,majorUnit:3,title:{text:'MAE (bpm)',textStyle:{fontSize:23,fill:C.gray}},textStyle:{fontSize:21,fill:C.gray},majorGridlines:{fill:C.line,width:1}},dataLabels:{showValue:true,position:'outEnd',numberFormatCode:'0.000',textStyle:{fontSize:20,fill:C.black}},chartFill:'none',plotAreaFill:'none'});applyPresentationChartFont(chart,{fontFamily:FONT});
 label(s,'Test coverage',865,200,330);text(s,'Participants 108 / 109',865,249,330,60,29,true);body(s,'10s:803 +4 forecasts\n30s:799 +0 forecasts',865,325,330,100,28);
 text(s,'The adapter\nincreased error',865,475,330,100,31,true);
 body(s,'Exploratory public-data result. Only one person contributes at30s. No Watch or failure validation.',80,625,1110,66,24);
}
// 9
{
 const s=slide('Provider evidence and remaining gates',`${snapshot}. This table summarizes implementation/fixture/live distinctions. Never claim all sponsors/providers were used. Gemini has four actual synthetic gateway response types, two signed-simulator native chats, and three accepted native production structured actions (proposal/session/week) after the provider-only schema fix. All new inputs were isolated synthetic records. Physical phone networking and personal coaching quality remain pending. The investigation used seven new provider attempts total: initial normal native 502, two diagnostic native HTTP400, one controlled direct HTTP200 and three post-fix native responses accepted by native display validation. No automatic retry or provider fallback was introduced. Voice local Apple synthesis is implemented with fake playback tests; no audible/ElevenLabs run. Tiger authenticated console accepted the gateway schema with zero rows; strict Node TLS remains blocked without trust bypass. Ingestion, readback, rollups and the separate prototype path remain unverified. The revised local landing uses actual white simulator captures and passed four-width, keyboard and reduced-motion checks; no public deployment. Snowflake pinned batch workflow and local ARM64 gateway/Caddy runtime checks passed; no Snowflake live statement or Vultr VM/credit/spend scope; Presage automatic derived-vitals egress unresolved; Delta zero judge requests and missing installation/legal operator gate. Sources: ${repo}/docs/evidence/pushup-prototype-integrity-2026-10-24.md; ${repo}/docs/evidence/gemini-structured-compatibility-2026-10-25.md; ${repo}/docs/snowflake-analytics.md; ${repo}/docs/vultr-deployment.md; ${repo}/docs/integration-readiness.md; ${repo}/docs/ISSUES.md; ${repo}/docs/voice-feedback.md; ${repo}/docs/presage-integration.md; ${repo}/docs/delta-workflow.md; ${repo}/docs/tiger-live-readiness.md; ${repo}/docs/evidence/tiger-console-2026-10-24.md; ${repo}/docs/evidence/landing-browser-2026-10-24.md.`);
 const values=[['Track','Evidence now','Remaining gate'],['Gemini','4 native types; synthetic','Physical network; real-user review'],['Tiger Data','Console schema; zero rows','Strict Node TLS; ingest/readback'],['Snowflake','Pinned batch workflow tested','Existing warehouse and live SQL'],['Vultr','Local ARM64 runtime checked','Spend scope; hosted TLS/auth'],['ElevenLabs','Local Apple speech only','API secret and audible acceptance'],['Presage','SDK plan prepared','Vitals egress decision and credits'],['Delta','Judge packet prepared','Operator/legal step, then one review']];
 const table=s.tables.add({rows:values.length,columns:3,left:78,top:164,width:1124,height:448,columnWidths:[204,344,576],values});
 table.borders.assign({fill:C.line,width:1,style:'solid'});
 table.cells.block({row:0,column:0,rowCount:8,columnCount:3}).assign({fill:C.white,textStyle:{typeface:FONT,fontSize:23,color:C.black},margins:{top:10,bottom:7,left:12,right:10}});
 table.cells.block({row:0,column:0,rowCount:1,columnCount:3}).assign({fill:C.black,textStyle:{typeface:FONT,fontSize:23,bold:true,color:C.white}});
 body(s,'Web prototype: 92 offline checks; real cloud upload pending.\nLanding: local browser accepted; public deployment pending.',80,627,1030,65,23);
}
// 10
{
 const s=slide('A two-minute demo of the implemented flow',`${snapshot}. This is a suggested rehearsal sequence, not an assertion that a rehearsal occurred. Use normal history safely. Open current Today/profile, then tracked workout, pause/end and source-aware record, Skills and explicit Coach controls. If fixtures or a simulator supply values, label them and do not call them live physiological data. Do not spend provider credits as part of rehearsal without the existing approved scope. Show the saved public-data benchmark as offline. Source inventory is current main 0006472; native TestFlight build 3 is frozen at ebbe560737d16ec3c6a72da7436ba25730587e19. Build 0.1 (3) passed signed archive/export and Apple validation at 00:22:55 UTC on 25 October; upload succeeded at 00:27:06 UTC. App Store Connect reports build 3 VALID, internal IN_BETA_TESTING and external IN_BETA_TESTING, with beta submission APPROVED at the 00:36 UTC read-back. Builds 1, 2 and 3 remain internal; the external OxHack group contains builds 3 and 1. Build 2 is not externally submitted. The existing public invitation https://testflight.apple.com/join/f3MhePbf remains enabled for 25 testers. Its public Apple page and both landing HTTPS links were verified; no itms-beta deep link, invitation acceptance or installation was performed. Build 3 includes the rendering/history refactor; the Gemini compatibility correction runs separately on the gateway. All four native Gemini request types accepted real responses with synthetic inputs; physical networking and real-user guidance remain unverified. The unresolved MediaPipe upstream privacy/origin-signature gap is separate from Apple processing. No physical installation or public App Store approval is claimed. Sources: ${repo}/docs/evidence/testflight-build-3-2026-10-25.md; ${repo}/docs/evidence/testflight-availability-2026-10-25.md; ${repo}/docs/testflight.md; ${repo}/docs/app-guide.md; ${repo}/docs/integration-readiness.md; ${repo}/docs/release-readiness.md; ${repo}/docs/testflight-provisioning.md.`);
 const items=[['00:00','Today and goals','Show the actual starting state.'],['00:15','A tracked workout','Show the camera path and visible cue. Label any fixture.'],['00:55','Pause, end and review','Keep controls available and preserve source labels.'],['01:20','Skills and Coach','Show prerequisites, then an explicit request action.'],['01:45','Evidence and next gates','Use the saved HR result and current provider status.']];
 items.forEach(([time,h,b],i)=>{const y=175+i*88;text(s,time,80,y,110,44,29,true,C.green);text(s,h,240,y,440,45,30,true);body(s,b,710,y,490,67,25);});
 body(s,'TestFlight: builds 1 + 2 + 3 internal; builds 1 + 3 external.\nBuild 3 beta review approved. Physical installs unverified.',80,635,1060,66,24);
}
// Keep copied text natural without changing evidence values.
const fixes=[['across2','across 2'],['returned200','returned 200'],['10s:803 +4','10s: 803 + 4'],['30s:799 +0','30s: 799 + 0'],['at30s','at 30s'],['gateway200s','gateway 200s']];
for(const s of deck.slides.items){for(const a of s.shapes.items){const v=a.text?.toString();if(v&&v!=='[object Object]'){let t=v;for(const [x,y]of fixes)t=t.replaceAll(x,y);if(t!==v)a.text=t;}}}
const candidate=path.join(stagingDir,'candidate.pptx');
await (await PresentationFile.exportPptx(deck)).save(candidate);
await fs.writeFile(path.join(stagingDir,'deck.json'),JSON.stringify(deck.toProto()));
await fs.writeFile(path.join(workspaceDir,'source','deck-text.json'),(await deck.inspect({kind:'slide,textbox,table,chart,notes',maxChars:100000})).ndjson);
const finalPath=path.join(stagingDir,'final','spottr-judges.pptx');
const result=await finalizePresentation({workspaceDir,candidatePath:candidate,finalPath,pythonExecutable:RUNTIME_PYTHON,integrityValidatorPath:path.join(SKILL_DIR,'container_tools/inspect_presentation_package_integrity.py'),layoutValidatorPath:path.join(SKILL_DIR,'container_tools/inspect_presentation_layout_geometry.py'),layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit','--require-native-table-slide','9'],explicitTotalSlideCount:10,requiredNativeChartOwnerSlides:[8],requiredNativeTableOwnerSlides:[9],materializeLiteralChartWorkbooks:true,fontPolicy:{basis:'design',families:[FONT]},verifyArtifactToolImport:true,receiptPath:path.join(stagingDir,'validation.json')});
console.log(JSON.stringify({font:FONT,finalPath,result}));
// Render the final imported package, not just the in-memory draft.
const final=await PresentationFile.importPptx(await FileBlob.load(finalPath));
for(const [i,s]of final.slides.items.entries()){
 const png=await final.export({slide:s,format:'png',scale:1});await fs.writeFile(path.join(workspaceDir,'previews',`slide-${String(i+1).padStart(2,'0')}.png`),new Uint8Array(await png.arrayBuffer()));
 await fs.writeFile(path.join(stagingDir,`slide-${i+1}.layout.json`),await(await s.export({format:'layout'})).text());
}
const montage=await final.export({format:'webp',montage:true,scale:.3});await fs.writeFile(path.join(workspaceDir,'output','preview-montage.webp'),new Uint8Array(await montage.arrayBuffer()));
try {const pdf=await final.export({format:'pdf'});await fs.writeFile(path.join(workspaceDir,'output','spottr-judges.pdf'),new Uint8Array(await pdf.arrayBuffer()));console.log('PDF exported');}catch(error){await fs.writeFile(path.join(stagingDir,'pdf-error.txt'),String(error));console.log('PDF export unavailable',String(error));}
await fs.copyFile(finalPath,path.join(workspaceDir,'output','spottr-judges.pptx'));
console.log('Rendered all10 final slides.');
