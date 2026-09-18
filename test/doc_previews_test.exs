defmodule Smith.DocPreviewsTest do
  use ExUnit.Case, async: false
  @moduletag :tmp_dir

  # This aggregate integration test builds every documentation example, including
  # SVG stroke unions and verified exports. Hosted runners need more than two
  # minutes for that work; retain all mesh and geometry assertions below.
  @tag timeout: 600_000
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

    root = Path.expand("..", __DIR__)

    sources = [
      Path.join(root, "README.md")
      | Path.wildcard(Path.join(root, "{guides,lib,examples}/**/*.{md,ex,livemd}"))
    ]

    names =
      for source <- sources,
          [_, name] <- Regex.scan(~r/data-preview="([a-z0-9-]+)"/, File.read!(source)),
          do: name

    assert length(names) == length(Enum.uniq(names))
    assert Enum.sort(File.ls!(output)) == Enum.sort(Enum.map(names, &(&1 <> ".json")))

    for name <- names do
      preview = output |> Path.join(name <> ".json") |> File.read!() |> JSON.decode!()
      assert preview["label"] != ""
      assert preview["revision"] =~ ~r/^[a-f0-9]{64}$/

      if preview["svg"] do
        assert String.starts_with?(preview["svg"], "<svg")
        assert preview["svg"] =~ "viewBox="
      else
        vertices = preview["vertices"]
        vertex_count = length(vertices)
        assert preview["triangles"] != [] or preview["lines"] != []

        for point <- vertices ++ Enum.flat_map(preview["lines"], & &1),
            do:
              assert(match?([x, y, z] when is_number(x) and is_number(y) and is_number(z), point))

        for triangle <- preview["triangles"] do
          assert length(triangle) == 3
          assert Enum.all?(triangle, &(is_integer(&1) and &1 >= 0 and &1 < vertex_count))
        end
      end
    end

    curve =
      output |> Path.join("projection-4-curves-result.json") |> File.read!() |> JSON.decode!()

    assert curve["triangles"] == []
    assert length(curve["lines"]) == 2

    length =
      Enum.sum(
        for line <- curve["lines"], [a, b] <- Enum.chunk_every(line, 2, 1, :discard) do
          Enum.zip_with(a, b, fn x, y -> (x - y) * (x - y) end) |> Enum.sum() |> :math.sqrt()
        end
      )

    assert_in_delta length, 20 * :math.asin(3 / 5), 0.03

    print = output |> Path.join("exporting-1-print-model.json") |> File.read!() |> JSON.decode!()
    assert Enum.min(Enum.map(print["vertices"], &Enum.at(&1, 2))) == 0.0
    assert Enum.max(Enum.map(print["vertices"], &Enum.at(&1, 2))) == 10.0

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
