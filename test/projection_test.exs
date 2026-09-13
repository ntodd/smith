defmodule Smith.ProjectionTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  test "sketch projection yields deferred boundary wires in target world coordinates" do
    source = Sketch.circle(3, on: Plane.xy(z: 8))
    target = Sketch.rectangle(20, 20)
    recipe = Smith.project(source, target, direction: {0, 0, -1})
    assert %Smith.Model{} = recipe
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, [edge]} = Smith.edges(result)
    assert {:ok, %{point: {_, _, z}}} = OCEx.edge_sample(edge, 0.5)
    assert_in_delta z, 0, 1.0e-6
    assert {:ok, length} = OCEx.length(result.shape)
    assert_in_delta length, 6 * :math.pi(), 1.0e-6
  end

  test "paths and edge recipes compose with projection and transforms" do
    target = Sketch.rectangle(20, 20)
    edge = Smith.line({-3, 0, 5}, {3, 0, 5})

    for source <- [edge, Smith.Path.new([edge])] do
      assert {:ok, result} =
               source
               |> Smith.project(target, from: {0, 0, 10})
               |> Smith.translate({0, 0, 2})
               |> Smith.evaluate()

      assert {:ok, length} = OCEx.length(result.shape)
      assert_in_delta length, 12, 1.0e-6
      assert {:ok, {{_, _, low}, {_, _, high}}} = OCEx.bounds(result.shape)
      assert_in_delta low, 2, 1.0e-6
      assert_in_delta high, 2, 1.0e-6
    end
  end

  test "model targets return all hits and callers can select a surface first" do
    source = Sketch.circle(2, on: Plane.xy(z: 8))
    target = Smith.box(20, 20, 4, align: {:center, :center, :min})
    assert {:ok, all} = Smith.evaluate(Smith.project(source, target, direction: {0, 0, -1}))
    assert {:ok, wires} = OCEx.wires(all.shape)
    assert length(wires) == 2
    top = Smith.surface(target, Smith.Selector.facing(:z))
    assert {:ok, only_top} = Smith.evaluate(Smith.project(source, top, direction: {0, 0, -1}))
    assert {:ok, [_]} = OCEx.wires(only_top.shape)
  end

  test "projection failures retain operation and target recipe context" do
    source = Smith.line({0, 0, 5}, {1, 0, 5})
    target = Sketch.rectangle(10, 10)

    assert {:error, %Smith.Error{operation: :project, step: 2, reason: :invalid_options}} =
             Smith.evaluate(Smith.project(source, target, []))

    assert {:error, %Smith.Error{operation: :project, reason: %Smith.Error{operation: :box}}} =
             Smith.evaluate(Smith.project(source, Smith.box(0, 1, 1), direction: {0, 0, 1}))
  end

  test "a closed planar projection becomes a face and extrudes without losing its geometry" do
    recipe =
      Sketch.circle(2, on: Plane.xy(z: 5))
      |> Smith.project(Sketch.rectangle(20, 20), from: {0, 0, 10})
      |> Smith.face()
      |> Smith.extrude({0, 0, 3})

    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 48 * :math.pi(), 1.0e-6
  end

  test "face conversion rejects open and multiple projected boundaries" do
    target = Sketch.rectangle(20, 20)
    open = Smith.line({-2, 0, 5}, {2, 0, 5}) |> Smith.project(target, direction: {0, 0, -1})

    assert {:error, %Smith.Error{operation: :face, reason: :open_wire}} =
             open |> Smith.face() |> Smith.evaluate()

    ring = Sketch.circle(4, on: Plane.xy(z: 5)) |> Sketch.cut(Sketch.circle(2))
    multiple = Smith.project(ring, target, direction: {0, 0, -1})

    assert {:error, %Smith.Error{operation: :face, reason: :wrong_shape_type}} =
             multiple |> Smith.face() |> Smith.evaluate()
  end
end
