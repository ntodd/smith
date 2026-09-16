# Modeling with coding agents

Smith's inspection tools work in an Elixir process. A coding harness needs shell
access to the native toolkit and a way to read files or stdout; Livebook and
vision are optional. Start with the [inspection guide](inspection.html).

## Modeling workflow

1. Read the project's coordinate convention, units, design requirements, and
   existing source. Preserve user edits and identify unresolved drawing data.
2. Build named immutable stages. Evaluate an expensive stage once, then branch
   with `Smith.from_result/1`. Keep its source recipe as the editable design.
3. Query geometry with `Smith.Inspection.topology/3` and measure it with
   `Smith.Measure`. Refine selectors until they identify the intended feature.
4. Run explicit requirements with `Smith.Inspection.run/2`. Inspect the report
   status and each failed check. A successful function call is not a passed check.
5. Write a revision-linked report with `Smith.Inspection.write/3`. Read the JSON;
   inspect its PNGs when vision is available. Use sections and stage differences
   to investigate a failure, then rerun the same requirements after the edit.
6. Export printable geometry with `Smith.export/3`, which runs mesh and STEP
   readback checks. A valid CAD solid alone does not establish printability.

## Measurements and checks

| Question | Tool |
| --- | --- |
| What faces or edges exist? | `Smith.Inspection.topology/3` with selectors and pagination |
| How far apart are feature centers? | `Smith.Measure.distance/4` with circle-center anchors |
| Did a dimension match the drawing? | `Smith.Measure` plus a measurement check |
| Is a feature fully supported? | A containment check on its base face against the body |
| Do mating parts clear? | A clearance check, including its interference volume |
| What did this operation change? | `Smith.Inspection.compare/2` |
| What is inside this part? | `Smith.section/2`, then inspect, measure, draw, or render the result |
| Can I inspect without a browser? | `Smith.Render.png/2` or an inspection artifact bundle |
| Can I annotate a drawing? | `Smith.Drawing.dimension/3` using measured geometry |

Without vision, use reports and numerical invariants. Do not claim visual
inspection or physical print validation. A dimension copied from an input
parameter is a design intention, not a measurement of the result. Equal volumes
also do not prove equal shapes. For important revisions, compare the actual
added and removed material.

## Errors and limitations

Geometry operations return tagged errors. A selector matching multiple features
must be refined; do not silently choose its first result. Topology indices belong
to one geometry revision and are not semantic names. Explicitly named inspection
sources are stable application labels for snapshots, not a face-tracking system.

Use tolerances in the reported units. Containment may report mm³, mm², or mm;
clearance is mm with a separate interference tolerance in mm³. The toolkit's
numerical tolerance does not replace manufacturing allowances or missing source
dimensions. Document an assumption before using it as a target.

`Smith.Inspection` currently handles material bounds, topology counts, containment,
clearance, and measured-value checks. It does not certify production fit or infer all design
requirements. Headless images render opaque meshes with flat shading. Drawing
dimensions are SVG annotations, not driving constraints or automatic drafting.

## Skills and documentation discovery

The package includes `skills/smith-cad/SKILL.md`. Copy that directory into your
harness's skill discovery directory if it supports the SKILL.md convention. For
example, a user who uses `~/.agents/skills` can copy
`deps/smith/skills/smith-cad` there. Installation is optional; the same workflow is
available in this guide and the public Elixir API.

ExDoc generates `llms.txt` and Markdown pages from the maintained docs and
functions. Start at `https://hexdocs.pm/smith/llms.txt`, then load the relevant
module or guide rather than the entire manual. The repository's `llms.txt` also
links to the agent guide, inspection reference, and package skill. These files
provide guidance; harnesses decide whether to discover and load them.
