# Releasing Smith 0.2

This repository publishes `smith` version `0.2.0` from tag `v0.2.0`.
Publish and verify OCEx 0.2 first. Smith's package depends on OCEx from Hex;
a path override is only for development.

## Prepare the source

1. Review the changelog, examples, and package file list. Exclude private projects
   and local notebook dependency experiments.
2. Before OCEx is published, build its archive in its own checkout, then run:

```sh
export OCEX_PATH=/absolute/path/to/ocex
mix deps.get
make check docs notebooks package
OCEX_ARCHIVE="$OCEX_PATH/ocex-0.2.0.tar" make package-smoke
```

`make package` removes the path override when building package metadata. The smoke
check installs both archives through a signed local registry in an isolated
consumer. CI uses the pinned OCEx release commit for the same check.

3. Inspect `doc/index.html`, its interactive previews, and the archive contents.
   Push the release commit and wait for the macOS/Linux CI matrix to pass.
4. Create the annotated tag at that verified commit, unless it already exists:

```sh
git tag -a v0.2.0 -m "Smith 0.2.0"
git push origin v0.2.0
```

The version, ExDoc source tag, changelog, smoke-test dependency, and public Livebook
setup must agree. Do not move a published release tag.

## Publish after OCEx

Run from the tagged checkout after OCEx 0.2 is available on Hex. Authenticate with
`mix hex.user auth` if needed. Clear the local override and resolve the public
dependency before generating the publication artifacts:

```sh
unset OCEX_PATH
mix deps.get
make check docs
mix hex.publish --dry-run
mix hex.publish
```

`mix deps.get` records the published OCEx checksum in the local `mix.lock`; the
lockfile is not part of the Hex package. The dry run does not publish. Review the
package summary before confirming the final command, which includes ExDoc.

To run the hosted matrix against public OCEx instead of the staged checkout:

```sh
gh workflow run ci.yml --ref main -f published_ocex=true
```

## Verify the public package

Run this from the repository after Smith is published. The consumer uses fresh
caches and public Hex, with no local dependency override:

```sh
release_check=$(mktemp -d)
cp scripts/package-smoke.exs "$release_check/model.exs"
(
  cd "$release_check"
  env -u OCEX_PATH HEX_HOME="$release_check/hex" \
    MIX_INSTALL_DIR="$release_check/install" elixir model.exs
)
```

The script checks native geometry, inspection, headless rendering, drawings,
STEP round trips, and printable exports without Kino. Keep the native toolkit
installed. Open an unmodified public Livebook to check installation with Kino,
and inspect [Smith 0.2 HexDocs](https://hexdocs.pm/smith/0.2.0/), including previews,
SVG sizing, guide navigation, and source links.

## Release limits

The phone Livebook is a modeling study with a documented edge-roll defect; it is
not a validated case-fit reference. Inspection checks test the conditions supplied
by the caller, not every possible design or manufacturing requirement.

Native builds require OCCT 7.9.3. Precompiled NIFs, Windows, hot upgrades, and hard
cancellation are outside this release. See [errors and limits](../guides/errors-and-limits.md).
