# CAD modeling performance investigation — 2026-09-19

## Automatic evaluation follow-up

The final evaluator now optimizes ordinary recipes without new caller options
or model rewrites. This supersedes the earlier requirement below to opt into
batching explicitly.

| Unchanged recipe | Before this follow-up | Automatic evaluation |
| --- | ---: | ---: |
| Plant stand | 4.294 s | 2.110 s |
| Deck clip | 1.338 s | 0.306 s |

Before values are five-sample medians from the build123d comparison session
(`results/modeling-before-automatic.csv`);
final values are ten-sample medians after warmup, in
`results/modeling-automatic-final.csv`. Exports and functional verification
are outside the timers. These are approximately 2.0× and 4.4× improvements.
The public model files are unchanged.

The internal evaluation plan groups runs of three or more compatible cuts or
fusions. Tools must contain only whitelisted, self-contained geometry operations.
Selectors, callbacks, retained snapshots and unknown operations are barriers.
Nodes retain their original indices; preparation or native batch failure falls
back to the original operations to recover the original error context. Older
OCEx releases without batching support evaluate those nodes sequentially.
Two-operation groups remain sequential: batching the clip's pairs did not help
in the follow-up measurements.

Hole validation integrates the intersection of the body and cutter instead of
subtracting two expensive whole-body volume measurements. The native validity
checks, integration tolerance and 1e-9 mm³ removal threshold remain. Pilot and
recess checks still execute separately against the current body. A hole run
reuses an enclosing box, invalidated at every other operation; top-face placement
still resolves after each cut. OCEx supplies an internal conservative envelope
using `BRepBndLib::Add` without triangulation. Public `OCEx.bounds/1` still uses
precise `AddOptimal`. Older releases fall back to precise bounds.

The first follow-up profile reduced clip volume work from roughly 820 ms to
0.45 ms; six additional local intersections took about 62 ms. Reusing the box
removed one 136 ms bounds call; using the conservative envelope removed the
remaining expensive extrema calculation. Intermediate experiments are retained
in `results/clip-automatic-{1,2}.csv` and `results/modeling-automatic-1.csv`.

Regression coverage includes overlapping tools, callback execution and ordering,
original error steps, repeated/tangent holes, recesses inside existing bores,
changing top-face centroids, shrinking envelopes, transforms between holes, and
complete body removal. Both models' functional checks pass. The native helper
is tested for enclosure of curved geometry and source immutability.

Both optimized models also match the previous exported BREP in both directional
Boolean differences (zero volume), with bounds within 1e-5 mm and volume within
1e-7 relative. Smith's full checks passed 313 tests plus four model tests; the
additional native-failure recovery regression passed in the five-test automatic
evaluation suite. OCEx passed 189 normal and 189 sanitizer tests, documentation
checks and the full native stress workload. The 19 automatic-evaluation and
hole tests also passed against the isolated older OCEx build without batch or
envelope support.
Current exports were regenerated and the shared viewer reloaded; its fresh
screenshot and revision/export IDs were checked against the current manifest.

## Earlier investigation

This investigation measures modeling itself, separately from the earlier mesh
processing work. The retained changes are explicit multi-tool Boolean operations,
a bounded native volume cache, and elimination of unused internal Smith snapshots.

## What changed

- `OCEx.cut_many/2` and `OCEx.fuse_many/2` copy their inputs, submit all tools in
  one OCCT operation, and validate the result. Parallel execution stays disabled.
- `Smith.cut_many/2` and `Smith.fuse_many/2` evaluate tools in order and clean the
  final result once. Existing sequential list operations are unchanged. Batch
  operations are explicit because topology, selectors, and error steps can differ.
- Each immutable native shape remembers its first successful volume measurement.
  The integration algorithm and tolerance are unchanged. The cache consists of
  a flag and a double, has the same lifetime as the shape, starts empty on new
  resources, and is protected by the existing NIF mutex. No global shape cache
  or additional retained geometry is introduced.
- Internal recipe tools now return shapes directly instead of creating a BREP
  snapshot, hash, and public Result that the parent immediately discards. Native
  result validation remains, as do public result validation, content revisions,
  retained-snapshot checks, callback execution, and nested error context.

Both repositories have changes on `perf/cad-modeling`. The new Smith batching API
requires the accompanying OCEx changes. Older OCEx versions return a tagged
`:unsupported_operation`; they do not silently substitute compound geometry.
A coordinated OCEx release is needed before consumers can use batching from Hex.
The automatic volume and internal-evaluation improvements need no recipe changes
when the updated libraries are used.

## Experiments and decisions

The native harness in `../ocex/benchmarks/` measures copying, OCCT execution,
validation, cleanup, serialization, and total time separately for 1, 8, and 32
cutters/additions. It compares deep copies with non-destructive sharing and
serial with parallel execution. Two independent runs contain nine samples per
case after two warmups (666 measured native samples total).

Batching won consistently for the 32-tool fixtures. Sharing inputs saved little
for cuts and made chained fusions slower; it was not adopted. Parallel execution
slightly helped one batch-fusion fixture but slowed batch cuts; it was not adopted.
A box fillet was also measured: kernel work, validation, and cleanup all contribute.

The real-model experiments tried batching via compounds first. Cut-only rewrites
provided no meaningful gain. Compound-based fusions failed: the plant stand
reported invalid geometry and the deck clip failed a hole check. Those experiments
are retained in `results/modeling-compound-baseline.*` as rejected evidence.
They are not the implementation of the new APIs.

Profiling the original sequential recipes with the revised Smith evaluator showed
that the plant stand spends about 2.0 s in fusions and 1.3 s in cleanup, versus
0.6 s in fillets. The deck clip spends about 1.46 s across 12 volume calls and
0.28 s in bounds. Caching volumes reduces those 12 calls to about 0.82 s total;
first measurements of new shapes still require precise integration.

The NIF holds one global mutex around its entire dispatch. Eight fixed batch jobs
took median 116.6 ms with one Elixir worker, 112.5 ms with two, and 112.8 ms with
four. This does not show useful multicore throughput scaling. Removing that lock
requires a separate audit of shared topology, native caches, and OCCT global state;
this investigation does not claim it is safe. Native input sharing experiments
are likewise not a concurrency-safety proof.

## Reproduction

Use `OCEX_PATH=../ocex` explicitly when running Smith against the sibling checkout.
Benchmarks are development artifacts and are excluded from Hex packages.

```sh
OCEX_PATH=../ocex mix run benchmarks/modeling.exs --output=benchmarks/results/modeling-current.csv
OCEX_PATH=../ocex mix run benchmarks/recipes.exs --output=benchmarks/results/recipes-current.csv
OCEX_PATH=../ocex mix run benchmarks/measurements.exs --output=benchmarks/results/volume-current.csv
OCEX_PATH=../ocex mix run benchmarks/concurrency.exs --output=benchmarks/results/concurrency-current.csv
OCEX_PATH=../ocex mix run benchmarks/profile-models.exs
```

`modeling.exs` loads only module definitions from the two public model scripts;
it does not execute their installation or export side effects. It saves BREP
fixtures to ignored `output/benchmarks/` for the measurements script. All timed
model evaluations create new shapes. Setup, functional verification, and geometry
comparisons are outside the timer. The batching rewrite in the benchmark accesses
internal recipe data only for controlled experiments; it is not a supported API.
Use the public `cut_many`/`fuse_many` functions in actual recipes.

The original Smith source can be replayed in a separate VM:

```sh
git show 249e26c:lib/smith.ex > /tmp/smith-modeling-baseline.ex
OCEX_PATH=../ocex mix run benchmarks/recipes.exs --reference-smith=/tmp/smith-modeling-baseline.ex --output=/tmp/recipes-before.csv
```

That isolates Smith changes only. The full original baseline additionally uses
an archive of OCEx commit `2522fae`, with its own native binary and Mix build path.
On this macOS run those were `/private/tmp/ocex-cad-modeling-baseline` and
`/private/tmp/smith-cad-modeling-baseline-build`. Canonical paths avoid macOS's
`/tmp` symlink ambiguity in generated build links. Smith baseline file SHA-256:
`84e82db3131f3a9bef70239c83c657121469600535329c9b5f541335d01bba2d`.

Timings are from macOS arm64, Elixir 1.20.1, OTP 29, 18 schedulers, and OCCT 7.9.3
built without TBB. No other validation or benchmark workloads ran during final
measurement collection. Raw per-sample CSVs are saved under `results/`.
This is single-machine evidence, not a guarantee for every CAD model.

## Measured results

Full-model values are medians of five rebuilds per case. The original baseline
uses the isolated original OCEx binary and original Smith source. The final
implementation was measured in two independent VMs; both run medians are shown.

| Model and recipe | Original | Final run 1 | Final run 2 |
| --- | ---: | ---: | ---: |
| plant-stand / existing sequential recipe | 4.121 s | 4.110 s | 4.113 s |
| plant-stand / explicit native batches | 4.121 s | 2.139 s | 1.993 s |
| deck-clip / existing sequential recipe | 2.011 s | 1.333 s | 1.323 s |
| deck-clip / explicit native batches | 2.011 s | 1.289 s | 1.296 s |

The plant stand needs explicit batching to obtain the approximately 2× gain;
its existing sequential recipe remains about 4.1 s. The existing deck-clip
recipe improves about 34% from accurate volume reuse, with batching adding a
smaller gain. The public model source files were not rewritten automatically.

Controlled recipe tests use 15 samples in each of two runs per implementation,
ordered before/after/after/before. They hold the native implementation fixed
before volume caching to isolate Smith's internal-snapshot change.

| Case | Before run medians | After run medians |
| --- | ---: | ---: |
| cut32/chain | 164.90 ms / 178.21 ms | 163.08 ms / 162.79 ms |
| fuse32/chain | 425.31 ms / 429.93 ms | 418.05 ms / 416.60 ms |
| compound100 | 113.86 ms / 118.28 ms | 85.89 ms / 85.34 ms |
| pattern16/rebuild | 134.09 ms / 136.20 ms | 117.82 ms / 118.19 ms |
| pattern16/snapshot_including_preparation | 71.36 ms / 73.05 ms | 54.94 ms / 57.82 ms |
| cut32/batch | New API | 39.21 ms / 40.95 ms |
| fuse32/batch | New API | 78.20 ms / 80.85 ms |

Internal snapshot removal cuts the 100-box compound workload by approximately
25–27%, with smaller improvements in Boolean-dominated chains. Explicit reuse
of one rounded source via `Smith.from_result/1` roughly halves the current
16-instance workload, including the cost of preparing the shared source.
No automatic callback memoization was introduced.

Repeated deck-clip volume measurements (15 samples each) went from a median
115.5 ms to roughly 1 µs of API overhead. First measurements remain about
114–115 ms. Values match exactly across repeated measurements; the dramatic
warm-cache microbenchmark ratio should not be read as a whole-model speedup.

## Verification

Real-model variants are checked for native validity, solid count, volume
agreement within 1e-7 relative, bounds within 1e-5 mm, and both directional
shape-difference volumes within 1e-7 relative. The existing model-specific
functional checks also pass for the final batched variants: drainage, support
feet, hole dimensions, insertion clearances, and flare thicknesses. These are
numerical and functional checks, not a claim of formal geometric equivalence.

Regression tests cover overlapping and duplicate tools, disjoint results,
complete removal, malformed lists, concurrent input/result independence,
repeated measurements across transformations and BREP copies, content revisions,
nested failure context, and invalid retained snapshots. Native ownership and
execution changes additionally run the project's sanitizer and stress gates.

Final gates passed: OCEx `make check docs sanitize stress` (187 tests in both
normal and sanitizer runs, plus the 1,000-workload/12,000-malformed-call stress
run with native resources returning to baseline); Smith `make check docs`
(303 tests including 36 doctests, plus four model tests). The older-OCEx capability
smoke check also passed. `make models` regenerated exports, and `node scripts/view.mjs`
reloaded 34 current models; the fresh screenshot was inspected.

A forced Mix.install cache refresh must be done once in a separate invocation,
not applied to the model test runner that loads two model files in one VM.
After that one-time refresh, the ordinary required checks passed unchanged.
