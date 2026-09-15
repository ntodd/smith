defmodule Smith.FromResultTest do
  use ExUnit.Case, async: true
  alias Smith.{Assembly, Plane}

  test "branches reuse evaluated geometry without repeating source callbacks" do
    owner = self()

    recipe =
      Smith.box(10, 8, 6)
      |> Smith.fillet(
        edges: fn edge ->
          send(owner, :selected)
          edge.type == :line
        end,
        radius: 0.5
      )

    assert {:ok, result} = Smith.evaluate(recipe)
    assert_received :selected
    drain()
    snapshot = Smith.from_result(result)
    assert {:ok, unchanged} = Smith.evaluate(snapshot)
    assert unchanged.revision == result.revision

    for side <- [:positive, :negative] do
      assert {:ok, half} = snapshot |> Smith.split(Plane.xy(z: 3), keep: side) |> Smith.evaluate()
      assert {:ok, volume} = OCEx.volume(half.shape)
      assert {:ok, whole} = OCEx.volume(result.shape)
      assert_in_delta volume, whole / 2, 1.0e-6
    end

    assert {:ok, assembly} =
             Assembly.new(:pair)
             |> Assembly.part(:left, snapshot)
             |> Assembly.part(:right, Smith.translate(snapshot, {20, 0, 0}))
             |> Smith.evaluate()

    assert length(assembly.entries) == 2
    refute_received :selected
    assert {:ok, original_brep} = OCEx.to_brep(result.shape)
    assert Base.encode16(:crypto.hash(:sha256, original_brep), case: :lower) == result.revision
  end

  test "snapshots preserve geometry types and reject a mismatched revision" do
    for recipe <- [Smith.Sketch.circle(2), Smith.bezier([{0, 0, 0}, {1, 2, 0}, {2, 0, 0}])] do
      assert {:ok, result} = Smith.evaluate(recipe)
      assert {:ok, copy} = result |> Smith.from_result() |> Smith.evaluate()
      assert copy.revision == result.revision

      assert {:error, %Smith.Error{step: 1, operation: :from_result, reason: :revision_mismatch}} =
               %{result | revision: "incorrect"} |> Smith.from_result() |> Smith.evaluate()
    end
  end

  defp drain do
    receive do
      :selected -> drain()
    after
      0 -> :ok
    end
  end
end
