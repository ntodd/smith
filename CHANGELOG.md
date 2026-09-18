# Changelog

## Unreleased

- Add immutable SVG assets and deferred artwork recipes, with fills, strokes,
  holes, group selection, units/transforms, physical fitting, and plane placement.
- Add geometry-linked SVG reports/previews, filled-outline export, and centerline
  paths for sweeps/projection. Unsupported visible features return tagged errors.
- Add an original volleyball asset, equivalent outlined fixture, and interactive
  file-upload/keychain notebook with raised and engraved variants.
- Accept SVG compact decimals and retain six licensed upstream icon fixtures
  with physical sizing, extrusion and engraving regression checks.
- Requires the accompanying unreleased OCEx planar artwork operations. Use
  `OCEX_PATH` to test both checkouts until the next coordinated package release.

## 0.3.0

- Refine the Livebook and documentation viewer toolbars, clipping controls,
  and responsive sizing.
- Add immutable font snapshots and deferred text recipes using OCEx 0.3.
  Position text on any plane, extrude names and fuse/cut them into parts.
- Measure actual ink, fit names proportionally, and validate placement/margins
  and visible height. Reports include font SHA-256, glyph layout and geometry
  revision, with matched headless PNG and font-independent outline SVG artifacts.
- Add a text/keychain guide and licensed varsity-style Graduate example font.
  Native builds now require FreeType, HarfBuzz and pkg-config.

## 0.2.0

- Reorganize guides and Livebooks into a 0.2 learning path, with CAD terminology,
  measured drawing lessons, and explicit limitations in the phone study.
- Render drawings through `Smith.Kino.render/2` with responsive sizing, fullscreen,
  and SVG download; screen sizing preserves the export's millimeter dimensions.

- Add geometry-derived dimensions, bounded topology inspection, explicit containment/clearance checks, and JSON reports with revision-linked artifacts.
- Add headless depth-buffered PNG views and colored stage comparisons without a browser or GPU.
- Add measured SVG dimensions with extension lines, center marks, and explicit placement.
- Add Kino standard views, native edge overlays, clipping controls, and colored layers.
- Ship an agent modeling guide, an optional Smith CAD skill, and a curated repository `llms.txt` alongside ExDoc's generated index.

- Add `Smith.from_result/1` to branch from evaluated geometry without rebuilding earlier operations.

- Add world-space and sketch Bézier curves backed by OCEx 0.2.
- Add an iPhone 17 Pro modeling study with dimensioned profile stations, inspection checks, and one-piece/split exports. Document the unresolved edge-roll defect; this study is not a validated case-fit reference.

- Add a Raspberry Pi enclosure Livebook covering reference geometry, a sliding tray, cam latch, cooling duct, clearance checks, and printable exports, with interactive previews in HexDocs.

- Render geometry examples throughout the README, guides, and API docs from their accompanying code. Include SVG drawing outputs and still images for GitHub.
- Display sampled paths and edge-only geometry in the shared Kino renderer.

## 0.1.0

- Return Kino previews directly and accept piped evaluation/view results; preview failures raise with their reason.

- Add parallel/conical curve projection, projected-wire face conversion, and a projection Livebook.

- Add symmetric and tapered extrusion, extrusion up to a plane, and a worked extrusion Livebook.

- Add evaluated assembly views for installed, display, and exploded inspection; update assembly notebooks.

- Add named joint frames, directed connections, five motion types, limits, and resolved pose reports.

- Add reusable nested assemblies, path lookup, leaf enumeration, and tree-aware export reports.

- Add planar split/section, draft, face extraction, 3D surface offset, and open-surface thickening.
- Update the worked models and assembly notebook, and add a staged forming notebook with analytic checks.

- Add measured selectors, stable sorting, unions/exclusions, and topology metadata inspection.
- Add planar mirrors, spheres, ring tori, rounded rectangles, and straight slots.
- Add blind holes, counterbores, and countersinks with explicit entry planes and depth.
- Document assembly export and move assembly result/export modules under `lib/assembly/`.
- Add smooth lofts, open-path sweeps, and shelling with signed thickness.
- Add composable edge/face selectors, explicit paths, and local sketch splines.
- Add a worked Livebook and a guide for selection, profile placement, and hollow parts.

Initial release of Smith.

- Immutable Elixir recipes backed by native OCEx geometry.
- Primitives with shared `at:` and per-axis `align:` options, world-coordinate profiles, booleans, finishing, and explicit placement.
- Local planes and sketches, alignment, convex corner fillets, cutouts, extrusion, revolve, and ruled loft.
- Named assemblies with references, reusable instances, print placement, and printable extras.
- STEP/BREP/STL/3MF bundles with print-mesh and STEP round-trip checks, separate export directories, and assembly manifests.
- Optional Livebook previews with fullscreen, staged examples, and PNG downloads.
- API reference with executable examples, option defaults, coordinate conventions, and error contracts. Guides cover installation, modeling, assemblies, export checks, and Livebook.

- Added `Smith.Drawing` orthographic views, curve sampling, and millimeter SVG/DXF polyline export, with a guide and executable Livebook.
