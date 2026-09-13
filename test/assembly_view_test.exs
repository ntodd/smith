defmodule Smith.AssemblyViewTest do
  use ExUnit.Case, async: true
  alias Smith.{Assembly, Plane, Result}

  defp bounds(shape, low, high) do
    assert {:ok, {actual_low, actual_high}} = OCEx.bounds(shape)

    for {actual, expected} <- Enum.zip(Tuple.to_list(actual_low), Tuple.to_list(low)),
        do: assert_in_delta(actual, expected, 1.0e-7)

    for {actual, expected} <- Enum.zip(Tuple.to_list(actual_high), Tuple.to_list(high)),
        do: assert_in_delta(actual, expected, 1.0e-7)
  end

  test "installed view retains the evaluated shape and revision" do
    recipe =
      Assembly.new(:fixture)
      |> Assembly.part(:base, Smith.box(2, 3, 4))
      |> Assembly.part(:coupon, Smith.box(1, 1, 1), installed: false)
      |> Assembly.reference(:board, Smith.box(10, 10, 10))

    assert {:ok, assembly} = Smith.evaluate(recipe)
    assert {:ok, %Result{} = view} = Assembly.view(assembly)
    assert view.shape == assembly.shape
    assert view.revision == assembly.revision
    assert {:ok, solids} = OCEx.solids(view.shape)
    assert length(solids) == 1
  end

  test "display and exploded views use world placement and additive ancestor offsets" do
    child =
      Assembly.new(:mount)
      |> Assembly.part(:body, Smith.box(2, 3, 4),
        position: {5, 0, 0},
        display_offset: {1, 0, 0},
        exploded_offset: {0, 0, 7},
        print: [on_bed: true]
      )
      |> Assembly.reference(:board, Smith.box(100, 100, 100))

    recipe =
      Assembly.new(:fixture)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.subassembly(:spare, child,
        installed: false,
        rotation: {{0, 0, 1}, 90},
        position: {10, 20, 30},
        display_offset: {2, 0, 0},
        exploded_offset: {0, 0, 11}
      )

    assert {:ok, assembly} = Smith.evaluate(recipe)
    assert {:ok, original} = OCEx.to_brep(assembly.shape)
    assert {:ok, display} = Assembly.view(assembly, :display)
    assert {:ok, exploded} = Assembly.view(assembly, :exploded)
    bounds(display.shape, {0, 0, 0}, {13, 27, 34})
    bounds(exploded.shape, {0, 0, 0}, {13, 27, 52})
    assert {:ok, solids} = OCEx.solids(exploded.shape)
    assert length(solids) == 2
    assert {:ok, volume} = OCEx.volume(exploded.shape)
    assert_in_delta volume, 25, 1.0e-7
    assert {:ok, ^original} = OCEx.to_brep(assembly.shape)
    assert {:ok, brep} = OCEx.to_brep(exploded.shape)
    assert exploded.revision == Base.encode16(:crypto.hash(:sha256, brep), case: :lower)
  end

  test "exploded views retain resolved joint placement without reevaluating recipes" do
    recipe =
      Assembly.new(:jointed)
      |> Assembly.part(:base, Smith.box(2, 2, 2))
      |> Assembly.part(:arm, Smith.box(4, 1, 1),
        position: {100, 0, 0},
        display_offset: {0, 0, 3},
        exploded_offset: {0, 0, 5}
      )
      |> Assembly.joint(:pivot, on: :base, at: Plane.xy(z: 2))
      |> Assembly.joint(:arm_pivot, on: :arm)
      |> Assembly.connect(:arm_pivot, to: :pivot, kind: :revolute, angle: 90)

    assert {:ok, assembly} = Smith.evaluate(recipe)
    assert {:ok, view} = Assembly.view(assembly, :exploded)
    bounds(view.shape, {-1, 0, 0}, {2, 4, 11})
    assert {:ok, arm} = Assembly.fetch(assembly, :arm)
    bounds(arm.shape, {-1, 0, 2}, {0, 4, 3})
  end

  test "views reject stale geometry before constructing a preview" do
    assert {:ok, assembly} =
             Smith.evaluate(Assembly.new(:one) |> Assembly.part(:body, Smith.box(1, 1, 1)))

    for mode <- [:installed, :display, :exploded] do
      assert {:error, :revision_mismatch} = Assembly.view(%{assembly | revision: "stale"}, mode)
    end
  end

  test "unknown modes and unevaluated inputs return tagged errors" do
    assert {:ok, assembly} =
             Smith.evaluate(Assembly.new(:one) |> Assembly.part(:body, Smith.box(1, 1, 1)))

    assert {:error, :invalid_options} = Assembly.view(assembly, :print)
    assert {:error, :invalid_argument} = Assembly.view(Assembly.new(:one), :display)
  end
end
