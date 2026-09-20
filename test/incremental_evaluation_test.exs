defmodule Smith.IncrementalEvaluationTest do
  use ExUnit.Case, async: false

  test "edited suffixes reuse a pure prefix and preserve geometry and error positions" do
    body =
      Smith.box(113, 80, 8)
      |> Smith.cut(
        for i <- 0..31,
            do: Smith.cylinder(2, 10, at: {5 + rem(i, 8) * 12, 5 + div(i, 8) * 20, -1})
      )

    {:ok, original} = Smith.evaluate(body)

    key =
      body.operations
      |> Smith.EvaluationPlan.compile()
      |> Smith.EvaluationPlan.checkpoints()
      |> List.last()
      |> elem(1)

    assert {^key, brep} = Smith.IncrementalCache.fetch([key])
    assert is_binary(brep)
    assert {:ok, repeated} = Task.async(fn -> Smith.evaluate(body) end) |> Task.await()
    assert repeated.revision == original.revision
    refute repeated.shape.ref == original.shape.ref

    for x <- [100, 103] do
      opts = [on: Smith.Plane.xy(), at: {x, 20}, diameter: 3, through: :all]
      {:ok, actual} = body |> Smith.hole(opts) |> Smith.evaluate()
      {:ok, expected} = original |> Smith.from_result() |> Smith.hole(opts) |> Smith.evaluate()

      for {a, b} <- [{actual.shape, expected.shape}, {expected.shape, actual.shape}] do
        {:ok, delta} = OCEx.cut(a, b)
        assert {:ok, amount} = OCEx.volume(delta)
        assert_in_delta amount, 0, 1.0e-7
      end
    end

    assert {:error, %Smith.Error{step: 34, operation: :hole, reason: :hole_misses_body}} =
             body
             |> Smith.hole(on: Smith.Plane.xy(), at: {200, 20}, diameter: 3, through: :all)
             |> Smith.evaluate()

    # An unavailable/corrupt optimization artifact must never break the recipe.
    Smith.IncrementalCache.put(key, "invalid snapshot")
    assert {:ok, _} = Smith.evaluate(body)
  end

  test "callback recipes remain observable across edits and repeated evaluations" do
    parent = self()

    source =
      Smith.box(11, 12, 13)
      |> Smith.fillet(
        radius: 0.2,
        edges: fn _ ->
          send(parent, :visited)
          true
        end
      )

    for _ <- 1..2 do
      assert {:ok, _} = Smith.evaluate(source)
      for _ <- 1..12, do: assert_received(:visited)
      refute_received :visited
    end

    assert Enum.all?(
             Smith.EvaluationPlan.checkpoints(Smith.EvaluationPlan.compile(source.operations)),
             fn
               {_, nil} -> true
               {nodes, _} -> Enum.all?(nodes, fn {{op, _}, _} -> op == :box end)
             end
           )
  end

  test "snapshot cache bounds bytes and entries, expires data, and tolerates absence" do
    {:ok, cache} =
      Smith.IncrementalCache.start_link(name: nil, max_bytes: 100, max_entries: 2, ttl: 20)

    Smith.IncrementalCache.put("a", :binary.copy("a", 40), cache)
    Smith.IncrementalCache.put("b", :binary.copy("b", 40), cache)
    assert {"a", _} = Smith.IncrementalCache.fetch(["a"], cache)
    Smith.IncrementalCache.put("c", :binary.copy("c", 40), cache)
    assert :miss = Smith.IncrementalCache.fetch(["b"], cache)
    assert {"c", _} = Smith.IncrementalCache.fetch(["c"], cache)
    Smith.IncrementalCache.put("huge", :binary.copy("x", 101), cache)
    assert :miss = Smith.IncrementalCache.fetch(["huge"], cache)
    Process.sleep(30)
    assert :miss = Smith.IncrementalCache.fetch(["a", "c"], cache)
    GenServer.stop(cache)
    assert :miss = Smith.IncrementalCache.fetch(["a"], cache)
    assert :ok = Smith.IncrementalCache.put("a", "b", cache)
  end
end
