.PHONY: check test docs notebooks package package-smoke release-check models view bench

check:
	mix format --check-formatted
	mix compile --warnings-as-errors
	mix test
	cd models && mix format --check-formatted
	elixir -r models/plant_stand.exs -r models/deck_clip.exs models/test/run.exs --no-export

test:
	mix test

bench:
	mix run benchmarks/performance.exs

docs:
	mix run scripts/check-api.exs
	mix run scripts/check-guides.exs
	mix docs --warnings-as-errors

notebooks:
	mix run scripts/check-notebooks.exs

package:
	env -u OCEX_PATH mix hex.build

package-smoke:
	sh scripts/package-smoke.sh

# Public-dependency release gate. Never silently test a sibling checkout.
release-check:
	@test -z "$${OCEX_PATH:-}" -a -z "$${OCEX_ARCHIVE:-}" || (echo "Unset OCEX_PATH and OCEX_ARCHIVE before release-check" >&2; exit 1)
	mix deps.get
	@release_install=$$(mktemp -d); \
	trap 'rm -rf "$$release_install"' EXIT HUP INT TERM; \
	MIX_INSTALL_DIR="$$release_install" $(MAKE) check docs notebooks package package-smoke

models:
	elixir models/plant_stand.exs
	elixir models/deck_clip.exs
	mix run scripts/svg-keychains.exs

view: models
	node scripts/view.mjs
