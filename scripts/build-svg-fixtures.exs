# Regenerate the MIT-licensed filled-outline counterpart from the original
# stroked asset. Explicit developer action; not part of every build.
alias Smith.SVG
root = Path.expand("../priv/svg", __DIR__)
{:ok, asset} = SVG.load(Path.join(root, "volleyball.svg"))
{:ok, layout} = SVG.layout(SVG.new(asset, width: 18, align: {:center, :center}))
{:ok, svg} = SVG.outline_svg(layout, tolerance: 0.001)
File.write!(Path.join(root, "volleyball-outlined.svg"), svg <> "\n")
