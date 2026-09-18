# Upstream SVG compatibility fixtures

Unmodified SVGs downloaded from the official repositories. These exercise compact
numbers, compound fills and holes, many disconnected regions, and curved strokes.
Upstream licenses are included alongside the files.

| Files | Source version | License |
| --- | --- | --- |
| `lucide-bike.svg`, `lucide-volleyball.svg` | [Lucide 0.468.0](https://github.com/lucide-icons/lucide/tree/0.468.0/icons) (`bike.svg`, `volleyball.svg`) | ISC, with upstream MIT notices; see LICENSE-lucide |
| `heroicons-heart.svg`, `heroicons-cog.svg` | [Heroicons v2.2.0](https://github.com/tailwindlabs/heroicons/tree/v2.2.0/optimized/24/solid) (`heart.svg`, `cog-6-tooth.svg`) | MIT; see LICENSE-heroicons |
| `bootstrap-balloon.svg`, `bootstrap-qr.svg` | [Bootstrap Icons v1.11.3](https://github.com/twbs/icons/tree/v1.11.3/icons) (`balloon-heart.svg`, `qr-code.svg`) | MIT; see LICENSE-bootstrap |

Run `mix test test/svg_compatibility_test.exs`. Tests check actual ink width,
valid faces and solids, extrusion volume = area × depth, and the material removed
by engraving. They do not assert that arbitrary SVG features are supported.

Print-export check: the balloon, cog, heart, bicycle and volleyball also passed
STEP/STL/3MF export as 30 mm artwork engraved 1.2 mm into a 40 × 40 × 2 mm plate.
The unmodified QR icon imports correctly, but that engraving has seven edges
shared by four triangles because some pixels touch only at corners. Its print
export correctly returns `{:error, :invalid_print_mesh}`. Introduce real gaps or
bridges in that artwork before printing; successful SVG import alone does not
prove that a particular fabrication operation is printable.
