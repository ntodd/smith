# Developing Smith

Smith is an independent repository at [ntodd/smith](https://github.com/ntodd/smith).
OCEx is a versioned Hex dependency. No parent repository or sibling checkout is required.

```sh
mix deps.get
sh deps/ocex/scripts/install-occt.sh
make check docs notebooks
make package package-smoke
```

The toolkit installer is needed once per supported OCCT installation. See
[OCEx installation](https://hexdocs.pm/ocex/installation.html) for prerequisites.

Before OCEx is published, or while developing both libraries, opt into a local checkout:

```sh
export OCEX_PATH=/absolute/path/to/ocex
mix deps.get
make check docs
make models
```

This variable is an explicit development option, not an automatic sibling lookup.
The standalone model scripts honor it too. Unset it before public dependency or
publication checks. For the 0.3 release, hosted CI builds the OCEx `v0.3.0` tag
and tests the two package archives together. After OCEx 0.3 is published, run the
workflow with `published_ocex=true` to test Smith against public Hex without a
checkout override.

`make check` runs formatting, warnings-as-errors compilation, behavioral tests,
doctests, and public model acceptance tests. `make docs` executes README/guide code
and generates ExDoc with warnings treated as errors. `make notebooks` evaluates model cells using local dependencies;
notebook setup is exercised separately when checking installation.

Public clip and plant stand sources and frozen-reference tests live in [models](../models/README.md).
Run `make view` to export both and reload the shared CAD viewer. The viewer requires
Node 22+ and a service at `http://127.0.0.1:3939/viewer`; modeling and Livebook do not.

## Test an unpublished OCEx dependency

Build OCEx's archive in its own repository, then pass the archive explicitly:

```sh
make package
OCEX_ARCHIVE=/absolute/path/to/ocex-0.3.0.tar make package-smoke
```

Without `OCEX_ARCHIVE`, the check fetches OCEx 0.3.0 from Hex. The consumer runs
outside the checkout with fresh caches and installs both packages from archives;
it does not use a path dependency. It checks native geometry, STEP exchange,
serialized STL topology, 3MF contents, and Kino's optional dependency behavior.

## Interactive documentation previews

`mix docs` evaluates marked examples and writes browser snapshots to the ignored
`.doc-preview-assets/` directory. ExDoc includes those snapshots and the shared Kino
renderer in its output. Serve `doc/` over HTTP to try the previews locally; browser
module loading does not work from a `file://` URL.

To add a preview, place this after a guide code block that defines `part`:

```html
<div class="smith-doc-preview" data-preview="unique-name" data-model="part" data-label="Part">
<p>Interactive 3D preview available in HexDocs.</p>
</div>
```

Add a preview after each example that constructs, changes, inspects, or exports
geometry. When an example produces several variants, show each one. Setup code,
numeric coordinate queries, and deliberate error examples need no preview.

Names must be unique across the README, guides, and API docs. The model attribute
names a variable from the preceding code: a recipe, evaluated result, successful
result tuple, native shape, selection list, mesh, drawing, or SVG string.
The builder evaluates Elixir blocks in document order, skipping `Mix.install`
because Mix already supplies dependencies. In API docstrings, place the same marker
after the indented IEx example. Each docstring has its own evaluation scope;
ExUnit still checks its expected outputs as doctests.

Surfaces use the shared Kino mesh payload. Wire-only results use sampled curves.
Drawings show the SVG produced by `Smith.Drawing`, including hidden-line styling.
For print-placement examples, read the exported STL back and preview that mesh.
Temporary exports are removed after the build; removed examples lose their stale
assets. Failed examples and empty geometric previews stop documentation generation.

Preview frames load on demand. They use the same JavaScript as Livebook and
contain a geometry snapshot, so editing and reevaluating a design still requires
Elixir. The fallback text or image remains visible in Markdown and without JavaScript.
