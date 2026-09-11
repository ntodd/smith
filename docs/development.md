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

`make check` runs 91 behavioral tests, 26 doctests, and four public model acceptance
tests. `make docs` executes README/guide code and generates ExDoc with warnings
treated as errors. `make notebooks` evaluates model cells using local dependencies;
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
