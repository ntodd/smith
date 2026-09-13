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
publication checks. Smith's hosted CI deliberately resolves OCEx from Hex and
therefore requires the first OCEx publication before it can pass.

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
OCEX_ARCHIVE=/absolute/path/to/ocex-0.1.0.tar make package-smoke
```

Without `OCEX_ARCHIVE`, the check fetches OCEx 0.1.0 from Hex. The consumer runs
outside the checkout with fresh caches and installs both packages from archives;
it does not use a path dependency. It checks native geometry, STEP exchange,
serialized STL topology, 3MF contents, and Kino's optional dependency behavior.

## Interactive documentation previews

`mix docs` evaluates marked examples and writes their meshes to the ignored
`.doc-preview-assets/` directory. ExDoc includes those meshes and the shared Kino
renderer in its output. Serve `doc/` over HTTP to try the previews locally; browser
module loading does not work from a `file://` URL.

To add a preview, place this after a guide code block that defines `part`:

```html
<div class="smith-doc-preview" data-preview="unique-name" data-model="part" data-label="Part">
<p>Interactive 3D preview available in HexDocs.</p>
</div>
```

The name must be unique across the README and guides. The model attribute names
a variable from the preceding Elixir blocks: a recipe, evaluated result, or
successful result tuple. The builder evaluates those blocks in document order,
skipping `Mix.install` because Mix already supplies the dependencies. Temporary
exports are removed after the build. A failed example stops documentation generation.

Preview frames load on demand. They use the same JavaScript as Livebook and
contain a mesh snapshot, so editing and reevaluating a design still requires
Elixir. The fallback text or image remains visible in Markdown and without JavaScript.
