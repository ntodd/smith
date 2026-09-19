defmodule Smith.AutomaticEvaluationTest do
  use ExUnit.Case, async: true

  test "ordinary boolean runs match separate evaluations with overlapping and disjoint tools" do
    base = Smith.box(10, 10, 10)
    tools = for x <- [5, 8, 25], do: Smith.box(10, 10, 10) |> Smith.translate({x, 0, 0})

    for operation <- [:cut, :fuse] do
      assert {:ok, together} = apply(Smith, operation, [base, tools]) |> Smith.evaluate()

      separate =
        Enum.reduce(tools, base, fn tool, body ->
          {:ok, result} = apply(Smith, operation, [body, tool]) |> Smith.evaluate()
          Smith.from_result(result)
        end)

      assert {:ok, separate} = Smith.evaluate(separate)

      for {a, b} <- [{together.shape, separate.shape}, {separate.shape, together.shape}] do
        assert {:ok, delta} = OCEx.cut(a, b)
        assert {:ok, volume} = OCEx.volume(delta)
        assert_in_delta volume, 0, 1.0e-7
      end
    end
  end

  test "invalid tools retain the original step and prevent later callbacks" do
    parent = self()

    observed =
      Smith.box(2, 2, 2)
      |> Smith.fillet(
        radius: 0.1,
        edges: fn _ ->
          send(parent, :unexpected_callback)
          true
        end
      )

    assert {:error,
            %Smith.Error{
              step: 3,
              operation: :cut,
              reason: %Smith.Error{step: 1, operation: :cylinder}
            }} =
             Smith.box(10, 10, 10)
             |> Smith.cut([Smith.box(1, 1, 1), Smith.cylinder(-1, 2), observed])
             |> Smith.evaluate()

    refute_received :unexpected_callback
  end

  test "tool selectors execute once and observe their own current topology" do
    parent = self()

    observed =
      Smith.box(2, 2, 2)
      |> Smith.fillet(
        radius: 0.1,
        edges: fn _ ->
          send(parent, :edge_observed)
          true
        end
      )

    assert {:ok, _} =
             Smith.box(10, 10, 10)
             |> Smith.cut([Smith.box(1, 1, 1), observed, Smith.box(1, 1, 1)])
             |> Smith.evaluate()

    for _ <- 1..12, do: assert_received(:edge_observed)
    refute_received :edge_observed
  end

  test "selectors and transformations separate runs and preserve step numbers" do
    assert {:error, %Smith.Error{step: 4, operation: :fillet, reason: :selection_count_mismatch}} =
             Smith.box(10, 10, 10)
             |> Smith.cut([Smith.box(1, 1, 1), Smith.box(2, 2, 2)])
             |> Smith.fillet(edges: :all, count: 1, radius: 0.1)
             |> Smith.fuse(Smith.box(2, 2, 2))
             |> Smith.evaluate()
  end

  test "native batch failure recovers the original failing boolean step" do
    edge = Smith.line({0, 0, 0}, {2, 0, 0})
    source = Smith.box(10, 10, 10)

    assert {:error, %Smith.Error{step: 2, operation: :fuse, reason: :operation_failed}} =
             expected =
             source |> Smith.fuse(edge) |> Smith.evaluate()

    assert source |> Smith.fuse([edge, edge, edge]) |> Smith.evaluate() == expected
  end
end
