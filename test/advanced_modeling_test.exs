defmodule Smith.AdvancedModelingTest do
  use ExUnit.Case, async: true
  alias Smith.{Path, Plane, Selector, Sketch}

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    result
  end

  defp volume(recipe, expected) do
    body = result(recipe)
    assert {:ok, actual} = OCEx.volume(body.shape)
    assert_in_delta actual, expected, 1.0e-4
    body
  end

  test "selectors compose face filters and extrema, and expose inspectable geometry" do
    body = result(Smith.box(20, 16, 10))
    top = Selector.type(:plane) |> Selector.facing(:z) |> Selector.at_max(:z)
    assert {:ok, [face]} = Smith.faces(body, top)
    assert {:ok, %{center: {10.0, 8.0, 10.0}}} = OCEx.face_info(face)
    assert {:ok, [_, _, _, _]} = Smith.edges(body, Selector.parallel(:z))
    assert {:ok, [_, _, _, _]} = Smith.edges(body, Selector.where(&(&1.length == 20)))
    assert {:ok, [bottom]} = Smith.faces(body, Selector.at_min(:z))
    assert {:ok, %{center: {10.0, 8.0, z}}} = OCEx.face_info(bottom)
    assert_in_delta z, 0, 1.0e-7
  end

  test "empty queries return lists; feature selections reject emptiness and incorrect counts" do
    body = result(Smith.box(20, 16, 10))
    assert {:ok, []} = Smith.faces(body, Selector.type(:sphere))
    assert {:error, :invalid_options} = Smith.faces(body, Selector.facing(:bad))

    assert {:error, :invalid_selector_result} =
             Smith.edges(body, Selector.where(fn _ -> :yes end))

    assert_raise RuntimeError, "predicate", fn ->
      Smith.faces(body, Selector.where(fn _ -> raise "predicate" end))
    end

    for {selection, count, reason} <- [
          {Selector.type(:sphere), 1, :empty_selection},
          {Selector.type(:plane), 1, :selection_count_mismatch}
        ] do
      assert {:error, %Smith.Error{operation: :shell, step: 2, reason: ^reason}} =
               Smith.box(20, 16, 10)
               |> Smith.shell(openings: selection, thickness: -2, count: count)
               |> Smith.evaluate()
    end
  end

  test "fillets accept composed selectors evaluated after transforms" do
    recipe = Smith.box(20, 16, 10) |> Smith.rotate({0, 1, 0}, 90)

    recipe
    |> Smith.fillet(edges: Selector.parallel(:x), radius: 1, count: 4)
    |> volume((320 - (4 - :math.pi())) * 10)
  end

  test "paths evaluate open connected wires, append immutably, and reject disconnected edges" do
    path = Path.new([Smith.line({0, 0, 0}, {0, 0, 5})])
    longer = Path.append(path, Smith.line({0, 0, 5}, {0, 0, 10}))
    assert {:ok, :wire} = OCEx.shape_type(result(longer).shape)
    assert {:ok, 5.0} = OCEx.length(result(path).shape)
    assert {:ok, 10.0} = OCEx.length(result(longer).shape)

    for invalid <- [
          Path.new([]),
          Path.new([Smith.box(1, 1, 1)]),
          Path.append(path, Smith.line({10, 0, 0}, {10, 0, 1}))
        ] do
      assert {:error, %Smith.Error{operation: :path}} = Smith.evaluate(invalid)
    end
  end

  test "smooth loft preserves the ruled default and reports bad options at evaluation" do
    sections = [
      Sketch.circle(2),
      Sketch.circle(4, on: Plane.xy(z: 3)),
      Sketch.circle(2, on: Plane.xy(z: 6))
    ]

    volume(Smith.loft(sections), 56 * :math.pi())
    volume(Smith.loft(sections, ruled: false), 344 / 5 * :math.pi())

    assert {:error, %Smith.Error{operation: :loft, reason: :invalid_options}} =
             Smith.loft(sections, ruled: nil) |> Smith.evaluate()
  end

  test "sweeps compose with holes and transforms" do
    path = Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])

    Sketch.circle(4)
    |> Smith.sweep(path)
    |> Smith.hole(on: :top, diameter: 2, through: :all)
    |> Smith.translate({3, 4, 5})
    |> volume(150 * :math.pi())

    ring = Sketch.circle(4) |> Sketch.cut(Sketch.circle(2))

    assert {:error, %Smith.Error{operation: :sweep, reason: :sweep_profile_has_holes}} =
             ring |> Smith.sweep(path) |> Smith.evaluate()
  end

  test "curved paths preserve placed profile coordinates" do
    path = Path.new([Smith.arc({0, 0, 0}, {0, 0, 1}, {1, 0, 0}, 10, 0, 90)])

    Sketch.circle(1, on: Plane.xz(), at: {10, 0})
    |> Smith.sweep(path)
    |> volume(5 * :math.pi() * :math.pi())
  end

  test "planar splines interpolate local points on arbitrary planes" do
    outline =
      Sketch.profile([
        Sketch.spline([{0, 0}, {2, 2}, {4, 0}]),
        Sketch.line({4, 0}, {0, 0})
      ])

    for plane <- [Plane.xy(), Plane.yz(x: 7)] do
      face = result(Sketch.on(outline, plane))
      assert {:ok, [spline]} = Smith.edges(face, Selector.type(:other))
      {:ok, point} = Plane.to_world(plane, {2, 2})
      assert {:ok, distance} = OCEx.distance_to_point(spline, point)
      assert_in_delta distance, 0, 1.0e-7
      assert {:ok, area} = OCEx.area(face.shape)
      assert area > 4
      volume(Smith.extrude(Sketch.on(outline, plane), 3), area * 3)
    end
  end

  test "shell selects fresh faces after placement and preserves its source recipe" do
    source = Smith.box(20, 16, 10) |> Smith.translate({4, 5, 6})
    before = result(source)
    recipe = source |> Smith.shell(openings: Selector.facing(:z), thickness: -2, count: 1)
    volume(recipe, 1664)
    assert result(source).revision == before.revision
  end

  @tag :tmp_dir
  test "new operations export watertight printable files with STEP volume agreement", %{
    tmp_dir: root
  } do
    path = Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])

    recipes = [
      {"sweep", Sketch.circle(2) |> Smith.sweep(path)},
      {"smooth",
       Smith.loft(
         [
           Sketch.circle(2),
           Sketch.circle(4, on: Plane.xy(z: 3)),
           Sketch.circle(2, on: Plane.xy(z: 6))
         ],
         ruled: false
       )},
      {"shell",
       Smith.box(20, 16, 10) |> Smith.shell(openings: Selector.facing(:z), thickness: -2)}
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

  test "extrema retain ties and face normal signs follow rotation" do
    body = result(Smith.box(10, 10, 10))
    assert {:ok, edges} = Smith.edges(body, Selector.at_max(:z))
    assert length(edges) == 4
    assert {:ok, [bottom]} = Smith.faces(body, Selector.facing({:z, :negative}))
    assert {:ok, %{normal: {_, _, normal}}} = OCEx.face_info(bottom)
    assert normal < -0.99
    turned = result(Smith.box(20, 16, 10) |> Smith.rotate({0, 1, 0}, 90))
    assert {:ok, [_]} = Smith.faces(turned, Selector.facing(:x))
    assert {:error, :invalid_options} = Smith.edges(body, Selector.facing(:z))
    assert {:ok, []} = Smith.faces(body, Selector.type(:sphere) |> Selector.at_max(:z))
  end

  test "shell invalid arguments and missing paths fail at the correct recipe step" do
    for opts <- [
          [thickness: -2],
          [openings: :all],
          [openings: :all, thickness: -2, extra: true],
          [openings: Selector.facing(:z), thickness: 0],
          [openings: Selector.facing(:z), thickness: -20],
          [openings: Selector.facing(:z), thickness: -2, count: 0]
        ] do
      assert {:error, %Smith.Error{operation: :shell, step: 2}} =
               Smith.box(20, 16, 10) |> Smith.shell(opts) |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{operation: :sweep, reason: :invalid_path}} =
             Sketch.circle(1) |> Smith.sweep(nil) |> Smith.evaluate()

    assert {:error, %Smith.Error{operation: :sweep, reason: :misaligned_profile}} =
             Sketch.circle(1, on: Plane.xy(z: 2))
             |> Smith.sweep(Path.new([Smith.line({0, 0, 0}, {0, 0, 10})]))
             |> Smith.evaluate()
  end

  test "paths reject reversed joins and loops without rewriting user geometry" do
    first = Smith.line({0, 0, 0}, {0, 0, 5})

    for {last, reason} <- [
          {Smith.line({0, 0, 10}, {0, 0, 5}), :disconnected_path},
          {Smith.line({0, 0, 5}, {0, 0, 0}), :closed_path}
        ] do
      assert {:error, %Smith.Error{operation: :path, reason: ^reason}} =
               Path.new([first, last]) |> Smith.evaluate()
    end
  end

  test "spline endpoint tangents transform as directions on a translated plane" do
    outline =
      Sketch.profile(
        [
          Sketch.spline([{0, 0}, {2, 2}, {4, 0}], {{1, 1}, {1, -1}}),
          Sketch.line({4, 0}, {0, 0})
        ],
        on: Plane.yz(origin: {7, 8, 9})
      )

    body = result(outline)
    assert {:ok, [edge]} = Smith.edges(body, Selector.type(:other))
    assert {:ok, %{tangent: {x, y, z}}} = OCEx.edge_sample(edge, 0)
    assert_in_delta x, 0, 1.0e-7
    assert_in_delta y, :math.sqrt(0.5), 1.0e-6
    assert_in_delta z, :math.sqrt(0.5), 1.0e-6

    for curve <- [
          Sketch.spline(nil),
          Sketch.spline([{0, 0}]),
          Sketch.spline([{0, 0}, {1, 1}], {{0, 0}, {1, 1}}),
          Sketch.spline([{0, 0}, {1, 1}], :bad)
        ] do
      assert {:error, %Smith.Error{}} = Sketch.profile([curve]) |> Smith.evaluate()
    end
  end

  test "degenerate cone apex edges do not break type queries or midpoint predicates" do
    cone = result(Smith.cone(5, 0, 10))
    assert {:ok, selected} = Smith.edges(cone, Selector.new())
    assert {:ok, all} = Smith.edges(cone)
    assert length(selected) == length(all)
    for {a, b} <- Enum.zip(selected, all), do: assert(OCEx.same?(a, b) == {:ok, true})
    assert {:ok, circles} = Smith.edges(cone, Selector.type(:circle))
    assert circles != []
    assert {:ok, apex} = Smith.edges(cone, Selector.where(&(&1.length < 1.0e-7)))
    assert apex != []

    for edge <- apex do
      assert {:ok, info} = OCEx.edge_info(edge)
      assert_in_delta elem(info.start, 2), 10, 1.0e-7
    end
  end
end
