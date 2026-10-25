# Spottr judges' presentation

Ten editable slides for the 25 October 2026, 00:36 UTC evidence snapshot. The deck keeps actual simulator captures, illustrations, implemented behavior, offline tests, live Gemini responses and unverified integrations distinct. Builds 1, 2 and 3 are internally available through TestFlight; builds 1 and 3 are externally available, and build 3 beta review is approved. Physical installations remain unverified.

## Deliverables

- `output/spottr-judges.pptx`: editable text, architecture/prerequisite diagrams, provider table and HR chart. The chart embeds a literal workbook with recorded metrics rounded to three decimals.
- `output/spottr-judges-rendered.pdf`: image-based PDF of the final checked slide renders. The native PDF exporter has a missing `#standard-fonts/Helvetica` dependency; no runtime files were changed or packages installed.
- `output/preview-montage.png`: overview of all ten slides. Full-size renders remain in `previews/`.
- [Presenter guide](../docs/judges-guide.md): suggested two-minute demonstration and accurate claim boundaries.

No PowerPoint/Keynote UI was opened, no provider call was made, and nothing was published. Structural/import/chart checks and raster inspection do not establish native PowerPoint application behavior.

## Sources and revision

`source/assets.json` records original paths and SHA-256 hashes. Existing PNG artwork and the owner's approved actual iPhone/Watch simulator JPEGs were copied byte-for-byte. The current deck uses the two actual screenshots and three existing push-up phase illustrations. The two unchanged PAMAP2 plot PNGs are supplementary evidence in `assets/`; the deck's chart uses the same recorded result JSON as an editable chart.

Each slide's notes contain relevant local source documents and interpretation limits. `source/provenance.json` records the evidence snapshot, asset types, source hashes, deliverable hashes and validation boundary. The refresh records merged Tiger/landing evidence and the Gemini compatibility correction: two signed-simulator native Gemini chats, the corrected camera/manual capability answer, the standalone prototype's 92 offline checks, the configured discomfort-cue correction, Tiger's authenticated console schema acceptance with zero rows, and the revised white-screen landing's local browser acceptance. Strict Node TLS still blocks gateway ingestion/readback; no Tiger workout, rollup or prototype persistence is accepted. Landing publication remains pending. The existing public TestFlight invitation and both landing HTTPS links were verified; no invitation was accepted or app installed. Three explicit production native proposal/session/week actions accepted real Gemini responses after a provider-only schema fix, with isolated synthetic inputs and unchanged full output validation. No proposed plan was approved/saved. Physical networking, real-user coaching quality, physical capture and audible voice remain pending. Recheck release/provider labels before judging if work continues. The 30-second HR test includes only one eligible participant. The fixed adapter worsened error and is not a validated improvement.

The builder uses the bundled `@oai/artifact-tool` and existing assets. It generates no SVG artwork. Native shapes implement only the requested editable diagrams, text and tables. Source: `source/build.mjs`. To revise on this host:

1. Copy the builder into `presentation/.build/build.mjs` and link `.build/node_modules` to the bundled Node packages.
2. Update evidence copy, snapshot and the private revision identifier. The official finalizer refuses to overwrite a completed output or receipt; each revision validates into its own `.build/<revision>/final/` directory before copying the unchanged result to the canonical output path.
3. Run with the bundled Node executable and `RUNTIME_NODE_MODULES` configured. The dependency locations are recorded in provenance.
4. The builder renders every slide from the final imported PPTX. Inspect changed slides at full size and check the whole deck. Keep unmodified asset proportions and all material evidence limits.
5. Run `source/export-rendered-pdf.py` with the bundled Python executable for the static PDF. Create the canonical PNG overview with the skill’s `container_tools/create_montage.py --input_dir presentation/previews --output_file presentation/output/preview-montage.png --num_col 2 --cell_width 640 --cell_height 360 --gap 16 --label_mode none --fail_on_image_error` from the repository root. This assembles existing slide renders; it creates no new illustration.
6. Refresh provenance output hashes after all exports and retain the finalizer receipt under the new private revision directory.

The source builder records its native PDF error and still completes PPTX/render output. `source/export-rendered-pdf.py` assembles already rendered slide PNGs into the separate static PDF without changing their pixels.

The finalizer passed package, font, chart/workbook and first-party import checks. Its conservative native-table height estimate warns on slide 9; the full-size Artifact Tool render was inspected with no table/footer overlap. Native PowerPoint layout remains unverified.

## Output hashes

SHA-256 for the 00:36 UTC snapshot; the complete source/output manifest is in `source/provenance.json`.

| Deliverable | SHA-256 |
| --- | --- |
| `preview-montage.png` | `4c7cf81bb0071f8b0fbf9e02553f458453bbd8b995b804b2a3bee7f4c5eb2c52` |
| `spottr-judges-rendered.pdf` | `0086b7ffbccfd9befe0aa16dc585664c163de9cfbbdd3228c1f666cc2760c23a` |
| `spottr-judges.pptx` | `e1a5666887158512ac1cbf886858b3de5e1ca07044a2f4c02563abd255e137d3` |
