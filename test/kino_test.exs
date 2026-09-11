defmodule Smith.KinoTest do
  use ExUnit.Case, async: true

  test "stages produce independent previews without modifying the source" do
    base = Smith.box(10, 8, 3)
    {:ok, before} = Smith.evaluate(base)
    assert {:ok, %Kino.JS{}} = Smith.Kino.render(base)

    assert {:ok, %Kino.JS{}} =
             base |> Smith.hole(on: :top, diameter: 2, through: :all) |> Smith.Kino.render()

    assert {:ok, after_result} = Smith.evaluate(base)
    assert after_result.revision == before.revision
    assert {:ok, %Kino.JS{}} = Smith.Kino.render(before)
  end

  test "preview accepts sketches and evaluated assemblies and reports invalid input" do
    assert {:ok, %Kino.JS{}} = Smith.Kino.render(Smith.Sketch.circle(2))

    {:ok, assembly} =
      Smith.Assembly.new(:pair)
      |> Smith.Assembly.part(:box, Smith.box(1, 2, 3))
      |> Smith.evaluate()

    assert {:ok, %Kino.JS{}} = Smith.Kino.render(assembly)
    assert {:error, :invalid_recipe} = Smith.Kino.render(nil)
    assert {:error, :invalid_options} = Smith.Kino.render(Smith.box(1, 2, 3), typo: true)
  end
end
