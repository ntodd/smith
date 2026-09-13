defmodule Smith.ExtrusionTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  test "sketch symmetric and tapered extrusion composes with finishing and retains previous recipe" do
    sketch = Sketch.rectangle(20, 16)
    recipe = Smith.extrude(sketch, 5, both: true, taper: 3)
    assert {:ok, result} = Smith.evaluate(recipe)
    slope = :math.tan(3 * :math.pi() / 180)
    expected = 2 * (320 * 5 - 36 * slope * 25 + 4 * slope * slope * 125 / 3)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, expected, 1.0e-5

    assert {:ok, finished} =
             Smith.evaluate(recipe |> Smith.hole(on: :top, diameter: 2, through: :all))

    assert {:ok, drilled} = OCEx.volume(finished.shape)
    assert_in_delta volume - drilled, 10 * :math.pi(), 1.0e-5
    assert {:ok, _} = Smith.evaluate(sketch)
  end

  test "sketch default options preserve primitive lowering and custom plane normals" do
    for sketch <- [Sketch.rectangle(4, 6), Sketch.circle(3)] do
      assert {:ok, a} = Smith.evaluate(Smith.extrude(sketch, -3))
      assert {:ok, b} = Smith.evaluate(Smith.extrude(sketch, -3, both: false, taper: 0))
      assert a.revision == b.revision
    end

    assert {:ok, part} =
             Sketch.rectangle(4, 6, on: Plane.yz(x: 10))
             |> Smith.extrude(-3, both: true)
             |> Smith.evaluate()

    assert {:ok, {{7.0, -2.0, -3.0}, {13.0, 2.0, 3.0}}} = OCEx.bounds(part.shape)
  end

  test "face recipes use world vector extrusion options" do
    recipe =
      Smith.box(20, 16, 2) |> Smith.section(Plane.xy(z: 1)) |> Smith.extrude({0, 0, 4}, taper: 2)

    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, [_]} = OCEx.solids(result.shape)
  end

  test "until uses sketch normals by default and permits an explicit direction" do
    target = Plane.new(origin: {0, 0, 4}, normal: {-0.5, 0, 1}, x_direction: {1, 0, 0.5})
    sketch = Sketch.rectangle(10, 6, align: {:min, :min})
    assert {:ok, result} = sketch |> Smith.extrude_until(target) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 390, 1.0e-6

    assert {:ok, result} =
             sketch
             |> Smith.extrude_until(Plane.xy(z: -3), direction: {0, 0, -1})
             |> Smith.evaluate()

    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 180, 1.0e-6

    assert {:ok, _} =
             Smith.box(10, 6, 1)
             |> Smith.section(:xy)
             |> Smith.extrude_until(target, direction: {0, 0, 1})
             |> Smith.evaluate()
  end

  test "invalid options and targets preserve recipe operation and step" do
    sketch = Sketch.rectangle(4, 6)

    assert {:error, %Smith.Error{operation: :sketch_extrude, step: 1, reason: :invalid_options}} =
             Smith.evaluate(Smith.extrude(sketch, 3, both: :yes))

    assert {:error, %Smith.Error{operation: :sketch_extrude, reason: :invalid_extrusion}} =
             Smith.evaluate(Smith.extrude(sketch, 0, taper: 2))

    assert {:error, %Smith.Error{operation: :sketch_extrude_until, reason: :target_not_ahead}} =
             Smith.evaluate(Smith.extrude_until(sketch, :xy))

    assert {:error, %Smith.Error{reason: :invalid_options}} =
             Smith.evaluate(Smith.extrude_until(sketch, Plane.xy(z: 3), both: true))

    assert {:error, %Smith.Error{operation: :extrude_until, step: 3, reason: :invalid_options}} =
             Smith.box(4, 6, 1)
             |> Smith.section(:xy)
             |> Smith.extrude_until(Plane.xy(z: 3))
             |> Smith.evaluate()
  end

  test "taper handles tangent rounded boundaries and returns printable solid meshes" do
    for sketch <- [Sketch.rounded_rectangle(20, 16, 3), Sketch.slot(20, 8)] do
      assert {:ok, result} = sketch |> Smith.extrude(4, taper: 3, both: true) |> Smith.evaluate()
      assert {:ok, [_]} = OCEx.solids(result.shape)
      assert {:ok, mesh} = OCEx.mesh(result.shape, 0.03, 0.1)
      assert mesh.triangles != []
      assert {:ok, volume} = OCEx.volume(result.shape)
      assert volume > 0
    end
  end

  test "spline profiles keep straight extrusion but reject unsupported tapered surfaces" do
    sketch =
      Sketch.profile([
        Sketch.spline([{0, 0}, {2, 2}, {4, 0}]),
        Sketch.line({4, 0}, {0, 0})
      ])

    assert {:ok, _} = sketch |> Smith.extrude(2) |> Smith.evaluate()

    assert {:error, %Smith.Error{reason: :unsupported_draft_surface}} =
             sketch |> Smith.extrude(2, taper: 3) |> Smith.evaluate()
  end
end
