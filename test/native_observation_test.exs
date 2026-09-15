defmodule Smith.NativeObservationTest do
  use ExUnit.Case, async: true

  test "native query results compose with drawings, dimensions, and Kino" do
    {:ok, shape} = OCEx.box(10, 20, 30)
    {:ok, width} = Smith.Measure.extent(shape, :x)
    assert {:ok, drawing} = Smith.Drawing.new(shape)
    assert {:ok, drawing} = Smith.Drawing.dimension(drawing, width, orientation: :horizontal)
    assert {:ok, _} = Smith.Drawing.svg(drawing)
    assert %Kino.JS{} = Smith.Kino.render(shape, view: :top)
  end
end
