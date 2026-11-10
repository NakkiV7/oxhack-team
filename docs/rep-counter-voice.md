# Rep counter voice

Build 1.0 (27) offers optional rep counts using the iPhone’s device speaking voice. Counts are separate from Maya and Leo’s natural offline coaching recordings. No gateway or paid synthesis is used.

## Behaviour

- **Opt in.** In the coach voice sheet, enable **Speak rep counts with device voice**. New installations and former celebrity-counter preferences start off. Explicit off stays off across launches. Choosing Maya, Leo or Local voice never enables counting automatically.
- **When it speaks.** The workout’s **Voice feedback** must also be on, and the input must be camera counting. Manual and video sets stay silent. Junior profiles do not offer the counter.
- **What it says.** A start line, the number for each counted rep from 1 to 30, gentle encouragement after every third clean rep, and a closing line after the set ends.
- **Queueing.** A new count replaces a waiting count. Counts expire after 1.5 seconds; start/encouragement lines after 4 seconds; closing lines after 8 seconds. A line that already started can finish. Counts cannot interrupt each other.
- **Shared voice ownership.** Form guidance waits for the current rep sentence and rechecks freshness. Stop guidance interrupts immediately. Muting, pausing, backgrounding, discomfort, or changing the selected voice cancels pending counts. Optional counts suppress routine coaching encouragement so both do not speak together.

## Implementation and evidence

`Shared/Core/VoiceCuePlayback.swift` owns queue rules. `Native/iOS/DemoVoicePlayback.swift` contains `RepVoicePlayer` and its device speech output. `TrainingStore` and `CoachingVoiceBridge` arbitrate counts and coaching. `VoiceCoachSettingsView` owns explicit opt-in.

`Tests/Core/RepVoicePlanTests.swift` checks queue and expiry rules. `Tests/iOS/PreviewRepCueTests.swift` exercises the real player/store handoffs with passive outputs, including finish, priority, cancellation and stale callbacks. Actual audible quality and audio coexistence remain physical-device checks.

The retired coaching and rep folders were independently preserved and verified on SSD before removal from the shipping resource tree. Historical builds and dated evidence remain unchanged. The shipping catalogue contains only Maya, Leo and Local voice; legacy Arnold/David/Goggins coaching preferences resolve to Maya without changing programme or workout history.
