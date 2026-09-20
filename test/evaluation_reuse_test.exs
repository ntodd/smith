defmodule Smith.EvaluationReuseTest do
  use ExUnit.Case, async: true

  test "repeated rounded geometry is unchanged under different placements" do
    source = Smith.box(4, 3, 2) |> Smith.fillet(edges: :all, radius: 0.2)
    {:ok, original} = Smith.evaluate(source)
    {:ok, expected} = OCEx.volume(original.shape)
    {:ok, snapshot} = OCEx.to_brep(original.shape)

    parts =
      for i <- 0..7,
          do: source |> Smith.rotate({0, 0, 1}, i * 15) |> Smith.translate({i * 10, 0, 0})

    assert {:ok, result} = parts |> Smith.compound() |> Smith.evaluate()
    assert {:ok, solids} = OCEx.solids(result.shape)
    assert length(solids) == 8
    assert {:ok, actual} = OCEx.volume(result.shape)
    assert_in_delta actual, 8 * expected, 1.0e-7
    assert OCEx.to_brep(original.shape) == {:ok, snapshot}
  end

  test "callbacks are never reused and nested evaluation remains independent" do
    parent = self()

    source =
      Smith.box(4, 3, 2)
      |> Smith.fillet(
        radius: 0.2,
        edges: fn _ ->
          send(parent, :visited)
          assert {:ok, nested} = Smith.box(1, 1, 1) |> Smith.evaluate()
          assert {:ok, volume} = OCEx.volume(nested.shape)
          assert_in_delta volume, 1, 1.0e-7
          true
        end
      )

    recipe = Smith.compound(for i <- 0..2, do: Smith.translate(source, {i * 10, 0, 0}))

    for _ <- 1..2 do
      assert {:ok, _} = Smith.evaluate(recipe)
      for _ <- 1..36, do: assert_received(:visited)
      refute_received :visited
    end
  end

  test "placement failures retain their original nested operation index" do
    source = Smith.box(4, 3, 2) |> Smith.fillet(edges: :all, radius: 0.2)

    assert {:error,
            %Smith.Error{
              operation: :compound,
              step: 1,
              reason: %Smith.Error{operation: :rotate, step: 3}
            }} =
             Smith.compound([source, source |> Smith.rotate({0, 0, 0}, 90)]) |> Smith.evaluate()
  end

  test "failed evaluation releases its private scope without touching caller state" do
    Process.put(:caller_marker, :keep)
    before = Process.get() |> Map.new()

    source =
      Smith.box(4, 3, 2) |> Smith.fillet(radius: 0.2, edges: fn _ -> raise "callback failure" end)

    assert_raise RuntimeError, "callback failure", fn ->
      Smith.compound([source, source]) |> Smith.evaluate()
    end

    assert Process.get() |> Map.new() == before
    assert {:ok, _} = Smith.compound([Smith.box(1, 1, 1), Smith.box(1, 1, 1)]) |> Smith.evaluate()
    assert Process.get() |> Map.new() == before
  end
end
