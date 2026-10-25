# Spottr generated artwork

Generated 24 October 2026 with the built-in `image_gen` tool after Omar resumed image work. No SVG artwork was authored. These are nonrealistic instructional graphics, not measured poses, model outputs or validated exercise instruction.

The nine original transparent PNGs are copied unchanged from the tool's generated-image directory. No manual crop, retouch, recolour or conversion was applied. The existing accepted native assets remain untouched. Exact prompts, source paths, SHA-256 hashes, dimensions and alpha checks are in `artwork-candidates.json`.

## Integrated mapping

| Exercise or role | Candidate file | Native asset name |
|---|---|---|
| Dead bugs | `deadBug-v2.png` | `deadBug` |
| Side plank | `sidePlank-v1.png` | `sidePlank` |
| Step jacks | `stepJack-v1.png` | `stepJack` |
| High knees | `highKnees-v1.png` | `highKnees` |
| Mountain climbers | `mountainClimber-v1.png` | `mountainClimber` |
| Cat-cow | `catCow-v1.png` | `catCow` |
| Hip-flexor stretch | `hipFlexorStretch-v1.png` | `hipFlexorStretch` |
| Single-leg stand | `singleLegBalance-v1.png` | `singleLegBalance` |
| Skill-building onboarding | `onboarding-skills-v1.png` | `onboarding-skills` |

These eight exercise IDs fill the current catalog's missing artwork. Keep the existing nine variation icons and use `pushup-mid` / `squat-mid` for the two camera-trackable entries, giving all 19 catalog exercises an image. Keep all six accepted `pushup-{top,mid,bottom}` and `squat-{top,mid,bottom}` phase images. The accepted `strength` bicep remains useful for navigation/strength grouping.

## Visual integration

- Exercise candidates use opaque black and pale grey, without mint joint dots, and are intended for a white or very light node surface. Do not place black silhouettes directly on a dark node.
- Preserve aspect ratio and use `scaledToFit`; horizontal exercises naturally occupy less height than standing ones. Use a consistent node canvas, not stretched figures.
- All eight were inspected at a 48 px icon size on white. Labels are still necessary to distinguish similar poses and support accessibility. Show the larger illustration on the detail screen.
- The onboarding hero is a complete ascending path with exercise nodes and a bicep destination. Use it at roughly 240–320 pt; it is not intended as a 48 px node icon. Its lone mint completion tick fits restrained completion colour.
- `artwork-review.html` / `artwork-review.png` are review aids with labels outside the images. They are not app assets.

## Validation

All nine originals decode as RGBA PNG, have fully transparent corners/background pixels and opaque figure pixels, and show complete subjects without embedded labels. Full-size and 48 px browser inspection found no obvious clipping or additional limbs. No live camera, health, ML or app behaviour is verified by this artwork check.

The parent reviewed and approved these nine images. Each is now copied byte-for-byte into its corresponding new `Assets.xcassets` imageset. `catalog-asset-validation.json` records that all 19 catalog art IDs resolve to nonempty transparent RGBA PNGs, the nine new copies match their source hashes, and all 34 pre-existing asset files remain unchanged. The original candidates are retained here for provenance.

One early dead-bug generation had an unwanted glow and was rejected; it remains only in the tool's original output directory. `deadBug-v2.png` is the clean selected image. App wiring, builds and commits remain owned by the parent task; this validation covers assets only.
