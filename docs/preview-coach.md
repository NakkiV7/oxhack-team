# Prepared Coach preview

`DemoCoachView(store: TrainingStore, profile: LocalProfile? = nil)` is an isolated, prewritten example. Route to it **only when the explicit TestFlight preview mode is enabled**. The parent integration owns the default-off setting, preview store/history namespace, automatic demo connections, mode switching, and source/project registration. Keep `CoachView` in normal mode. Pass the isolated preview `TrainingStore`, never the real store. The supplied optional profile is accepted for router compatibility; the sample does not infer personal ability from it.

The screen loads a prepared Omar conversation and labels it as a sample. Its three numbered planning stages describe a prepared workflow; they do not claim a provider call, elapsed latency, or hidden reasoning. No timer, automatic request, approval persistence, history write, camera call or connection setup runs on appearance. There is no free-text composer or keyboard in this view. Native toggles/buttons support Dynamic Type; the view has no animations and therefore requires no reduced-motion exception.

Seven days include two separated strength days, two mobility days, one optional recovery day and two rest days. Six of seven unique catalogue exercises start selected. Selection applies across every day containing an exercise. Wall support starts unconfirmed. Confirm it or deselect wall push-ups before approving; an empty selection cannot be approved. Any selection/support edit invalidates approval. Approval remains in view state. Explicit Start on an approved day constructs a `CoachSavedPlan` using the existing proposal validator, then calls `store.startPlan(plan, availableSupport:)`. Finishing/logging is owned by the existing session flow. Starting never creates a completed-history record itself.

Parent router should recreate this screen when changing mode, so local approval/selection cannot carry across workspaces. The existing root session cover presents `store.presented`; this view deliberately adds no competing cover. The parent should keep real push-up/squat camera handling in its existing runtime path. No device/Pi access was used.

## Exact selectors and coordinated native checks

Core: `swift test --filter DemoCoachTranscriptTests` (three behavior tests). The root owns all simulator/native builds and should register both new Swift sources through the existing project workflow.

| Element | Accessibility identifier |
| --- | --- |
| Screen | `demo-coach-conversation` |
| Preview badge | `demo-coach-preview-badge` |
| Loaded user turn | `demo-coach-user-message` |
| Prepared workflow | `demo-coach-workflow` |
| Day card | `demo-coach-day-<monday…sunday>` |
| Exercise toggle | `demo-coach-exercise-<day>-<catalogueID>` |
| Wall confirmation | `demo-coach-support-wall` |
| Count | `demo-coach-selection-count` |
| Approval | `demo-coach-approve` |
| Approved day Start | `demo-coach-start-<day>` |
| Validation error | `demo-coach-error` |
| Links | `demo-coach-link-nhs-strength`, `demo-coach-link-nhs-flexibility`, `demo-coach-link-who` |

Suggested coordinated UI sequence, after the parent has enabled preview through its own setting:

1. Open Coach. Assert loaded user message, preview badge, prepared workflow, `6 of 7 exercises selected`, disabled approval, and absent `demo-coach-start-monday`.
2. Toggle `demo-coach-exercise-monday-wallPushup` off. Count becomes `5 of 7`; Thursday's wall toggle also becomes off. Approval is enabled without wall confirmation. Approve; Start Monday appears. No history record should be added.
3. Change `demo-coach-exercise-tuesday-hipFlexorStretch`. Count increases, approval becomes available again, and Start buttons disappear until approval is repeated.
4. Restore wall selection. Approval stays disabled until `demo-coach-support-wall` is on. Approve and tap `demo-coach-start-monday`. Expect the existing configured-session UI with only the selected Monday exercises; abort without saving and confirm history unchanged.
5. Exercise link-opening checks only in the root's browser session: each Link uses the default system URL action, with no in-app webview. No browser was driven by this lane.
6. At accessibility text sizes, check that day headings/badges stack and exercise labels remain readable. No fixed text heights or animated transitions are used.

## Guidance checked 25 October 2026

These are general guidance links; the sample's exact doses and weekly schedule are illustrative, not attributed prescriptions or a clinical readiness assessment.

- [NHS strength exercises](https://www.nhs.uk/live-well/exercise/strength-exercises/) supports gentle restart and gradual progression.
- [NHS strength and flexibility](https://www.nhs.uk/live-well/exercise/how-to-improve-strength-flexibility/) advises gradual progression and strengthening at least twice weekly.
- [WHO physical activity](https://www.who.int/initiatives/behealthy/physical-activity/) describes broader activity targets and strength work on at least two days for adults.

Validation performed in this lane is isolated SwiftPM behavior testing only. Native compilation, rendering, actual link opening, preview routing/persistence isolation and physical-device acceptance are integration checks, not established here.
