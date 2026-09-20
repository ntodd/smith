# Incremental evaluation and transform fusion

Follow-up to Smith `247e54f` and OCEx `3991368`. All retained changes work through
ordinary recipes and `Smith.evaluate/1`; no public recipe options are added.

## Retained changes

**Transform fusion.** Adjacent translations, rotations, and mirrors are composed
in construction order using OCCT `gp_Trsf::PreMultiply`, followed by one copying
transform and validity check. It also applies to placements of reused geometry.
Every transform argument is checked. Failure replays the original steps, keeping
their first error and index. Empty shapes and shapes/transforms outside the
conservative coordinate range use sequential evaluation, preventing extreme
cancelling translations from concealing an invalid intermediate shape. The
helper is internal; public OCEx transform functions keep their behavior.

**Incremental pure prefixes.** An application-supervised cache remembers expensive
pure recipe prefixes across evaluations, including evaluations in different
processes. Prefix keys hash the AST in order and fingerprint the relevant Elixir
implementation modules. Changed operations invalidate their suffix. Callbacks,
file-backed geometry, retained results, and unknown operations stop eligibility.
The longest available checkpoint is restored, and remaining groups retain their
original operation indices. Batch boundaries limit checkpoint granularity;
editing within a batch rebuilds that batch.

The cache stores BREP binaries, never native shape references or caller state.
Restoration creates an independent validated resource. Limits are 128 entries,
32 MiB of keys and serialized geometry, 4 MiB per snapshot, and two minutes of
idle lifetime, with least-recently-used eviction. Only groups taking at least
2 ms are snapshotted, and only the last 32 pure checkpoints per recipe are
eligible. Cheap primitive recipes bypass fingerprinting and cache calls.
Unavailable, expired, evicted, or unreadable snapshots fall back to normal
evaluation. No failures are cached. The existing per-call native reuse remains.

## Measurements

Same macOS arm64 host and OCCT 7.9.3 build as the preceding report. Warm VMs;
startup, export, and external verification are outside the evaluation timer.
The original evaluator baseline has seven samples; the final short workloads
have eleven. Medians in milliseconds:

| Workload | Before | Fusion, cache disabled | Automatic warm cache |
| --- | ---: | ---: | ---: |
| Rounded part with 24 transforms | 26.736 | 7.008 | 4.018 |
| Repeat 32-cut body | 39.341 | 40.091 | 8.058 |
| Change final hole after 32 cuts | 46.723 | 48.165 | 16.686 |
| Change box width before filleting | 5.604 | 5.821 | 6.091 |
| Small box with changed width | 0.423 | 0.425 | 0.403 |

Changing the primitive invalidates the whole prefix; the cache cannot save that
work and snapshot population has a cost. These measurements deliberately include
misses as well as hits. Timing thresholds are not regression tests.

Full-model medians, seven samples each:

| Model | Previous evaluator | New cold cache | New warm cache |
| --- | ---: | ---: | ---: |
| Tray | 1.836 s | 1.930 s | 1.464 s |
| Clip | 206 ms | 225 ms | 22.5 ms |

Cold-cache runs clear snapshots before each timed evaluation and include snapshot
population. Warm runs reuse the unchanged recipe. The tray contains ineligible
stages, so it still rebuilds substantial geometry. A warm snapshot result must
not be presented as the cost of constructing new geometry. See
`results/evaluator-*.csv` and `results/incremental-models-*.csv` for raw samples.
The preceding build123d comparison remains a comparison of rebuilds, not cache
hits; its Python timings have not been reclassified or compared to these hits.

Reference: [OCCT transform composition](https://dev.opencascade.org/doc/refman/html/classgp___trsf.html).

## Reproduction and verification

```sh
OCEX_PATH=../ocex mix run benchmarks/evaluator.exs --samples=11 --output=/tmp/evaluator.csv
OCEX_PATH=../ocex mix run benchmarks/evaluator.exs --no-cache --samples=11 --output=/tmp/fusion.csv
OCEX_PATH=../ocex mix run benchmarks/modeling.exs --cold-cache --variants=baseline --samples=7 --output=/tmp/cold.csv
OCEX_PATH=../ocex mix run benchmarks/modeling.exs --variants=baseline --samples=7 --output=/tmp/warm.csv
```

Regression tests cover noncommuting transforms and mirrors, input immutability,
invalid intermediate operations, snapshot revision stability across processes,
edited suffixes and original error indices, observable callbacks, cache limits,
expiry, and unavailable/corrupt snapshot fallback. Both final full models match
previous exports in precise volume and bounds, and both directional Boolean
differences have zero volume.

Validation: 328 Smith tests and four model-reference tests; 194 OCEx tests in
both normal and sanitizer builds; stress with 100 transform chains and 30,000
malformed calls, returning native resource counts to baseline; 34 focused tests
against older OCEx; and the isolated archive-installed consumer check all passed.
Both repositories also passed `make check docs`.
