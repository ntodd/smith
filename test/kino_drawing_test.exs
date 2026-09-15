defmodule Smith.KinoDrawingTest do
  use ExUnit.Case, async: true

  test "measured drawings render directly without changing export units" do
    {:ok, part} = Smith.box(60, 40, 5) |> Smith.evaluate()
    {:ok, width} = Smith.Measure.extent(part, :x)
    {:ok, drawing} = Smith.Drawing.new(part)
    {:ok, drawing} = Smith.Drawing.dimension(drawing, width, orientation: :horizontal)
    {:ok, before} = Smith.Drawing.svg(drawing)

    assert %Kino.JS{} =
             Smith.Kino.render(drawing, label: "Measured mounting plate", hidden: false)

    assert %Kino.JS{} = Smith.Kino.render({:ok, drawing})
    assert {:ok, ^before} = Smith.Drawing.svg(drawing)
    assert before =~ "mm\""
    assert before =~ "60.00 mm"

    assert_raise RuntimeError, ~r/invalid_options/, fn ->
      Smith.Kino.render(drawing, view: :top)
    end
  end
end
