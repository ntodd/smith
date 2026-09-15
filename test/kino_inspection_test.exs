defmodule Smith.KinoInspectionTest do
  use ExUnit.Case, async: true

  test "named views, native edge overlays and clipping stay tied to the source" do
    {:ok, result} = Smith.box(10, 20, 30) |> Smith.evaluate()
    opts = [view: :front, edges: true, clip: {Smith.Plane.xy(z: 15), :positive}]
    assert %Kino.JS{} = Smith.Kino.render(result, opts)
    assert {:ok, data} = Smith.Kino.Data.build(result, opts)
    assert data.view == :front and data.edges
    assert data.edge_lines != []
    assert data.clip.origin == [0.0, 0.0, 15.0]
    assert data.clip.keep == :positive
    assert data.revision == result.revision
    assert_raise RuntimeError, fn -> Smith.Kino.render(result, view: :nonsense) end
  end

  test "colored layers support additions and removals" do
    assert %Kino.JS{} =
             Smith.Kino.render([
               {Smith.box(2, 2, 2), {80, 140, 180}},
               {Smith.box(1, 1, 1, at: {3, 0, 0}), {200, 50, 30}}
             ])
  end
end
