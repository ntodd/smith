# Releasing OCEx and Smith

Release **OCEx first, then Smith**. Each is a separate Git repository and Hex
package. For 0.4.0, OCEx is already published: start at the Smith section.
Do not rebuild or move the published OCEx tag.

## Before either release

Install the native prerequisites (OCCT 7.9.3, FreeType, HarfBuzz and pkg-config)
and authenticate once with `mix hex.user auth`.

Update each project's `mix.exs` version and ExDoc source tag, plus its changelog.
In Smith, also update the OCEx dependency requirement and the Smith dependency
strings in README, guides, examples and Livebook setup cells. Preserve notebook
model cells. Smoke scripts read versions automatically from `mix.exs` and
`mix.lock`; they no longer need a separate version bump.

## 1. OCEx — skip if already published

Run in the OCEx repository:

```sh
mix deps.get
make check docs package package-smoke
```

Review the generated docs and package file list, commit the release changes,
push, and wait for CI to pass. Then tag that commit and publish:

```sh
git tag -a v0.4.0 -m "OCEx 0.4.0"
git push origin v0.4.0
mix hex.publish --dry-run
mix hex.publish
```

The dry run publishes nothing; the final command publishes the package and docs.
Verify the public package using [OCEx's checklist](https://github.com/ntodd/ocex/blob/main/docs/releasing.md)
before continuing.

## 2. Smith — resolve the published OCEx and run one gate

Run in the Smith repository:

```sh
unset OCEX_PATH OCEX_ARCHIVE
mix deps.update ocex
make release-check
```

`release-check` rejects local OCEx overrides and uses a fresh temporary install
cache, then runs formatting, compilation,
tests, model acceptance checks, executable docs, notebooks, package build and an
isolated archive installation. The smoke test fetches the locked OCEx version
from Hex and checks geometry, SVG holes and extrusion, text, STEP, drawings and
printable exports without Kino. CI also uses public OCEx by default.

Review `git diff`, the changelog and `doc/index.html`. Commit all release changes,
including `mix.lock`, push, and wait for CI to pass. Only then tag and publish:

```sh
git tag -a v0.4.0 -m "Smith 0.4.0"
git push origin v0.4.0
mix hex.publish --dry-run
mix hex.publish
```

If the tag already exists, check that it points at the verified release commit.
An unpublished tag can be corrected deliberately; **never move a tag after its
package has been published**. Code changes after publication need a new version.
For future releases, substitute the new version in these commands.

## 3. Verify Smith from public Hex

After publishing, run this from the Smith repository. It installs the exact
release into fresh caches outside the checkout:

```sh
release_check=$(mktemp -d)
cp scripts/package-smoke.exs "$release_check/model.exs"
(
  cd "$release_check"
  env -u OCEX_PATH -u OCEX_ARCHIVE SMITH_VERSION=0.4.0 \
    HEX_HOME="$release_check/hex" MIX_INSTALL_DIR="$release_check/install" \
    elixir model.exs
)
```

Open an unmodified public Livebook to verify installation with Kino. Inspect
[Smith 0.4.0 HexDocs](https://hexdocs.pm/smith/0.4.0/), including interactive
previews, SVG sizing, navigation and source links. Keep the native toolkit
installed on consumer machines; the packages do not ship precompiled NIFs.

## Documentation-only corrections

To update HexDocs without replacing the package, review the generated docs, then:

```sh
mix hex.publish docs --dry-run
mix hex.publish docs
```

This does not update installed code or bundled notebooks. Those need a new release.
