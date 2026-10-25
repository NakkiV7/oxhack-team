# Skill tree

Skills offers a connected grid and a linear list of the same 19 exercises. The chosen layout is remembered locally. Every node opens its exercise instructions and logging controls, including challenges whose prerequisites are pending.

Earn a challenge with three goal-meeting sets across two local calendar days, plus all of its incoming prerequisites. The graph combines each family's earlier level with selected supporting challenges: plank supports push-ups, side plank supports close-grip push-ups, balance supports reverse lunges, mobility supports assisted single-leg squats, and plank supports mountain climbers. Practice before unlocking is retained.

Manual and camera sets contribute with their source shown in exercise details. Video replays and discomfort-stopped sets do not earn challenge progress. XP remains a deterministic game score, not a measured strength, recovery or readiness estimate. The graph controls achievements; it does not restrict which exercises someone can practise.

Add exercises in `ExerciseCatalog`, prerequisites in `SkillGraph`, and behavior cases in `SkillGraphTests`. Keep edges acyclic and check both layouts. This is the first unreleased graph version; changing its prerequisites can change previously computed completion states.

Validation: all staged shared tests passed (37 XCTest and 71 Swift Testing cases). All four Skills simulator flows passed, covering manual history/progress persistence, hold pause/review, library tracking labels, and grid/linear navigation and preference persistence. No physiological or camera-accuracy validation is implied.
