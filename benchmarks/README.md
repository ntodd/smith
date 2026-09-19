# Performance review

For the latest modeling results, see [automatic compiler optimizations](COMPILER_OPTIMIZATIONS.md),
including the build123d comparison. The measurements below describe the earlier
mesh-processing work.

Run from the Smith repository with the sibling OCEx checkout explicitly selected:

```sh
OCEX_PATH=../ocex mix run benchmarks/performance.exs --samples=30 --output=/tmp/after.csv
```

The suite separates native geometry, recipe evaluation, text/SVG layout, mesh
welding and connectivity, STL/3MF serialization, and the complete checked print
mesh pipeline. Compilation and fixture creation are excluded. Each case has
three warmups followed by independent samples in fresh monitored processes;
process creation and initial GC are outside the timer, while allocation and GC
during the operation are included. CSVs contain minimum, median, nearest-rank
p95 microseconds, and median BEAM reductions. Reductions are supporting evidence
for Elixir work, not a measure of native CPU time or peak memory.

Use the original implementation in a separate VM for a reproducible comparison:

```sh
git show 9f78ac4:lib/mesh.ex > /tmp/smith-reference-mesh.ex
OCEX_PATH=../ocex mix run benchmarks/performance.exs --samples=30 --reference-mesh=/tmp/smith-reference-mesh.ex --output=/tmp/before.csv
OCEX_PATH=../ocex mix run benchmarks/equivalence.exs /tmp/smith-reference-mesh.ex
```

`--reference-mesh` compiles the supplied trusted source into that benchmark VM;
it does not change repository files. Alternate before/after runs with other
builds and checks stopped. Compare several runs rather than isolated minima.
No CI timing thresholds are imposed on shared hardware.

Fixtures include a 20 mm sphere (3,302 welded vertices / 6,600 triangles), a
20,000-triangle connected planar grid, 5,000 disconnected triangles, and a
nonmanifold fan with 2,000 triangles sharing one edge. The latter two expose
algorithmic scaling and are not claims about typical printable models.
The checked export case includes native triangulation, welding, STL encoding,
STL decoding, connectivity/volume checks, and comparison with native volume.
It excludes file I/O, STEP export, and the viewer.

## Changes under measurement

Connectivity previously connected every triangle on an edge to every other
triangle, including itself. A star has the same connected components with
linear adjacency storage even for high-valence nonmanifold edges. Component
seeds now come from one fixed triangle list instead of repeatedly enumerating
a shrinking MapSet. Existing edge counts, orientation checks, and signed volume
calculations remain in place.

STL encoding builds one 50-byte binary per facet, replacing four small binaries
and a nested list per facet. Normals, coordinate precision, winding, headers,
and attribute bytes remain identical.

The equivalence script compares full inspection reports and exact STL bytes
against the original implementation for 1,000 seeded meshes, including repeated
indices and nonmanifold edges. Behavioral tests separately cover analytical
box volume, disconnected closed shells, winding, vertex-only contacts, empty
meshes, and decoded STL normals/coordinates.

## Results — 2026-09-18

macOS arm64, Elixir 1.20.1, OTP 29, 18 schedulers, OCCT 7.9.3.
Smith baseline: `9f78ac4`; OCEx: `2522fae`. Three independent VM runs per
implementation, 30 samples per case per run (3,600 timed samples total),
plus three warmups per case per run. Run order: before/after, after/before,
before/after. Other validation jobs finished before collection. The six
saved CSVs in `results/` include p95 and BEAM reduction measurements.

Values below are the median of the three run medians in microseconds.
Ranges show the smallest/largest run medians; positive percentages mean
less elapsed time. Small control-case changes are noise, not optimizations.

| Case | Before µs | After µs | Time reduction | Run ranges: before / after µs |
| --- | ---: | ---: | ---: | --- |
| native/box | 183 | 183 | 0.0% | 181–188 / 180–192 |
| native/cut | 2434 | 2445 | -0.5% | 2376–2467 / 2415–2454 |
| native/mesh_sphere | 10276 | 10334 | -0.6% | 10258–10302 / 10304–10493 |
| native/brep | 15 | 18 | -20.0% | 15–16 / 17–18 |
| native/volume | 207 | 204 | 1.4% | 202–207 / 203–206 |
| recipe/evaluate | 2131 | 2109 | 1.0% | 2120–2141 / 2096–2125 |
| text/layout | 7972 | 8002 | -0.4% | 7943–8094 / 7967–8011 |
| svg/layout | 3051 | 3075 | -0.8% | 3046–3091 / 3053–3103 |
| mesh/weld_sphere | 2199 | 2151 | 2.2% | 2162–2224 / 2134–2216 |
| mesh/inspect_sphere | 9539 | 8985 | 5.8% | 9510–9584 / 8914–9035 |
| mesh/inspect_grid_5000 | 6883 | 6516 | 5.3% | 6879–6903 / 6370–6635 |
| mesh/inspect_grid_20000 | 35911 | 32255 | 10.2% | 35579–36274 / 31977–32332 |
| mesh/inspect_islands_1000 | 4404 | 1013 | 77.0% | 4375–4492 / 1003–1075 |
| mesh/inspect_islands_5000 | 81755 | 4900 | 94.0% | 79160–82021 / 4849–4918 |
| mesh/inspect_fan_1000 | 26776 | 912 | 96.6% | 26408–27252 / 895–931 |
| mesh/inspect_fan_2000 | 275898 | 2006 | 99.3% | 266619–277940 / 2005–2076 |
| mesh/to_stl | 1718 | 1229 | 28.5% | 1714–1754 / 1213–1277 |
| mesh/from_stl | 4919 | 4873 | 0.9% | 4918–5013 / 4828–5100 |
| mesh/to_3mf | 6082 | 6089 | -0.1% | 6069–6093 / 6077–6197 |
| export/checked_sphere | 27674 | 26950 | 2.6% | 27630–27782 / 26862–28790 |

The ordinary mesh improvements repeat across all three runs: sphere
inspection is 5.8% faster, the 20,000-triangle grid is 10.2% faster, and
STL serialization is 28.5% faster. Disconnected triangles improve 16.7×
and the high-valence fan 137.5×. Growing disconnected input from 1,000 to
5,000 triangles now costs about 4.8× rather than 18.6×. These pathological
cases demonstrate removal of avoidable superlinear work, not typical
whole-application speedups.

Checked sphere export has a 2.6% lower median across runs, but one optimized
run is slower than every baseline run. The overlapping ranges do not support
a reliable end-to-end speedup claim. Native meshing alone costs about 10 ms;
the unchanged native, recipe, text, and SVG controls show no material gains.
The native BREP microbenchmark changes by only 3 µs despite its large relative
percentage. No native geometry validation, immutability, or tolerances were
relaxed to obtain the improvements.

## Verification and limits

- Smith: `OCEX_PATH=../ocex make check docs` passed; final check rerun passed
  300 tests (36 doctests and 264 tests) plus four model tests.
- OCEx: `make check docs` passed, including 182 tests.
- Seeded equivalence check passed for 1,000 meshes, with byte-identical STL.
- `OCEX_PATH=../ocex make models` regenerated exports. The shared viewer was
  reloaded with `node scripts/view.mjs` and its fresh screenshot inspected.
- No native ownership or execution changes; sanitizer/stress gates for such
  changes are not applicable. No notebook or editor-owned files changed.

This is a single-machine review of representative workloads. It does not
measure concurrent throughput, peak memory, STEP file I/O, or browser rendering
performance. Native meshing remains a substantial cost in checked exports;
changing its copy/ownership strategy would need a separate concurrency and
immutability investigation. Timing thresholds are deliberately not tests.

The subsequent [CAD modeling investigation](CAD_MODELING.md) measures Boolean
operations, fillets, model rebuilds, precise measurements, and reuse separately
from these mesh-processing results.
