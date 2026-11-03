# Spottr: consolidated patient demo

## Intent and authority

Omar requested consolidation of pushed teammate branches, working squat and push-up web tools, a complete native Spottr demo, better onboarding and skill-tree workflow, offline coach audio, and free infrastructure where needed. The pitch is to OneMedicalGroup: £125,000 for 30% to develop the MVP and explore GP-practice rollout for MSK recovery, weight management and social prescribing. This is product-development context, not evidence of clinical effectiveness or an agreed clinical deployment.

## Product flow

1. A short introduction explains movement practice, locally stored progress and optional camera feedback. Goals, starting point and a manageable routine lead into a personalised training path. Optional measurements remain optional.
2. Skills presents the next useful practice step, its purpose, progress and prerequisites. The complete challenge tree stays accessible. A deterministic catalogue path works without accounts, provider credits or network configuration; AI enhancement is optional and labelled.
3. Squat and push-up sessions work from a phone camera or selected video. Recorded videos are clearly replay and cannot earn live-workout achievements. Framing, tracking loss, pause/stop and manual fallback remain visible. Arnold and Goggins use the already supplied recordings offline, with safety cues retaining priority and cancellation.
4. Insights shows actual history by default. Sample history is confined to explicit preview mode. Empty history offers a useful first action. Reports retain source labels and missing measurements stay missing.
5. Demo materials show an onboarding-to-path-to-session-to-report journey. Captures of the actual app and prerecorded exercise replays support the pitch. GP referral, clinician review and outcomes evaluation are future pilot proposals unless implemented and verified here.

## Consolidation

Preserve the current dirty checkout in a local checkpoint commit, excluding unrelated Finder metadata and private/unreviewed media. Merge current main, nakki/app-demo and nakki-squat-model on a codex branch. Resolve conflicts by retaining the latest local Full-model, physiology isolation and camera lifecycle safeguards alongside teammate path, calendar and audio additions. Regenerate the Xcode project using the maintained script.

## Implementation choices

These are implementation decisions by Codex, open to Omar's steering: retain SwiftUI, Swift Core and browser MediaPipe; prefer local storage and bundled audio; make essential exercises/path generation work without hackathon providers; preserve optional adapters instead of deleting historical service code. Use Cloudflare only for a concrete hosting need. Do not activate paid providers or migrate existing private datasets. Do not fabricate patient records or clinical outcomes.

## Verification

Observe relevant failures before new production fixes. Run shared Swift, gateway, web tracker and native tests; build the simulator and phone variants. Inspect the rendered onboarding, paths, camera/replay controls and reports. Exercise both web tools in a browser with real model loading and supplied videos, recording observed counts separately from accuracy claims. Check connected devices before phone installation. Phone camera quality and audible playback need physical acceptance; simulator success does not establish those.

## Deliverables

A locally consolidated reviewable branch; working squat/push-up tools and documented launch commands; a coherent native app build; clearer onboarding and next-step navigation; offline recordings; explicit preview/replay handling; screenshots or screen recordings; a concise pitch storyboard and honest remaining gates. No App Store submission or remote Git push is implied by this work.
