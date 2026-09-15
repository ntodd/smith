defmodule Smith.RenderTest do
  use ExUnit.Case, async: true
  alias Smith.Render
  @moduletag :tmp_dir

  test "headless PNG contains pixels, dimensions and the source revision" do
    {:ok, result} = Smith.box(20, 10, 4) |> Smith.evaluate()
    assert {:ok, png} = Render.png(result, view: :top, width: 160, height: 120)
    assert <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", 160::32, 120::32, _::binary>> = png
    assert png =~ result.revision
    chunks = chunks(binary_part(png, 8, byte_size(png) - 8), [])
    pixels = for {"IDAT", data} <- chunks, into: <<>>, do: data
    raw = :zlib.uncompress(pixels)
    assert byte_size(raw) == 120 * (1 + 160 * 3)
    colors = for <<0, row::binary-size(480) <- raw>>, <<r, g, b <- row>>, do: {r, g, b}
    assert length(Enum.uniq(colors)) > 1
  end

  test "depth testing makes opaque layer order irrelevant and keeps standard views distinct" do
    a = Smith.box(10, 10, 2)
    b = Smith.box(4, 4, 2, at: {3, 3, 3})
    opts = [view: :top, width: 96, height: 96, edges: false]
    {:ok, x} = Render.png([{a, {200, 30, 30}}, {b, {30, 180, 30}}], opts)
    {:ok, y} = Render.png([{b, {30, 180, 30}}, {a, {200, 30, 30}}], opts)

    idat = fn png ->
      chunks(binary_part(png, 8, byte_size(png) - 8), []) |> Enum.filter(&(elem(&1, 0) == "IDAT"))
    end

    assert idat.(x) == idat.(y)
    {:ok, front} = Render.png(a, view: :front, width: 96, height: 96)
    {:ok, top} = Render.png(a, view: :top, width: 96, height: 96)
    refute idat.(front) == idat.(top)
  end

  test "bad render options fail before allocating large buffers" do
    for opts <- [
          [width: 0],
          [width: 100_000],
          [view: :wrong],
          [color: {-1, 0, 0}],
          [clip: :wrong],
          [width: 100, width: 200]
        ] do
      assert {:error, _} = Render.png(Smith.box(2, 2, 2), opts)
    end
  end

  defp chunks(<<>>, acc), do: Enum.reverse(acc)

  defp chunks(<<n::32, kind::binary-size(4), data::binary-size(n), crc::32, rest::binary>>, acc) do
    assert :erlang.crc32(kind <> data) == crc
    chunks(rest, [{kind, data} | acc])
  end
end
