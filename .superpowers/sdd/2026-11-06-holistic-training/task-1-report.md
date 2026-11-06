# Task 1 implementation report

Status: DONE for Task 1. The confirmed all-ages steering is incorporated. Core implementation commit: `ecaa7b5` (`feat: add age-aware personal programmes and shared skill curriculum`). Independent task review and downstream native/service integration remain separate work.

Base: `1c8f4f0519f76803c2be4cc41b50a7490d7e4800`.

## Scope

Pure shared domain models and necessary execution/record adapters only. No native UI, account, service, network, ML/CV, audio, simulator, provider, or secret work. The existing four `TrainingAttribute` cases, three `LocalProfile.BaselineAbility` cases, coarse BMI category, catalogue levels, XP calculation and recorded history remain unchanged.

## Verification evidence

All commands use the existing scratch directory and two jobs:

```sh
swift test --scratch-path '/Volumes/Spottr Development/CV23-Core' --jobs 2 --filter 'programme|curriculum|sixBandBMI|plannedSessionRecords'
swift test --scratch-path '/Volumes/Spottr Development/CV23-Core' --jobs 2 --filter 'plannedSessionTelemetry|plannedSessionSupport|programmeAbility|programmeUsesReal'
swift test --scratch-path '/Volumes/Spottr Development/CV23-Core' --jobs 2 --filter 'programme|curriculum|sixBandBMI|plannedSession'
swift test --scratch-path '/Volumes/Spottr Development/CV23-Core' --jobs 2
```

Logs are under `/Volumes/Spottr Development/Audio/Holistic-Training-20261106/task1/`.

- `red.log`: expected compile failure for missing new domain APIs before production changes.
- `green-1.log`: test macro compilation error, corrected by assigning the mutating result before `#expect`.
- `green-2.log`: three assertions exposed an incorrect test fixture (8 push-ups instead of the existing 10-rep target); fixture corrected without lowering the earned requirement.
- `green-3.log`: 11 new tests passed.
- `red-adapters.log`: expected failures for dropped planned-workout ID during telemetry import, ignored legacy tracked-set completion, and independent own-family earned evidence not influencing the planner.
- `green-adapters.log`: 15 new tests passed after these adapters were fixed.
- `full-core.log`: 365 tests in 1 suite passed before subsequent self-review and age-policy changes.
- `red-self-review.log`: expected failures for current-week effort not affecting later unstarted days and a legacy feedback call clearing a recorded effort choice.
- `green-self-review.log`: 17 new tests passed after those fixes.
- `red-age.log`: expected compile failure for missing new age-context and age-aware BMI APIs before age-policy production code.
- `green-age-1.log`: 21 new tests passed.
- `red-child-curriculum.log`: test compilation correction for a missing `try`.
- `red-child-curriculum-2.log`: the cross-language fixture passed, and 14 expected assertions demonstrated that child curriculum usability still exposed adult exercises before the shared age restriction was applied.
- `green-final-focused.log`: all 23 new focused tests passed (5.469 seconds).
- `full-core-final.log`: all **373 tests in 1 suite passed** (7.616 seconds).
- `git diff --check` and `git diff --cached --check`: clean. SSD free space remained 1.5 GiB; no resizing, cleanup, migration, simulator or native builds occurred.

Final focused command (the full command is above):

```sh
swift test --scratch-path '/Volumes/Spottr Development/CV23-Core' --jobs 2 --filter 'trainingAgeContext|ageAwareBMI|programme|curriculum|sixBandBMI|plannedSession'
```

## Self-review and remaining integration concerns

The final self-review verified deterministic goal ordering/IDs, validation on decode, exact 53-ID coverage, support/floor/exclusion filtering, preserved legacy XP/evidence, age boundaries, explicit unknown age, non-applicable adult BMI, unclipped extreme marker values, DST-aware day scheduling, recovery spacing, immutable protected snapshots, legacy tracked completion, deduplicated recent effort and telemetry preservation. Two real compatibility defects found during self-review were fixed through failing public-behaviour tests before completion.

Plan/day IDs are stable **inside a training profile's storage scope**, not globally unique across people. Native account/guardian-profile containers must scope programmes, history, active IDs and Watch journals by the separate training-profile identity, and never pass another profile's history into this planner. Age is a supplied whole-year context, not a verified identity or automatically ageing date of birth; native profile review must keep it current. Policy flags must be combined with actual consent/OS state. No raw child data should be sent to cloud or analytics.

Under-5 `familyMovement` is a domain outcome with no `CoachSavedPlan`; guardian activity cards/resources are Task 3 work. Existing direct adult BMI APIs are retained solely for compatibility; new UI must use the age-aware profile API. Required adult measurement setup, parental gating, account/profile isolation, persistence, live UI and physical Watch/camera acceptance were not performed or claimed in this Core-only task. No new model, dataset, service or authentication logic was introduced.

## Integration requirements and limitations

Use `LocalProfile.trainingGoals` for five-goal user-facing selection. `programmePreferences` is the source of truth when present; old `.goals`, `.baselineAbility`, `.weightManagementGoal` remain legacy persisted values. Every native profile-copy/settings path must carry `programmePreferences` forward.

Persist `TrainingProgramme` after creation. Viewing Today should read that snapshot, not call the planner on every render. To change it, call `revise` with active day IDs. Completed IDs are also protected automatically from `SessionRecord.plannedWorkoutID`. Launch a day with `ConfigurableSession(plan:availableSupport:plannedWorkoutID:)`, passing `day.id`. This domain does not own persistence, UI state, or active session lookup.

The six curriculum chapter labels are navigation only. `SkillCurriculum.evaluate` preserves independently qualifying three-set/two-day evidence, allows own-family alternatives and self-reported placement, and keeps `isUsable` separate from earned status. Placement earns no XP, workouts, or camera observations. Existing `NodeVerification` remains the separate camera-quality verification API; `cameraSets` is an evidence count, not a new quality-verification claim.

The legacy explicit network uploader in `Shared/Core/WorkoutSync.swift` serializes `LoggedSet`. Later service/UI integration must remove/gate that old upload path or explicitly exclude local effort under the new privacy contract. Task 1 adds no network requests and does not enable that path.

Only actual required catalogue support is mandatory. Optional nearby support no longer blocks `ConfigurableSession`; Wall, Stable chair, and Stable sofa or counter are still required for their exercises. Counting, observed time, camera generation, audio, and rest lifecycle are unchanged.

## Exact public integration API

```swift
public enum TrainingGoal: String, CaseIterable, Codable, Sendable {
    case strength, stamina, mobility, balance, weightManagement
}
public enum TrainingStartingPoint: String, CaseIterable, Codable, Sendable {
    case startingOut, somePractice, regularPractice, experienced
    public var suggestedLevel: Int { get } // 1, 2, 3, 4
}
public struct TrainingAgeContext: Codable, Equatable, Sendable {
    public init(ageYears: Int, guardianManaged: Bool) throws
    public let ageYears: Int
    public let guardianManaged: Bool
    public var allowsAnalytics: Bool { get }
    public var allowsCloudPlanSync: Bool { get }
    public var allowsHealthIntegration: Bool { get }
    public var allowsTimePressureRewards: Bool { get }
}
public struct ProgrammePreferences: Codable, Equatable, Sendable {
    public init(goals: Set<TrainingGoal>, weekdays: Set<Int>, minutesPerSession: Int = 20,
                preferredLocalHour: Int = 18, availableSupport: Set<String> = [],
                allowsFloorWork: Bool = true, excludedExerciseIDs: Set<String> = [],
                startingPoint: TrainingStartingPoint? = nil, ageContext: TrainingAgeContext? = nil) throws
    public let goals: Set<TrainingGoal>
    public let weekdays: Set<Int>
    public let minutesPerSession: Int
    public let preferredLocalHour: Int
    public let availableSupport: Set<String>
    public let allowsFloorWork: Bool
    public let excludedExerciseIDs: Set<String>
    public let startingPoint: TrainingStartingPoint?
    public let ageContext: TrainingAgeContext?
    public static let floorExerciseIDs: Set<String>
    public func canUse(_ entry: ExerciseEntry) -> Bool
}
```

Weekdays are ISO Monday=1 through Sunday=7; duration is exactly 10/20/30/45; hour is 0...23. Goals/days must be nonempty, excluded IDs must exist, and support strings must come from `PathSurvey.equipmentChoices` with exact case. Unknown age and unknown ability are distinct optional values. Age validates 0...120, and under-18 requires `guardianManaged == true`. That declaration is not verified guardianship; the later native parental gate supplies access control. The four capability flags are policy allowances, never consent, entitlements or proof of OS permission.

`LocalProfile.init` retains all existing parameters and adds trailing `programmePreferences: ProgrammePreferences? = nil`. New read-only properties are:

```swift
public let programmePreferences: ProgrammePreferences?
public var trainingGoals: Set<TrainingGoal> { get }
public var effectiveProgrammePreferences: ProgrammePreferences { get }
public var bmiAssessment: AgeAwareBMI { get }
```

Legacy profiles decode with nil preferences. Legacy goals plus the weight flag project into `trainingGoals`; when new preferences exist, their exact goal set wins. Legacy weekly targets project to the first N of `[1,3,5,2,4,6,7]`. Legacy age stays unknown; this fallback is not permission to generate an adult programme.

```swift
public enum ProgrammePlanner {
    public enum Invalid: Error, Equatable { case date, noUsableExercises, timeZone, ageRequired }
    public static func makeWeek(profile: LocalProfile, history: [SessionRecord], start: Date,
                                calendar: Calendar = .current) throws -> TrainingProgramme
    public static func revise(_ programme: TrainingProgramme, profile: LocalProfile,
                              history: [SessionRecord], protecting activeDayIDs: Set<String>,
                              calendar: Calendar = .current) throws -> TrainingProgramme
}
public struct TrainingProgramme: Codable, Equatable, Sendable, Identifiable {
    public enum DayKind: String, Codable, Sendable { case workout, rest, recovery, familyMovement }
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let localDate: String
        public let date: Date
        public let kind: DayKind
        public let plan: CoachSavedPlan?
    }
    public let id: String
    public let timeZoneID: String
    public let revision: Int
    public let days: [Day]
}
```

`makeWeek` produces seven local Gregorian days beginning on `start`'s local date, not necessarily Monday. The supplied calendar's timezone is retained. Day IDs are `programme:<timezone>:YYYY-MM-DD`; week IDs are `week:<timezone>:YYYY-MM-DD`. Revision starts at 1; `revise` increments it and retains original timezone. Each day's scheduled `Date` uses the preferred local hour, including Foundation's DST resolution. Rest/family-movement days have nil plans. All formal plans validate through existing `ConfigurableSession` limits. Current-week recorded work before each later day participates in adaptation, with a 28-local-day recent window and duplicate session/set filtering. Future records and video replay do not drive adaptation.

Unknown age throws `.ageRequired`. Under-5 activity days use `.familyMovement`, with no formal sets/camera claims. Ages 5–12 use only frontArmRaise, standingKneeRaise, seatedMarch, stepJack, sitToStand, singleLegBalance, subject to actual equipment/floor/exclusions. They cap at one set and six reps/ten seconds. Ages 13–17 use beginner-level entries (plus the gentle standingBicepsCurl alternative) and cap at two sets and ten reps/twenty seconds. Both groups ignore adult goal prioritisation and adult starting-level/comfort progression, disable automatic effort-based overload, and still allow conservative reductions after difficult/incomplete recorded work. These are conservative product defaults, not clinical exercise prescriptions. Seven selected formal activity days include recovery after each two consecutive workout days.

```swift
public enum SetEffort: Int, CaseIterable, Codable, Sendable {
    case veryEasy = 2, easy = 4, moderate = 6, hard = 8, veryHard = 10
}
// LoggedSet
public var effort: SetEffort? = nil
// SessionRecord
public let plannedWorkoutID: String?
// SessionRecord.init: new trailing plannedWorkoutID: String? = nil
// ConfigurableSession
public init(plan: CoachSavedPlan, availableSupport: Set<String>, plannedWorkoutID: String? = nil) throws
public let plannedWorkoutID: String?
public mutating func feedback(reserve: Int?, reason: StopReason)
public mutating func feedback(reserve: Int?, reason: StopReason, effort: SetEffort?)
// CoachSavedPlan now Equatable, as is CoachSavedPlan.Item
public init(items: [Item], availableSupport: Set<String>, createdAt: Date, rationale: String) throws
```

Nil effort means unrated; invalid raw numbers do not decode. The existing feedback overload preserves a stored effort choice; the new overload can set/clear it explicitly. Neither overload changes actual quantity or clears the discomfort latch. Legacy records decode missing planned-workout ID/effort as nil. Telemetry import retains the new fields. No reward/XP multiplier is added for effort.

```swift
public struct BMIReference: Equatable, Sendable {
    public enum Band: String, CaseIterable, Sendable {
        case underweight, healthyWeight, overweight, obesityClass1, obesityClass2, obesityClass3
    }
    public enum Edge: String, Sendable { case below, above }
    public let value: Double
    public let boundaries: [Double]
    public let referenceWeightKG: Range<Double>
    public var band: Band { get }
    public var markerPosition: Double { get }
    public var visualMarkerPosition: Double { get }
    public var edge: Edge? { get }
}
public struct AgeAwareBMI: Equatable, Sendable {
    public let value: Double?
    public let adultReference: BMIReference?
    public let adultCategory: LocalBodyMeasurements.Category?
    public let needsChildGrowthReference: Bool
}
```

**Native consumers must use `LocalProfile.bmiAssessment`.** It returns no value/classification for unknown age or under-2; ages 2–17 can have a numeric value from optional guardian-provided measurements, but never adult categories/reference bands/centiles. Known adults retain explicit applicability and threshold selection. For compatibility, `LocalBodyMeasurements.category` retains its previous coarse semantics and `.reference` is a standalone adult-reference calculation; those legacy/direct APIs cannot determine age and must not drive child UI. No stored measurements are rewritten to hide that distinction.

Adult boundaries are standard `[18.5,25,30,35,40]` or adjusted `[18.5,23,27.5,32.5,37.5]`. `referenceWeightKG` is the healthy-reference interval for the recorded height, upper bound excluded, not a target. Marker axis is 15...45: `markerPosition` preserves an unclipped fraction; only `visualMarkerPosition` clamps to 0...1. `value` remains actual BMI and `edge` signals off-axis values. No child reference dataset or centile calculation is included. Adult height/weight setup guards, guardian-only measurement UI and NHS external links belong to native integration.

```swift
public enum SkillCurriculum {
    public struct Chapter: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let exerciseIDs: [String]
    }
    public enum State: String, Codable, Sendable { case earned, placed, available, locked }
    public struct Node: Equatable, Sendable, Identifiable {
        public var id: String { get } // exerciseID
        public let exerciseID: String
        public let state: State
        public let isUsable: Bool
        public let qualifyingSets: Int
        public let trainingDays: Int
        public let manualSets: Int
        public let cameraSets: Int
    }
    public struct Progress: Equatable, Sendable {
        public let nodes: [Node]
        public let points: Int
        public func node(_ exerciseID: String) -> Node?
    }
    public static let chapters: [Chapter]
    public static var exerciseIDs: [String] { get }
    public static func evaluate(profile: LocalProfile, history: [SessionRecord],
                                calendar: Calendar = .current) -> Progress
}
```

The exact six chapter arrays are in `SkillCurriculum.swift` and tested against the binding spec, including all 53 unique IDs. Age restrictions affect `isUsable` without deleting earned state/XP. Native practice launch must honor usability and shared setup/access gates; an earned historical node is not permission to assign an adult exercise to a child.

## Representative cross-language fixtures

This exact adult preferences fixture is decoded and round-tripped by `programmePreferencesCrossLanguageFixtureKeepsExactRawValuesAndOptionalAgeCompatibility`. JSON arrays representing Swift Sets are unordered semantically; JavaScript consumers should normalize them as sets.

```json
{
  "goals": ["balance", "weightManagement"],
  "weekdays": [1, 3, 5],
  "minutesPerSession": 20,
  "preferredLocalHour": 18,
  "availableSupport": ["Wall", "Stable chair"],
  "allowsFloorWork": false,
  "excludedExerciseIDs": ["wallSit"],
  "startingPoint": "somePractice",
  "ageContext": {"ageYears": 30, "guardianManaged": false}
}
```

A guardian-managed child uses the same local preference shape with `"ageContext":{"ageYears":12,"guardianManaged":true}`. It must remain local/paired, not sent through cloud-plan sync or analytics. Omitting `ageContext` still decodes but blocks new programme generation with `.ageRequired`; null/missing `startingPoint` means unknown ability and gentle choices.

A recorded set's new effort field is a JSON number such as `"effort":8`; omit it or use null for unrated. The session's `"plannedWorkoutID":"programme:Europe/London:2026-11-02"` matches the selected day. Foundation's existing default Date codec uses seconds since 2001, not Unix time; external JSON boundaries must explicitly agree a codec (for example `JSONEncoder.dateEncodingStrategy = .iso8601` with matching decoding). This task does not introduce a new network date format or upload local records.
