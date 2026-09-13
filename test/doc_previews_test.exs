defmodule Smith.DocPreviewsTest do
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  test "documentation previews mesh the documented stages and assembly poses", %{tmp_dir: output} do
    script = Path.expand("../scripts/build-doc-previews.exs", __DIR__)
    Code.eval_string(File.read!(script), [output: output], file: script)

    expected = %{
      "mount" => (60 * 40 - (4 - :math.pi()) * 4 - 2 * :math.pi() * 16) * 5,
      "plate-blank" => 60 * 40 * 5,
      "plate-rounded" => (60 * 40 - (4 - :math.pi()) * 4) * 5,
      "plate-drilled" => (60 * 40 - (4 - :math.pi()) * 4 - :math.pi() * 16) * 5,
      "assembly-installed" => 48,
      "assembly-exploded" => 48
    }

    assert Enum.sort(File.ls!(output)) ==
             Enum.sort(Enum.map(Map.keys(expected), &(&1 <> ".json")))

    data =
      Map.new(expected, fn {name, volume} ->
        preview = output |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()
        assert preview["label"] != ""
        assert preview["revision"] =~ ~r/^[a-f0-9]{64}$/

        mesh = %{
          vertices: Enum.map(preview["vertices"], &List.to_tuple/1),
          triangles: Enum.map(preview["triangles"], &List.to_tuple/1)
        }

        inspected = mesh |> Smith.Mesh.weld() |> Smith.Mesh.inspect()
        assert inspected.watertight and inspected.winding_consistent
        assert_in_delta inspected.volume, volume, volume * 0.005
        {name, preview}
      end)

    installed = data["assembly-installed"]["vertices"] |> Enum.map(&Enum.at(&1, 2)) |> Enum.max()
    exploded = data["assembly-exploded"]["vertices"] |> Enum.map(&Enum.at(&1, 2)) |> Enum.max()
    assert_in_delta exploded - installed, 30, 1.0e-8
    assert data["plate-blank"]["revision"] != data["plate-drilled"]["revision"]
  end
end
