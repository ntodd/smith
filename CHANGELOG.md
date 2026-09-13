# Changelog

## Unreleased

- Embed the shared 3D renderer in HexDocs, with meshes generated from the documented examples.

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
