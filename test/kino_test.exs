defmodule Smith.KinoTest do
  use ExUnit.Case, async: true

  test "stages produce independent previews without modifying the source" do
    base = Smith.box(10, 8, 3)
    {:ok, before} = Smith.evaluate(base)
    assert %Kino.JS{} = Smith.Kino.render(base)

    assert %Kino.JS{} =
             base |> Smith.hole(on: :top, diameter: 2, through: :all) |> Smith.Kino.render()

    assert {:ok, after_result} = Smith.evaluate(base)
    assert after_result.revision == before.revision
    assert %Kino.JS{} = Smith.Kino.render(before)
  end

  test "preview accepts sketches and evaluated assemblies and reports invalid input" do
    assert %Kino.JS{} = Smith.Kino.render(Smith.Sketch.circle(2))

    {:ok, assembly} =
      Smith.Assembly.new(:pair)
      |> Smith.Assembly.part(:box, Smith.box(1, 2, 3))
      |> Smith.evaluate()

    assert %Kino.JS{} = Smith.Kino.render(assembly)

    assert_raise RuntimeError, "cannot render Smith preview: :invalid_recipe", fn ->
      Smith.Kino.render(nil)
    end

    assert_raise RuntimeError, "cannot render Smith preview: :invalid_options", fn ->
      Smith.Kino.render(Smith.box(1, 2, 3), typo: true)
    end
  end

  test "evaluation and assembly view results pipe directly into previews" do
    assert %Kino.JS{} = Smith.box(1, 2, 3) |> Smith.evaluate() |> Smith.Kino.render()

    {:ok, assembly} =
      Smith.Assembly.new(:pair)
      |> Smith.Assembly.part(:box, Smith.box(1, 2, 3), exploded_offset: {0, 0, 10})
      |> Smith.evaluate()

    assert %Kino.JS{} = Smith.Kino.render({:ok, assembly})
    assert %Kino.JS{} = assembly |> Smith.Assembly.view(:exploded) |> Smith.Kino.render()
  end

  test "failed recipes retain their operation and step in the display error" do
    recipe = Smith.box(2, 3, 4) |> Smith.hole(on: :top, diameter: -1, through: :all)
    {:error, reason} = failure = Smith.evaluate(recipe)
    assert %Smith.Error{operation: :hole, step: 2, reason: :invalid_options} = reason

    for input <- [recipe, failure] do
      assert_raise RuntimeError, "cannot render Smith preview: #{inspect(reason)}", fn ->
        Smith.Kino.render(input)
      end
    end

    assert_raise RuntimeError, "cannot render Smith preview: :unknown_part", fn ->
      Smith.Kino.render({:error, :unknown_part})
    end
  end

  test "curve previews contain sampled paths instead of an empty surface" do
    path = Smith.Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])
    assert %Kino.JS{} = Smith.Kino.render(path)
    {:ok, result} = Smith.evaluate(path)
    assert {:ok, data} = Smith.Kino.Data.build(result, [])
    assert data.triangles == []
    assert data.lines == [[[0.0, 0.0, 0.0], [0.0, 0.0, 10.0]]]
    assert data.revision == result.revision
  end

  test "surface previews retain triangles without adding tessellation edges" do
    {:ok, result} = Smith.evaluate(Smith.Sketch.circle(4))
    assert {:ok, data} = Smith.Kino.Data.build(result, [])
    assert data.triangles != []
    assert data.lines == []
    assert {:error, :invalid_argument} = Smith.Kino.Data.build(result, tolerance: 1.0e-9)
  end
end
