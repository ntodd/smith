---
name: smith-cad
description: Build, inspect, dimension, and validate CAD models with the Smith Elixir library and native OCEx geometry. Use for Smith scripts, assemblies, or Livebook modeling; supports numerical inspection without vision.
---

# Smith CAD

Use the project's installed Smith version. For 0.2, read the [inspection guide](https://hexdocs.pm/smith/inspection.md)
and [API index](https://hexdocs.pm/smith/llms.txt) when selecting operations. In a
checkout or dependency, the same guide is `guides/inspection.md`.

Keep modeling in ordinary Elixir functions and immutable recipes. A standalone
`.exs` is enough; use Livebook when the user wants an interactive walkthrough.
Preserve existing notebook edits and its chosen dependency setup.

Build → evaluate → inspect → check → revise:

- Evaluate expensive stages once. `Smith.from_result/1` branches from a native
  snapshot without rebuilding its source; rerun upstream stages after edits.
- Name relevant snapshots in `Smith.Inspection.run/2`. Inspect topology through
  `Smith.Inspection.topology/3` with bounded pages and geometric selectors.
- Measure actual geometry with `Smith.Measure`. Circle-center anchors expose
  feature spacing; extents expose overall dimensions. Ambiguous selections are
  errors. Face and edge indices apply only to their recorded revision.
- Express requirements as bounds, topology counts, containment, clearance, or measurement checks.
  Read `report.status`: `{:ok, report}` alone does not mean checks passed. Keep
  failed requirements separate from kernel errors and unresolved design data.
- Use `Smith.Inspection.write/3` for JSON and revision-linked PNG observations.
  Text-only agents should read the JSON. Vision-capable agents can also inspect
  the referenced images. Never claim to have inspected an image you did not read.
- Use sections and `Smith.Inspection.compare/2` to investigate internal geometry
  and added/removed material. Compare shapes when equal volume is insufficient.
- For drawings, use `Smith.Drawing.dimension/3` with a `Smith.Measure` from the
  same source revision. Do not label a feature with its input parameter and call
  that a measured dimension. Dimensions are annotations, not driving constraints.
- Finish printable deliverables with `Smith.export/3` and its mesh/STEP checks.
  Follow the project's viewer/reload conventions when they exist.

Coordinates are millimeters; modeling angles are degrees. Report tolerances in
the check's units: containment can use mm, mm², or mm³. Clearance has separate
linear and interference-volume tolerances. Numerical precision, manufacturing
allowances, print compensation, and uncertain drawing dimensions are distinct.

Keep assumptions visible. A valid solid is not proof of intended shape or real
hardware fit. Do not weaken a failing check merely to make a report pass. An empty
or failed section is not evidence of absence of material. Native geometry and
inspection errors remain actionable evidence for the next edit.
