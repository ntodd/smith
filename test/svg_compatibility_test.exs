defmodule Smith.SVGCompatibilityTest do
  use ExUnit.Case, async: false
  alias Smith.SVG

  test "SVG number grammar accepts omitted zeros, trailing dots, signs and exponents" do
    for {token, expected} <- [
          {".5", 0.5},
          {"-.5", -0.5},
          {"+.5", 0.5},
          {"1.", 1.0},
          {"1.e2", 100.0},
          {".5e1", 5.0}
        ] do
      assert SVG.PathData.number(token) == expected
    end
  end

  for name <-
        ~w(bootstrap-balloon bootstrap-qr heroicons-cog heroicons-heart lucide-bike lucide-volleyball) do
    @tag timeout: 300_000
    test "#{name} imports at physical sizes and produces valid engraved solids" do
      assert {:ok, asset} =
               SVG.load(Path.join([__DIR__, "fixtures", "svg", unquote(name) <> ".svg"]))

      for width <- [12, 30] do
        assert {:ok, layout} = SVG.layout(SVG.new(asset, width: width, align: {:center, :center}))
        assert {:ok, true} = OCEx.valid?(layout.result.shape)
        assert_in_delta layout.report.width, width, 0.001
        assert layout.report.area > 0

        assert {:ok, solid} =
                 layout.result
                 |> Smith.from_result()
                 |> Smith.extrude({0, 0, 1.2})
                 |> Smith.evaluate()

        assert {:ok, true} = OCEx.valid?(solid.shape)
        assert {:ok, volume} = OCEx.volume(solid.shape)
        assert_in_delta volume, layout.report.area * 1.2, 0.001
        base = Smith.box(40, 40, 2, align: {:center, :center, :min})
        assert {:ok, engraved} = base |> Smith.cut(Smith.from_result(solid)) |> Smith.evaluate()
        assert {:ok, true} = OCEx.valid?(engraved.shape)
        assert {:ok, remaining} = OCEx.volume(engraved.shape)
        assert_in_delta remaining, 3200 - volume, 0.001
      end
    end
  end
end
