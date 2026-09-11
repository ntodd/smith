defmodule Smith.SketchTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  defp volume(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    assert {:ok, volume} = OCEx.volume(result.shape)
    volume
  end

  test "principal planes have explicit right-handed local axes and offsets" do
    assert {:ok, {2.0, 3.0, 5.0}} = Plane.to_world(Plane.xy(z: 5), {2, 3})
    assert {:ok, {5.0, 2.0, 3.0}} = Plane.to_world(Plane.yz(x: 5), {2, 3})
    assert {:ok, {2.0, 5.0, 3.0}} = Plane.to_world(Plane.xz(y: 5), {2, 3})
    assert Plane.normal(Plane.xz()) == {:ok, {0.0, -1.0, 0.0}}
    plane = Plane.new(origin: {10, 20, 30}, normal: {1, 1, 1}, x_direction: {1, -1, 0})
    assert {:ok, {x, y, z}} = Plane.to_world(plane, {2, 3})
    assert_in_delta x - 10 + (y - 20) + (z - 30), 0, 1.0e-10
    assert_in_delta :math.pow(x - 10, 2) + :math.pow(y - 20, 2) + :math.pow(z - 30, 2), 13, 1.0e-9
  end

  test "rectangles center by default and alignment places their local bounds explicitly" do
    assert {:ok, centered} = Sketch.rectangle(4, 6) |> Smith.extrude(2) |> Smith.evaluate()
    assert OCEx.bounds(centered.shape) == {:ok, {{-2.0, -3.0, 0.0}, {2.0, 3.0, 2.0}}}

    assert {:ok, aligned} =
             Sketch.rectangle(4, 6, align: {:min, :max}, at: {10, 20})
             |> Smith.extrude(2)
             |> Smith.evaluate()

    assert OCEx.bounds(aligned.shape) == {:ok, {{10.0, 14.0, 0.0}, {14.0, 20.0, 2.0}}}
    assert_in_delta volume(Sketch.rectangle(4, 6) |> Smith.extrude(2)), 48, 1.0e-9
  end

  test "circle alignment and negative extrusion respect the plane normal" do
    recipe = Sketch.circle(2, align: {:min, :max}, on: Plane.yz(x: 10)) |> Smith.extrude(-5)
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, {{lx, ly, lz}, {hx, hy, hz}}} = OCEx.bounds(result.shape)

    for {actual, expected} <- [{lx, 5}, {hx, 10}, {ly, 0}, {hy, 4}, {lz, -4}, {hz, 0}],
        do: assert_in_delta(actual, expected, 1.0e-7)

    assert_in_delta volume(recipe), 20 * :math.pi(), 1.0e-7
  end

  test "a sketch can be reused on arbitrary planes without changing its original" do
    sketch = Sketch.rectangle(4, 6)

    for plane <- [
          Plane.xz(y: 8),
          Plane.new(normal: {0, 0, -1}),
          Plane.new(origin: {10, -20, 30}, normal: {1, 2, 3}, x_direction: {0, 1, 0})
        ] do
      recipe = sketch |> Sketch.on(plane) |> Smith.extrude(5)
      assert_in_delta volume(recipe), 120, 1.0e-7
      {:ok, result} = Smith.evaluate(recipe)
      {:ok, center} = OCEx.center_of_mass(result.shape)
      {:ok, origin} = Plane.to_world(plane, {0, 0})
      {:ok, normal} = Plane.normal(plane)
      {:ok, vertices} = OCEx.vertices(result.shape)

      points =
        Enum.map(vertices, fn vertex ->
          {:ok, point} = OCEx.point(vertex)
          point
        end)

      for {local_axis, low, high} <- [{{1, 0}, -2, 2}, {{0, 1}, -3, 3}] do
        {:ok, endpoint} = Plane.to_world(plane, local_axis)
        direction = for i <- 0..2, do: elem(endpoint, i) - elem(origin, i)

        projections =
          Enum.map(points, fn point ->
            Enum.with_index(direction)
            |> Enum.map(fn {component, i} -> (elem(point, i) - elem(origin, i)) * component end)
            |> Enum.sum()
          end)

        assert_in_delta Enum.min(projections), low, 1.0e-7
        assert_in_delta Enum.max(projections), high, 1.0e-7
      end

      for i <- 0..2,
          do: assert_in_delta(elem(center, i), elem(origin, i) + elem(normal, i) * 2.5, 1.0e-7)
    end

    assert {:ok, face} = Smith.evaluate(sketch)
    assert {:ok, area} = OCEx.area(face.shape)
    assert_in_delta area, 24, 1.0e-8
    assert OCEx.bounds(face.shape) == {:ok, {{-2.0, -3.0, 0.0}, {2.0, 3.0, 0.0}}}
  end

  test "polygon winding does not reverse scalar extrusion and alignment preserves polygon shape" do
    points = [{0, 0}, {4, 0}, {0, 3}]

    for polygon <- [points, Enum.reverse(points)] do
      sketch = Sketch.polygon(polygon, align: {:center, :center}, on: Plane.xy(z: 7))
      assert_in_delta volume(Smith.extrude(sketch, 2)), 12, 1.0e-8
      {:ok, result} = sketch |> Smith.extrude(2) |> Smith.evaluate()
      {:ok, {{_, _, low}, {_, _, high}}} = OCEx.bounds(result.shape)
      assert_in_delta low, 7, 1.0e-8
      assert_in_delta high, 9, 1.0e-8
    end
  end

  test "ordered local line and arc profiles extrude in their plane" do
    sketch =
      Sketch.profile(
        [
          Sketch.arc({0, 0}, 2, 0, 180),
          Sketch.line({-2, 0}, {2, 0})
        ],
        on: Plane.yz(x: 5)
      )

    assert_in_delta volume(Smith.extrude(sketch, 3)), 6 * :math.pi(), 1.0e-7

    assert {:error, _} =
             Sketch.profile([Sketch.line({0, 0}, {1, 0})]) |> Smith.extrude(2) |> Smith.evaluate()
  end

  test "sketch corner fillets have analytic rounded-rectangle area on any plane" do
    for plane <- [Plane.xy(), Plane.new(normal: {1, 2, 3}, x_direction: {1, 0, 0})] do
      recipe = Sketch.rectangle(10, 8, on: plane) |> Sketch.fillet(radius: 2) |> Smith.extrude(3)
      assert_in_delta volume(recipe), (80 - (4 - :math.pi()) * 4) * 3, 1.0e-6
    end

    for points <- [[{0, 0}, {10, 0}, {10, 8}, {0, 8}], [{0, 8}, {10, 8}, {10, 0}, {0, 0}]] do
      assert_in_delta volume(
                        Sketch.polygon(points)
                        |> Sketch.fillet(radius: 2)
                        |> Smith.extrude(3)
                      ),
                      (80 - (4 - :math.pi()) * 4) * 3,
                      1.0e-6
    end
  end

  test "convex triangle fillets use each corner angle" do
    height = 5 * :math.sqrt(3)

    recipe =
      Sketch.polygon([{0, 0}, {10, 0}, {5, height}])
      |> Sketch.fillet(radius: 1)
      |> Smith.extrude(2)

    expected = (25 * :math.sqrt(3) - (3 * :math.sqrt(3) - :math.pi())) * 2
    assert_in_delta volume(recipe), expected, 1.0e-6
  end

  @tag :tmp_dir
  test "rounded sketches and plane holes export verified printable files", %{tmp_dir: root} do
    plane = Plane.yz(x: 10)

    model =
      Sketch.rectangle(10, 8, on: plane)
      |> Sketch.fillet(radius: 1)
      |> Smith.extrude(3)
      |> Smith.hole(on: plane, at: {2, 1}, diameter: 2, through: :all)

    assert {:ok, result} = Smith.evaluate(model)

    assert {:ok, files} =
             Smith.export(result, root,
               name: "rounded",
               print_rotation: {{0, 1, 0}, -90},
               on_bed: true
             )

    assert files.verification.mesh.watertight
    assert files.verification.mesh.winding_consistent
    assert files.verification.mesh.components == 1
    assert files.verification.step_relative_volume_error < 1.0e-6
    assert {:ok, _} = :zip.extract(File.read!(files.three_mf), [:memory])
    assert_in_delta volume(model), (80 - (4 - :math.pi()) - :math.pi()) * 3, 1.0e-6
  end

  test "sketch validation returns tagged evaluation errors for unsupported or degenerate inputs" do
    invalid = [
      Sketch.rectangle(0, 2),
      Sketch.circle(-1),
      Sketch.rectangle(2, 3, typo: true),
      Sketch.circle(2, align: :bad),
      Sketch.polygon([{0, 0}, {1, 1}]),
      Sketch.polygon([{0, 0}, {2, 2}, {0, 2}, {2, 0}]),
      Sketch.rectangle(4, 6) |> Sketch.fillet(radius: 3),
      Sketch.circle(4) |> Sketch.fillet(radius: 1),
      Sketch.rectangle(4, 6) |> Sketch.fillet(nil),
      Sketch.polygon([{0, 0}, {4, 0}, {2, 1}, {4, 4}, {0, 4}]) |> Sketch.fillet(radius: 0.1),
      Sketch.rectangle(4, 6) |> Sketch.on(false),
      Sketch.rectangle(4, 6) |> Sketch.fillet(radius: -1),
      Sketch.rectangle(4, 6, on: Plane.new(normal: {0, 0, 0})),
      Sketch.rectangle(4, 6, on: Plane.new(normal: {1, 0, 0}, x_direction: {1, 0, 0})),
      Sketch.rectangle(4, 6, on: Plane.xy(z: 3, origin: {0, 0, 0})),
      Sketch.rectangle(4, 6, on: Plane.xy(typo: 1))
    ]

    for sketch <- invalid,
        do: assert({:error, %Smith.Error{}} = sketch |> Smith.extrude(2) |> Smith.evaluate())

    for height <- [0, :bad],
        do:
          assert(
            {:error, %Smith.Error{}} =
              Sketch.rectangle(2, 3) |> Smith.extrude(height) |> Smith.evaluate()
          )

    assert {:error, _} = Plane.to_world(Plane.xy(), {1, :bad})
  end
end
