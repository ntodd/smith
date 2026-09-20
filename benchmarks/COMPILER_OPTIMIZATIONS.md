# Automatic evaluator optimizations — 2026-09-19

Subsequent work is documented in [incremental evaluation and transform fusion](INCREMENTAL_EVALUATION.md).
The cache-lifetime descriptions and measurements below describe this earlier checkpoint.

The validated automatic-batching checkpoint was committed as Smith `e872321`
and OCEx `7a6aacf` on `perf/cad-modeling`. Production model recipes contained
no explicit batching calls and remain unchanged. The following work builds on
that checkpoint without adding public recipe options or requiring manual reuse.

## Retained optimizations

- **Common subexpressions:** the planner identifies repeated, self-contained
  recipe bases, stripping trailing rigid placements from their identity. Static
  fillets, chamfers and hole features are eligible; callbacks, retained snapshots,
  file-backed operations and unknown operations are not. Successful geometry is
  reused lazily, with at most 128 candidate bases retained per evaluation. Scope
  is restored even when callbacks raise; nested evaluations get independent
  scopes. No shapes are cached across calls.
- **Independent holes:** three or more explicit-plane hole features can use one
  body cut if their complete cutter envelopes are pairwise disjoint. Pilot
  material and additional recess material are checked separately. Overlap,
  body-dependent top-face placement, uncertainty, or failure uses the original
  sequential path and original recipe error indices. Speculative exceptions
  also replay sequentially, preserving an earlier feature's failure.
- **Shared intersections:** sequential checked holes use one OCCT
  `BOPAlgo_PaveFiller` for both cut and common results. This avoids computing the
  same intersections twice while retaining output validity checks and the
  existing adaptive volume integration and minimum-removal threshold.
- **Placement work:** primitive alignment and position are combined into one
  translation. Unrepresentable coordinates still return tagged errors. Native
  translate/rotate/scale no longer copy a shape before calling the transform
  algorithm with `Copy=true`, which already makes an independent copy.
- **Selective kernel parallelism:** Boolean batches with at least three tools
  against bodies with at least 128 faces request OCCT parallel execution. Small
  operations remain serial. Inputs are copied, and the native state/resource
  mutex remains held. No global thread-pool configuration is changed.

## Measurements

Timings are warm-process rebuilds on the same macOS arm64 machine, excluding
imports/VM startup, exports and external verification. Each row uses a median;
timing thresholds are not tests. Smith uses local OCCT 7.9.3 without TBB.

| Workload | Committed checkpoint | Final |
| --- | ---: | ---: |
| Plant tray, ordinary recipe | 1.953 s | 1.836 s |
| Deck clip, ordinary recipe | 0.283 s | 0.206 s |
| 16 placed copies of a rounded part | 116.40 ms | 46.74 ms |
| 100-part compound | 84.49 ms | 64.42 ms |
| 32 ordinary cuts (already automatically batched) | 38.91 ms | 36.20 ms |
| 32 ordinary fusions (already automatically batched) | 75.86 ms | 69.96 ms |

The 16-part automatic-reuse case also beats the manually prepared snapshot case
in this run (52.39 ms including source preparation). Final real-model medians
use ten samples; checkpoint models use five; recipe cases use ten. Raw data:
`compiler-baseline.csv`, `compiler-final-verified.csv`,
`compiler-recipes-before.csv`, and `compiler-final-recipes.csv` in `results/`.

The sequence of experiments is retained separately: `compiler-parallel-default`,
`compiler-parallel-four`, `compiler-recipes-reuse`,
`compiler-reuse-adaptive-parallel`, `compiler-final-models`, and
`compiler-independent-holes`. The checkpoint predates subrecipe reuse; the
intermediate final-models file predates independent-hole batching.

## build123d comparison

The user's existing Python recipes were run in their existing environment:
build123d 0.11.1 / OCP 7.9.3.1. They were imported without executing their export
entry points. A temporary benchmark-only variant batches the tray's annular
cutters, clipped spokes, and supports, and the clip's six final drilling cutters.
The user's Python source files were not edited, and no Python dependency was
added to either public repository.

| Model | build123d existing recipe | build123d manually batched | Smith automatic |
| --- | ---: | ---: | ---: |
| Plant tray | 6.123 s | 4.947 s | 1.836 s |
| Deck clip | 0.228 s | 0.152 s | 0.206 s |

Python values are five-sample medians after warmup. Existing and batched Python
models passed validity, solid-count and matching-bounds/volume checks; the tray
also passed drain and foot-count probes and the clip passed its own full feature
verification. No cross-library Boolean equivalence claim is made for the new
manually batched Python variants. Smith's model-reference suite independently
checks its geometry against the established reference models.

These are end-to-end recipe comparisons, not matched wrapper-overhead tests.
Kernel build flags, internal validation work and mass-property defaults differ.
In particular, the Python clip performs direct cylinder subtractions, while
Smith checks that every pilot and recess actually removes material. The tuned
Python clip remains faster. Raw Python samples and numerical checks are in
`results/build123d-compiler-comparison.json`.

## Parallelism and remaining opportunities

OCCT supports `SetRunParallel` and a built-in thread pool even without TBB;
TBB changes the backend rather than enabling otherwise unavailable threading.
See the [OCCT parallel API](https://dev.opencascade.org/doc/occt-7.8.0/refman/html/classOSD__Parallel.html)
and [thread-pool release notes](https://dev.opencascade.org/sites/default/files/pdf/release_notes_7.4.0.pdf).

Requesting parallel execution for all three-or-more-tool batches reduced the
tray median from 1.953 s to 1.873 s. A four-thread pool gave 1.863 s, too small a
difference to justify changing OCCT's process-wide pool policy. The retained
policy instead gates parallel execution on substantial incoming topology and
leaves the pool's configuration alone. The heuristic is empirical, not a
guarantee for every shape or machine.

Independent Elixir evaluations still serialize at the native mutex. Removing it
without isolating OCCT mutable state and shape caches would not be justified by
these tests. Further promising work includes isolated kernel workers for
independent models, sharing intersection preparation across an entire checked
hole batch, composing long transform chains into one native transform, and
document-scoped incremental caching with explicit invalidation and ownership.

## Verification

- Smith: 322 tests (36 doctests, 286 tests) and four model-reference tests passed.
- OCEx: 192 normal and 192 sanitizer tests passed. Extended stress included
  1,000 shape workloads, 100 checked cuts and 24,000 malformed calls; tracked
  native resources returned to baseline.
- The 28 targeted evaluator, reuse and hole tests passed against the older OCEx
  build without batch/envelope/checked-cut helpers.
- Both final models matched previous exports in precise volume and bounds;
  both directional Boolean differences had zero volume.
- Model exports were regenerated. The shared viewer's new screenshot was
  inspected and its geometry revisions/export IDs matched the current manifest.
