# Elixir reproductions of the CAD projects

- [`Models.PlantStand`](plant_stand.exs): 247.65 mm pot riser, seven slot bands, eight spokes, 13 feet, R2 slot/root fillets, 0.5 mm rim chamfers.
- [`Models.DeckClip`](deck_clip.exs): tapered return-arm spline, signed circular arcs, mounting plate and flange, side trimming, R0.8 rounds, drilled/counterbored holes.
- [`Models.Verification`](support/verification.exs): independent reference comparison and geometric probe helpers loaded by tests and opt-in export audits.

The clip and stand's `build/1` returns a deferred `Smith.Model`. Dimensions live in a struct; `Smith.evaluate/1` constructs the native geometry. Neither model reads the reference files during construction.

From the repository root:

```sh
elixir models/plant_stand.exs
elixir models/deck_clip.exs
node scripts/view.mjs
```

Exports are revisioned under `output/models/<name>/<sha256>/<export_id>/`. Normal exports verify native geometry, printable meshes, and STEP round trips before updating `current.json`. Pass `--verify` to any script to also run frozen-reference and functional audits; `make check` always runs those audits. Reference helpers and test modules are not loaded for normal exports or `--no-export`. Run the scripts sequentially. STEP/BREP retain the installed orientation. The stand's STL/3MF have the pot-contact face on the print bed. The clip retains its original print orientation. 3MF files contain geometry, without printer settings.

## Reference provenance

The reference STEP and JSON files were copied unchanged from the user's existing projects:

- `Deck Clip/output/v04/deck-clip-v04.step`
- `Plant Tray Insert/output/v04/plant-tray-insert-v04.step`

SHA-256:

```text
662371e08e184cc2a67f82eb3cebc9079cc560b50e9035acdb14c6b09113834a  deck-clip.step
958ef5e12c09bfdcd61aefabd1e2bdd49ce8ebbac9487afa424936f1a6cf8ab2  plant-stand.step
```

The original model sources and the installed build123d 0.11.1 implementation were read as references. No Python process was used for modeling, testing, meshing, or export. OCEx calls the same OCCT algorithms directly: `GC_MakeArcOfCircle`, `GeomAPI_Interpolate` (1e-6 tolerance, automatically scaled endpoint tangents), and `ShapeUpgrade_UnifySameDomain` (edges/faces/BSpline concatenation enabled, internal edges disabled). Cleanup and finishing order follow the original models.

## Acceptance criteria

Every result must be one valid solid. Against the frozen STEP reference, maximum envelope-coordinate error must be below 1e-4 mm, absolute volume error below 0.01 mm³, and both directional Boolean residual volumes below 0.001 mm³. About 400 mesh-node boundary samples in each direction must lie within 1e-4 mm of the other model's shells. These samples supplement the full Boolean comparisons; they are not a formal Hausdorff-distance proof.

The stand also checks seven clear drain bands, 13 disconnected feet in a 0.5 mm bottom slice, and four continuous intermediate supports. The clip checks actual cylindrical hole radii/axes/positions, seven clear insertion stations, widening clearance, and five measured taper sections using solid-line intersections.

The STL bytes themselves are re-read and checked for closed two-face edge incidence, opposite edge winding, one connected component, and less than 0.5% volume error. STEP exports are re-read and checked for one valid solid and less than 1e-6 relative volume error. STEP serialization and numerical integration can introduce tiny measurement differences even when Boolean residuals are empty.

The migration reproduces the existing geometry and its existing design assumptions; it does not change the dimensions or constitute a new physical fit/load test.

## Functions and composition

These are ordinary Elixir scripts. There is no models Mix project, application, or custom Mix task. Each script uses `Mix.install` to load this Smith checkout, defines its feature functions, and runs its checked export. OCEx resolves from Hex unless `OCEX_PATH` explicitly selects a development checkout. The native dependency is compiled and cached on the first run.

The clip script includes its profile module, so the entire assembly definition is in one file. Shared reference verification helpers live in `support/`, and functional checks live in `test/`. Generic file export, printable mesh validation, STEP round trips, and manifest publication belong to [`Smith.Export`](../lib/export.ex). Each script supplies its model name, placement options, and verification metadata.

To load the functions in IEx without exporting:

```sh
iex models/deck_clip.exs --no-export
```

```elixir
alias Models.DeckClip

# Evaluate the whole design.
{:ok, clip} = DeckClip.build() |> Smith.evaluate()

# Reuse a feature independently and branch it with ordinary functions.
dimensions = %DeckClip{hook_width: 36.0}
hook = DeckClip.hook(dimensions)
{:ok, placed_hook} = hook |> Smith.translate({100, 0, 0}) |> Smith.evaluate()
```

`DeckClip.build/1` composes its hook, mounting plate, flange, tip trimmers, edge rounds, and screw-hole tools in one pipeline. The stand follows the same pattern with a drained deck, radial supports, intermediate feet, and center foot. Repeated features are produced with maps/comprehensions; `Smith.cut/2` and `Smith.fuse/2` accept ordered lists of recipes. Lists preserve operation order and expand into normal deferred operations.

The hook section and curve math live in [`DeckClip.Profile`](deck_clip.exs), isolated from feature assembly; geometry evaluation remains explicit in `Smith.evaluate/1`. For this clip, rounding must happen before drilling to preserve the cylindrical holes and counterbore seats. Composition preserves that required order.

`make models` runs both scripts sequentially; `make view` also reloads the shared viewer. `make check` runs the library tests and the assemblies’ ExUnit tests using plain Elixir. OCEx and Smith remain Mix libraries; the assemblies need no project scaffold.

## Print mesh settings

The clip uses absolute linear deflection **0.005 mm** and angular deflection **0.05 radians**. The stand uses **0.02 mm** and **0.08 radians**. These match the respective Python scripts. STL and 3MF use the same welded print mesh; `verification.json` records both settings. Viewer preview meshing remains independent. Matching settings does not guarantee identical triangulation after STEP serialization.
