defmodule Smith.ProfileOperationsTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    result
  end

  defp volume(recipe, expected) do
    result = result(recipe)
    assert {:ok, [_]} = OCEx.solids(result.shape)
    assert {:ok, actual} = OCEx.volume(result.shape)
    assert_in_delta actual, expected, 1.0e-6
    result
  end

  test "annular sketches have inner loops and extrude in either direction without mutation" do
    original = Sketch.circle(5)
    before = result(original)
    ring = original |> Sketch.cut(Sketch.circle(3))
    face = result(ring)
    assert OCEx.shape_type(face.shape) == {:ok, :face}
    assert {:ok, [_, _]} = OCEx.wires(face.shape)
    assert {:ok, area} = OCEx.area(face.shape)
    assert_in_delta area, 16 * :math.pi(), 1.0e-8

    for height <- [4, -4] do
      body = volume(Smith.extrude(ring, height), 64 * :math.pi())
      assert {:ok, distance} = OCEx.distance_to_point(body.shape, {0, 0, height / 2})
      assert_in_delta distance, 3, 1.0e-7
    end

    assert result(original).revision == before.revision
    assert result(ring).revision == face.revision
    assert Sketch.cut(original, []) == original
  end

  test "multiple holes, repeated cuts and overlapping cutters use set subtraction" do
    cutters = [Sketch.circle(1, at: {-3, 0}), Sketch.circle(1, at: {3, 0})]
    sketch = Sketch.rectangle(12, 8) |> Sketch.cut(cutters)
    face = result(sketch)
    assert {:ok, [_, _, _]} = OCEx.wires(face.shape)
    volume(Smith.extrude(sketch, 2), (96 - 2 * :math.pi()) * 2)
    volume(sketch |> Sketch.cut(cutters) |> Smith.extrude(2), (96 - 2 * :math.pi()) * 2)

    Sketch.rectangle(12, 8)
    |> Sketch.cut([Sketch.rectangle(4, 2), Sketch.rectangle(4, 2, at: {2, 0})])
    |> Smith.extrude(2)
    |> volume((96 - 12) * 2)
  end

  test "cutouts may meet the outline and nonintersecting tools leave the area unchanged" do
    Sketch.rectangle(10, 8)
    |> Sketch.cut(Sketch.rectangle(4, 2, at: {5, 0}))
    |> Sketch.cut(Sketch.circle(1, at: {50, 0}))
    |> Smith.extrude(3)
    |> volume((80 - 4) * 3)
  end

  test "cutters inherit local coordinates when a complete sketch moves to another plane" do
    sketch =
      Sketch.rectangle(12, 8)
      |> Sketch.fillet(radius: 1)
      |> Sketch.cut(Sketch.circle(1, at: {3, 0}))

    for plane <- [Plane.yz(x: 7), Plane.new(origin: {5, 6, 7}, normal: {1, 2, 3})] do
      body =
        sketch
        |> Sketch.on(plane)
        |> Smith.extrude(4)
        |> volume((96 - (4 - :math.pi()) - :math.pi()) * 4)

      {:ok, center} = Plane.to_world(plane, {3, 0})
      {:ok, n} = Plane.normal(plane)

      assert {:ok, distance} =
               OCEx.distance_to_point(body.shape, Plane.add(center, Plane.scale(n, 2)))

      assert_in_delta distance, 1, 1.0e-7
    end
  end

  test "explicit cutter planes must be coplanar but may use different axes" do
    cutter_plane = Plane.new(origin: {3, 0, 7}, normal: {0, 0, -1}, x_direction: {0, 1, 0})

    body =
      Sketch.rectangle(12, 8, on: Plane.xy(z: 7))
      |> Sketch.cut(Sketch.circle(1, on: cutter_plane))
      |> Smith.extrude(2)
      |> volume((96 - :math.pi()) * 2)

    assert {:ok, distance} = OCEx.distance_to_point(body.shape, {3, 0, 8})
    assert_in_delta distance, 1, 1.0e-7

    for plane <- [
          Plane.xy(z: 8),
          Plane.yz(),
          Plane.new(origin: {0, 0, 7}, normal: {1.0e-7, 0, 1})
        ] do
      assert {:error, %Smith.Error{reason: :non_coplanar_sketches}} =
               Sketch.rectangle(12, 8, on: Plane.xy(z: 7))
               |> Sketch.cut(Sketch.circle(1, on: plane))
               |> Smith.evaluate()
    end
  end

  test "nested cut recipes preserve holes in the cutter" do
    cutter = Sketch.rectangle(12, 12) |> Sketch.cut(Sketch.circle(2))
    Sketch.rectangle(10, 10) |> Sketch.cut(cutter) |> Smith.extrude(3) |> volume(12 * :math.pi())
  end

  test "empty, disconnected and invalid cut profiles return tagged errors" do
    for {tool, reason} <- [
          {Sketch.rectangle(20, 20), :empty_sketch},
          {Sketch.rectangle(2, 20), :disconnected_sketch},
          {nil, :invalid_sketch},
          {Smith.cylinder(1, 2), :invalid_sketch}
        ] do
      assert {:error, %Smith.Error{operation: :sketch_extrude, reason: ^reason}} =
               Sketch.rectangle(10, 10)
               |> Sketch.cut(tool)
               |> Smith.extrude(3)
               |> Smith.evaluate()
    end
  end

  test "revolve makes full rings and partial sectors around a world axis" do
    profile = Sketch.rectangle(2, 3, align: {:min, :min}, at: {4, 0}, on: Plane.xz())
    volume(Smith.revolve(profile, {0, 0, 1}), 60 * :math.pi())
    volume(Smith.revolve(profile, {0, 0, 1}, 90), 15 * :math.pi())
    reverse = Smith.revolve(profile, {0, 0, -1}, 90) |> volume(15 * :math.pi())
    assert {:ok, {{_, low_y, _}, {_, high_y, _}}} = OCEx.bounds(reverse.shape)
    assert_in_delta low_y, -6, 1.0e-7
    assert_in_delta high_y, 0, 1.0e-7
  end

  test "revolve respects translated axes, circular profiles and cutouts" do
    Sketch.circle(1, at: {5, 0}, on: Plane.xz(y: 7))
    |> Smith.revolve({0, 0, 1}, 360, {0, 7, 0})
    |> volume(10 * :math.pi() * :math.pi())

    Sketch.rectangle(4, 6, at: {5, 0}, on: Plane.xz())
    |> Sketch.cut(Sketch.rectangle(2, 2, at: {5, 0}))
    |> Smith.revolve({0, 0, 1})
    |> Smith.translate({0, 0, 10})
    |> volume(200 * :math.pi())
  end

  test "world-coordinate face recipes also revolve" do
    Smith.polygon([{2, 0, 0}, {4, 0, 0}, {4, 0, 3}, {2, 0, 3}])
    |> Smith.revolve({0, 0, 1}, 180)
    |> volume(18 * :math.pi())
  end

  test "revolve rejects invalid axes, angles and non-face inputs during evaluation" do
    profile = Sketch.rectangle(2, 3, at: {4, 0}, on: Plane.xz())

    for {axis, angle, origin} <- [
          {{0, 0, 0}, 360, {0, 0, 0}},
          {{0, 0, 1}, 0, {0, 0, 0}},
          {{0, 0, 1}, -90, {0, 0, 0}},
          {{0, 0, 1}, 361, {0, 0, 0}},
          {:z, 90, {0, 0, 0}},
          {{0, 0, 1}, 90, nil}
        ] do
      assert {:error, %Smith.Error{operation: :revolve}} =
               Smith.revolve(profile, axis, angle, origin) |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{operation: :revolve, step: 2}} =
             Smith.box(1, 2, 3) |> Smith.revolve({0, 0, 1}) |> Smith.evaluate()
  end

  test "ruled loft connects ordered sections with the analytic frustum volume" do
    sections = [Sketch.rectangle(4, 6), Sketch.rectangle(8, 12, on: Plane.xy(z: 9))]
    before = Enum.map(sections, &result(&1).revision)
    body = Smith.loft(sections) |> volume(9 / 3 * (24 + 96 + 48))
    assert {:ok, {{lx, ly, lz}, {hx, hy, hz}}} = OCEx.bounds(body.shape)

    for {a, b} <- [{lx, -4}, {ly, -6}, {lz, 0}, {hx, 4}, {hy, 6}, {hz, 9}],
        do: assert_in_delta(a, b, 2.0e-7)

    assert Enum.map(sections, &result(&1).revision) == before
  end

  test "multi-section loft is piecewise ruled and supports displaced sections" do
    Smith.loft([
      Sketch.circle(2),
      Sketch.circle(4, on: Plane.xy(z: 3)),
      Sketch.circle(2, on: Plane.xy(z: 6))
    ])
    |> volume(56 * :math.pi())

    Smith.loft([
      Sketch.rectangle(4, 6, on: Plane.yz(x: 2)),
      Sketch.rectangle(4, 6, on: Plane.yz(origin: {7, 8, 9}))
    ])
    |> volume(120)
  end

  test "loft rejects insufficient, invalid, coincident or multiply bounded sections" do
    ring = Sketch.circle(3) |> Sketch.cut(Sketch.circle(1))

    for sections <- [
          nil,
          [],
          [Sketch.circle(2)],
          [Sketch.circle(2), nil],
          [Sketch.circle(2), Smith.box(1, 2, 3)],
          [Sketch.circle(2), Sketch.circle(2)],
          [ring, Sketch.circle(3, on: Plane.xy(z: 4))]
        ] do
      assert {:error, %Smith.Error{operation: :loft}} = Smith.loft(sections) |> Smith.evaluate()
    end
  end

  test "loft accepts an edge cutout with one boundary and preserves section shape" do
    section = Sketch.rectangle(10, 8) |> Sketch.cut(Sketch.rectangle(4, 2, at: {5, 0}))
    body = Smith.loft([section, Sketch.on(section, Plane.xy(z: 3))]) |> volume(76 * 3)
    assert {:ok, distance} = OCEx.distance_to_point(body.shape, {4, 0, 1.5})
    assert_in_delta distance, 1, 1.0e-7
  end

  test "placed cutters stay in their explicit frame and malformed cutter options are rejected" do
    cut = Sketch.rectangle(10, 8) |> Sketch.cut(Sketch.circle(1, on: Plane.xy()))

    assert {:error, %Smith.Error{reason: :non_coplanar_sketches}} =
             cut |> Sketch.on(Plane.xy(z: 3)) |> Smith.evaluate()

    for cutter <- [
          Sketch.circle(1, on: nil),
          Sketch.circle(1, typo: true),
          Sketch.circle(1, at: nil),
          Sketch.circle(-1)
        ] do
      assert {:error, %Smith.Error{}} =
               Sketch.rectangle(10, 8) |> Sketch.cut(cutter) |> Smith.evaluate()
    end
  end

  @tag :tmp_dir

  test "cut, revolved and lofted solids export verified STEP, STL and 3MF", %{tmp_dir: root} do
    recipes = [
      {"ring", Sketch.circle(5) |> Sketch.cut(Sketch.circle(3)) |> Smith.extrude(2)},
      {"revolved",
       Sketch.rectangle(2, 3, at: {4, 0}, on: Plane.xz()) |> Smith.revolve({0, 0, 1})},
      {"lofted", Smith.loft([Sketch.circle(3), Sketch.circle(2, on: Plane.xy(z: 4))])}
    ]

    for {name, recipe} <- recipes do
      assert {:ok, files} =
               Smith.export(result(recipe), root,
                 name: name,
                 on_bed: true,
                 angular_tolerance: 0.1
               )

      assert files.verification.mesh.watertight
      assert files.verification.mesh.winding_consistent
      assert files.verification.mesh.components == 1
      assert files.verification.step_relative_volume_error < 1.0e-6
      assert {:ok, _} = :zip.extract(File.read!(files.three_mf), [:memory])
    end
  end
end
