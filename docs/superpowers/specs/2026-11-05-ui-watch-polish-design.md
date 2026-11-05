# Consistent UI and guided Watch connection

The user wants a finished consumer experience, using the existing workout stick-figure artwork as the visual reference. This is a continuation of the delegated Spottr overhaul. Keep the native SwiftUI app, local training/Health model, four tabs, existing progress and offline functionality. No human faces, runtime AI, paid services, Chrome, new simulators or destructive data changes.

## Visual direction

Reuse the existing squat/push-up workout images wherever their movement applies; they have dark rounded limbs, subtle edging, simple heads and bright joint markers. Remove the mismatched flat onboarding drawing. Other poses should use the same stroke/joint treatment. Use restrained movement demonstrations, short state transitions and press feedback with Reduce Motion support. Stop repeating animations when a screen is inactive. No decorative perpetual animation on reports or sensor values.

Unify heading hierarchy, 24-point content gutters, restrained 16–24-point radii, neutral surfaces, blue actions and green successful states. Use meaningful labelled actions, minimum 44-point touch areas and layouts which reflow at accessibility text sizes. Remove repeated page headings and gratuitous full stops, implementation explanations and prototype narration. Keep source/date/gap information needed to interpret measurements, plus actual error/permission guidance. Move lengthy methodology into an expandable explanation where useful. Keep existing accessibility identifiers whenever behavior remains.

## Watch setup

Provide a guided optional flow: choose whether the user has a Watch, choose a model family or Not sure, show installation instructions only when needed, show live pairing/app-install/reachability states, verify the companion responds, explain workout access, show last observed sync and queued-data state when known. Never animate fictional percent progress. A completed setup milestone requires its real observation; connected does not mean Health read permission. Keep shared WCSession ownership in CompanionLink; never install a second delegate.

Offer SE, Series 6 or later, Ultra, Not sure and No Watch choices without making model choice a barrier. Model selection is a local user preference, not a hardware attestation. Known limitations (notably no oxygen sensor on SE) may tailor explanation/request options, but never fabricate readings or infer denied read access. Historical Health data may originate from a different device and must stay clearly separate. Actual motion availability comes from CoreMotion on the Watch; actual Health readings and timestamp/source remain authoritative. Expose only metrics the app implements. Do not add ECG/temperature claims or raw access that the app does not implement. Builder may choose a small backward-compatible capability/status message handshake if required for real sync progress, with validated freshness, local persistence bounds and tests. Preserve durable telemetry and legacy packet compatibility.

## Validation and delivery

Write behavior tests before new connection/state/capability logic. Reuse the existing iPhone only, coordinate ownership before running UI tests, build on SSD. Validate onboarding, all four tabs, settings/Watch flow, empty reports, a manual saved report and Reduce Motion. Review actual captures and inspect larger Dynamic Type. Preserve build17/Vendor and existing evidence. Scope independent workers to nonoverlapping files. Root integrates/reviews/tests and produces the next signed TestFlight build only after verification. Physical Watch/sensor/battery acceptance remains separate.

Builder calls: reuse imagery rather than generating new assets; keep optional setup skippable; prefer honest milestone/status labels over a fake percentage. No new training or HPC work.
