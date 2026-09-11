# Project conventions

- Keep public operations immutable and use documented tagged errors for modeling failures.
- Add behavioral tests before changing an exposed operation. Use analytic geometry and meaningful invariants.
- Run `make check docs` after changes. Do not weaken geometric checks to make a model pass.
- This repository is intended for public release. Keep private consumer projects and their assets, examples, and documentation outside the checkout and Git history.
- Native operations belong in OCEx. Recipe, sketch, selector, assembly, and export semantics belong in Smith.
- OCEx is a versioned Hex dependency; use `OCEX_PATH` only as an explicit development override. Never publish with it set.
- Preserve user edits to notebooks. Do not stage a local dependency experiment into a public example.
- After making or verifying model changes, run `make models` and reload the current exports with `node scripts/view.mjs`. Inspect the fresh screenshot.
- Viewer scripts must read the active manifest and remain tied to its geometry revision and export ID.
