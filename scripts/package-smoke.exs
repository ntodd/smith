# This file is copied out of the repository and run against archive-installed deps.
Mix.install([{:smith, "~> 0.1.0"}])

false = Code.ensure_loaded?(Kino)
true = Code.ensure_loaded?(Smith.Kino)
{:error, :kino_not_available} = Smith.Kino.render(Smith.box(1, 2, 3))
{:ok, "7.9.3"} = OCEx.version()
model = Smith.box(60, 40, 5)
  |> Smith.fillet(edges: {:parallel, :z}, count: 4, radius: 2)
  |> Smith.hole(on: :top, diameter: 8, through: :all)
{:ok, result} = Smith.evaluate(model)
{:ok, true} = OCEx.valid?(result.shape)
{:ok, volume} = OCEx.volume(result.shape)
expected = (60 * 40 - (4 - :math.pi()) * 4 - :math.pi() * 16) * 5
true = abs(volume - expected) < 1.0e-6
{:ok, files} = Smith.export(result, "output", name: "archive-plate", on_bed: true)
mesh = files.stl |> File.read!() |> Smith.Mesh.from_stl() |> Smith.Mesh.inspect()
true = mesh.watertight and mesh.winding_consistent
{:ok, entries} = :zip.extract(String.to_charlist(files.three_mf), [:memory])
true = Enum.any?(entries, fn {name, xml} -> name == ~c"3D/3dmodel.model" and String.contains?(xml, "<triangle") end)
IO.puts("Verified isolated archive: native geometry, STEP round trip, watertight STL, and 3MF")
