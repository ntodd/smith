defmodule Smith.PartitionTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Selector, Sketch}

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    result
  end

  defp volume(recipe, expected) do
    body = result(recipe)
    assert {:ok, actual} = OCEx.volume(body.shape)
    assert_in_delta actual, expected, 1.0e-6
    body
  end

  test "split is deferred, accepts named/positioned planes and keeps signed material" do
    source = Smith.box(20, 12, 10)
    plane = Plane.xy(z: 3)
    both = source |> Smith.split(plane) |> volume(2400)
    assert {:ok, [_, _]} = OCEx.solids(both.shape)
    source |> Smith.split(plane, keep: :positive) |> volume(1680)
    source |> Smith.split(plane, keep: :negative) |> volume(720)
    source |> Smith.split(:xy, keep: :positive) |> volume(2400)
    source |> volume(2400)
  end

  test "new cut faces can be selected for further finishing" do
    body =
      Smith.box(20, 12, 10)
      |> Smith.split(Plane.xy(z: 3), keep: :positive)
      |> Smith.fillet(edges: Selector.parallel(:z), radius: 1, count: 4)
      |> volume((240 - (4 - :math.pi())) * 7)

    assert {:ok, [%{center: {_, _, z}}]} =
             Smith.inspect_faces(body, Selector.facing({:z, :negative}))

    assert_in_delta z, 3, 1.0e-7
  end

  test "section keeps holes and supports another extrusion after transformation" do
    body = Smith.cylinder(5, 10) |> Smith.hole(on: :top, diameter: 4, through: :all)
    profile = Smith.section(body, Plane.xy(z: 4))
    face = result(profile)
    assert {:ok, :face} = OCEx.shape_type(face.shape)
    assert {:ok, area} = OCEx.area(face.shape)
    assert_in_delta area, 21 * :math.pi(), 1.0e-6
    profile |> Smith.translate({0, 0, -4}) |> Smith.extrude({0, 0, 2}) |> volume(42 * :math.pi())
    body |> Smith.section(:xz) |> Smith.extrude({0, 2, 0}) |> volume(120)
  end

  test "disconnected sections extrude as separate solids" do
    original = Smith.compound([Smith.box(4, 5, 6), Smith.box(4, 5, 6, at: {10, 0, 0})])
    section = Smith.section(original, Plane.xy(z: 3))
    assert {:ok, [_, _]} = Smith.faces(result(section))
    result = section |> Smith.extrude({0, 0, 2}) |> volume(80)
    assert {:ok, [_, _]} = OCEx.solids(result.shape)
  end

  test "empty results remain valid query values and invalid plane/options identify the step" do
    source = Smith.box(10, 10, 10)
    empty = result(Smith.section(source, Plane.xy(z: 20)))
    assert {:ok, []} = Smith.faces(empty)
    assert {:ok, []} = Smith.edges(empty)
    empty = result(Smith.split(source, Plane.xy(z: 20), keep: :positive))
    assert {:ok, []} = OCEx.solids(empty.shape)

    for {operation, args, reason} <- [
          {:split, [:bad], :invalid_plane},
          {:split, [Plane.xy(), [keep: :top]], :invalid_options},
          {:section, [Plane.new(normal: {0, 0, 0})], :invalid_plane}
        ] do
      assert {:error, %Smith.Error{operation: ^operation, step: 2, reason: ^reason}} =
               apply(Smith, operation, [source | args]) |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{operation: :section, reason: :wrong_shape_type}} =
             Sketch.circle(2)
             |> Smith.extrude(3)
             |> Smith.section(:xy)
             |> Smith.section(:xy)
             |> Smith.evaluate()
  end
end
