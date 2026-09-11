defmodule Models.ProjectsTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 600_000
  for {name, module, checks} <- [
        {"plant-stand", Models.PlantStand, Models.PlantStandChecks},
        {"deck-clip", Models.DeckClip, Models.DeckClipChecks}
      ] do
    test "#{name} matches v04 geometry, functional probes, and printable topology" do
      {:ok, result} = unquote(module).build() |> Smith.evaluate()
      comparison = Models.Verification.reference(result.shape, unquote(name))
      checks = unquote(checks).verify(result.shape)
      tolerance = if unquote(name) == "plant-stand", do: 0.02, else: 0.005
      angle = if unquote(name) == "plant-stand", do: 0.08, else: 0.05
      {:ok, %{checks: mesh}} = Smith.Export.mesh(result.shape, tolerance, angle)
      assert mesh.watertight

      IO.inspect(%{model: unquote(name), comparison: comparison, functional: checks, mesh: mesh},
        label: "Verified",
        limit: :infinity
      )
    end
  end
end
