.PHONY: check test docs notebooks package package-smoke models view

check:
	mix format --check-formatted
	mix compile --warnings-as-errors
	mix test
	cd models && mix format --check-formatted
	elixir -r models/plant_stand.exs -r models/deck_clip.exs models/test/run.exs --no-export

test:
	mix test

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

models:
	elixir models/plant_stand.exs
	elixir models/deck_clip.exs

view: models
	node scripts/view.mjs
