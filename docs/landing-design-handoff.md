# Spottr landing design handoff

For Misha, landing issue 2. This is a design reference and acceptance brief, not a landing implementation. NAKU and TinyTaps were inspected read-only; no files in either repository were changed. Reuse their successful composition patterns while retaining Spottr's own identity and assets.

## References and transferable patterns

| Reference | Useful pattern | Apply to Spottr |
|---|---|---|
| NAKU: `site/dist/index.html`, `merged.css` | Large, direct headline; short supporting paragraph; clear primary action; actual app screenshot beside a distinctive illustration | Lead with the coaching experience and one large, current iPhone screen. Use Spottr's accepted exercise graphics rather than decorative dashboard cards. |
| NAKU: `site/dist/tour.mjs`, `tour-state.mjs`, `motion.mjs` | Screenshot-led product tour; separate user roles; motion pauses on focus, hover, hidden document and reduced-motion preference | Show Train, Review and Skills as a short, manually controlled tour. Pair iPhone and Watch only where their real interaction is visible. |
| TinyTaps: `landing/dist/index.html`, `style.css` | Compact header, generous whitespace, one focused phone illustration, three concise benefits separated by fine rules | Keep the page brief. Use a restrained three-benefit row rather than a long feature-card grid. |
| TinyTaps: mobile styles | Clear stacked reading order, compact navigation, comfortable tap targets, explicit illustration label | Keep headline, supporting copy and CTA before the phone at narrow widths. Label replay/sample material accurately. |

Source roots: `/Users/scsoc/dev/NAKU` and `/Users/scsoc/dev/TinyTaps`. Local hero renders were inspected at 1440×1000 and 390×844 with reduced motion; neither rendered page showed horizontal overflow. This is a local reference check, not a claim about their public deployment or complete accessibility. Temporary previews: `/tmp/spottr-reference-{naku,tinytaps}-{1440,390}.png`.

## Proposed page

1. **Header:** Spottr wordmark, How it works, Skills, and one primary action. Keep sponsor/platform details out of the main navigation.
2. **Hero:** “Make every rep count.” Supporting direction: “Train with live form cues, follow your progress, and build your next skill.” Use a real native workout screen, a small Watch companion where useful, and accepted flat exercise art. Primary CTA should open a working demo or recording; use a truthful availability label if there is no public app destination. Secondary action: See how it works.
3. **Three benefits:** See your form; Review your training; Build your next skill. Each needs one concrete sentence and one relevant visual. Distinguish the two camera-trackable exercises from the broader exercise catalog.
4. **Product tour:** Train → Review → Skills, with actual screenshots and short captions. Show the connected skill tree and visible prerequisites. Explain what users do next rather than describing the internal architecture. A Watch caption must reflect the actual connection/data state shown.
5. **Optional small integration row:** Include only services demonstrated by the current product, with a brief accurate role for each. This belongs below the product explanation. Avoid implying every sponsor integration is already live.
6. **Closing action and compact footer:** Repeat the working primary action. Add only verified project/support/privacy destinations; the builder should obtain the correct facts before adding legal or availability claims.

## Visual direction

White background, near-black type, light grey dividers and generous spacing. Use a compact system sans serif, strong headings and readable body copy. Keep one restrained completion green; reserve form amber/red for actual form feedback. Show approved raster silhouettes with their aspect ratio preserved. The onboarding `onboarding-skills` illustration can support the Skills section, while an actual app screen remains the hero's main product evidence.

Use NAKU's clarity and TinyTaps' restraint. Their mascots, palettes, typography, branded copy, illustrations, personal/legal text, company information and destination links are not transferable assets. Do not add invented readiness scores, validated injury-prevention claims, or predictions about safe training to failure.

## Acceptance brief

- Use lightweight static delivery and local optimized images with explicit dimensions. Keep essential text/actions available without motion or a carousel.
- Verify 320, 390, 768 and 1440 px layouts, keyboard navigation, visible focus, image alt text and adequate contrast. Offer pause controls for any automatic movement and respect reduced motion.
- Use real screenshots; clearly label sample data, replay material or illustrations. Confirm every CTA's destination and displayed availability.
- Opening the landing page must not start camera capture, voice playback, biometric collection or paid API calls.
- Capture desktop/mobile evidence of the hero and product tour after implementation. This brief does not certify native runtime behavior or any cloud integration.

Misha retains implementation choices within issue 2. The brief adds no dependency on a new animation library, account flow or external service.

## Availability and usability pass — 24 October 2026

The follow-up preserves Misha's layout, feature grid and existing design imagery. Both placeholder App Store destinations are replaced by disabled **TestFlight soon** controls. Copy distinguishes offline counting/history/on-screen cues from optional online Gemini requests and uploads; unsupported recovery and live voice claims were removed, with voice marked planned. Interface concepts and Watch sample values are labelled as previews. All five existing PNGs are copied unchanged into `landing/assets/` so the page can be served on its own, with explicit dimensions and preserved aspect ratios. It uses system fonts without a remote font request.

Skip navigation, visible keyboard focus, fixed-header anchor spacing and reduced-motion handling are included. The [landing guide](../landing/README.md) explains local preview and contribution boundaries. This pass does not publish a website or establish app/device/provider availability.

CUA-controlled Chrome rendered the page at desktop width and approximately 320, 390, 768 and 1440 CSS px using native window resizing and page zoom. Hero/badge wrapping, feature stacking, uncropped images and the closing availability controls were visually inspected. Keyboard navigation reached Skip to content, moved into main content and skipped the disabled availability buttons; the How It Works link reached its section below the fixed header. Source/local HTTP checks found five image responses at 200 with hashes matching the originals, six valid internal anchors and no remote startup resources or script elements. This is desktop reflow evidence, not mobile touch/device emulation. Native Chrome developer tools did not open through the available controls, so console-log health and a measured DOM overflow check remain unverified; no error overlay or visual clipping was observed. Reduced-motion support was inspected in CSS without changing the system setting. Safari, publication and app availability remain outside this check.
