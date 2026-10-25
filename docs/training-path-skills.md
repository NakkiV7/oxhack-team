# Training path: Skills tab

The Skills tab now holds the personalised training path. It uses the Core logic in
[training-path-core.md](training-path-core.md) and the gateway routes in [training-path-gateway.md](training-path-gateway.md).

## What a person sees

1. **Before a path exists**, the tab shows the existing challenge tree unchanged, with a "Build your training path" card
   above the tab bar.
2. **The survey** asks five questions (goal, starting point, what is nearby, routine, preferences), then shows an
   editable review. Answers are saved as they are given.
3. **Building** makes one Gemini plan through the gateway. If the gateway is not configured, the plan fails the app's
   checks or Gemini is unavailable, the catalogue path for the same answers is shown instead, labelled "Built from the
   catalogue", with the reason. A plan that failed the checks can be sent back once with "Ask Gemini to fix it".
4. **The preview** draws the path, the start reason and emphasis, and, for a new version, what changes, what progress
   carries over and what stays in history. Nothing is saved until "Start my path" or "Save as version N".
5. **The path screen** shows the path level (a game score, not fitness), the current quest, the map or a list, the
   measured Tempo, Consistency and Practice (each "Not assessed yet" until there is evidence, with "How is this
   calculated?"), "Adjust my path" and "All challenges", which opens the full tree.
6. **A step sheet** opens from any node: why the step is there, the practice target, the earned rule and progress
   (manual and camera sets), what comes before it with Go links, the assessment capability, rewards, and an action that
   fits the state: "Go to …" for a locked step, otherwise "Start workout" and "Log manually".

## Design

The app's light theme throughout: white backgrounds, `Palette.surface` cards, blue for the current and open steps, green
for earned, grey for locked, amber for AI-verified, and the existing raster exercise artwork in every node. The goal is a
crest, camera-assessed steps are hexagons with a camera badge, practice steps are circles, and the optional branch has a
dashed outline. Lines leave below a step's name and arrive at the top of the next step, so they never cross labels.

## Accessibility and motion

Every node is a button named with its exercise, state, capability, role and progress, in path order. The list view shows
the same steps as rows. Artwork is hidden from VoiceOver wherever the name is already read. With Reduce Motion on, the
current step's pulse and the preview's reveal are off.

## What stays the same

- **Earned rule.** Three sets at the catalogue goal across two days; the path only changes which steps are open.
- **The existing tree.** `SkillsView` and its files are not edited. It stays mounted under the path screen, because
  swapping one navigation stack for another inside a tab sends the tab bar back to Today.
- **One line in `HomeViews.swift`.** The Skills tab now creates `PathSkillsView`.

## Building locally

The new files need the generated project: run `ruby scripts/generate-project.rb` (needs the `xcodeproj` gem). The
project file is not committed here; the primary chat regenerates it on merge.

## Checks

- `TrainingPathFlowTests` walks the whole flow on an iPhone 18 Pro simulator (iOS 27.1): the tree and the build card
  before a path, the survey, the catalogue preview, saving, the current and locked steps, the locked step's Go link, the
  current step sheet, the list view and "All challenges".
- The existing `SkillsFlowTests` (seven tests) pass unchanged.
- `SpottrFlowTests.testUnavailableCameraLeavesVideoAndStopControlsUsable` fails on this simulator with or without this
  change; it expects "Camera unavailable" from the Today session.
