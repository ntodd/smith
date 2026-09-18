defmodule Smith.SVGTest do
  use ExUnit.Case, async: true
  alias Smith.{SVG, Plane}

  defp asset(body, attrs \\ "viewBox=\"0 0 20 20\""),
    do: SVG.from_binary("<svg #{attrs}>#{body}</svg>")

  defp layout(body, opts) do
    assert {:ok, a} = asset(body)
    assert {:ok, l} = a |> SVG.new(opts) |> SVG.layout()
    l
  end

  test "fills keep islands and both winding rules, with actual mm bounds" do
    l = layout(~s|<path fill-rule="evenodd" d="M0 0H20V20H0Z M5 5H15V15H5Z"/>|, width: 20)
    assert_in_delta l.report.area, 300, 1.0e-5
    assert_in_delta l.report.width, 20, 1.0e-6
    assert {:ok, a} = asset(~s|<path d="M0 0H20V20H0Z M5 5H15V15H5Z"/>|)
    assert {:ok, l} = SVG.layout(SVG.new(a, width: 20))
    assert_in_delta l.report.area, 400, 1.0e-5
  end

  test "open strokes become cutters, with predictable physical width" do
    {:ok, a} =
      asset(
        ~s|<path fill="none" stroke="black" stroke-width="2" stroke-linecap="round" d="M1 10H19"/>|
      )

    motif =
      SVG.new(a,
        width: 20,
        mode: :strokes,
        stroke_width: 2,
        align: {:center, :center},
        on: Plane.xy(z: 3)
      )

    assert {:ok, l} = SVG.layout(motif)
    assert_in_delta l.report.width, 20, 0.0001
    assert_in_delta l.report.height, 2, 0.0001
    tag = Smith.box(30, 10, 3, align: {:center, :center, :min})
    assert {:ok, result} = tag |> Smith.cut(Smith.extrude(motif, -0.6)) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 900 - 0.6 * (36 + :math.pi()), 0.001
  end

  test "source units, nested transforms, reflection, selection and use instances" do
    {:ok, a} =
      asset(
        ~s|<defs><rect id="tile" width="2" height="3"/></defs><g id="pair" transform="translate(1 2)"><use href="#tile"/><use href="#tile" x="5"/></g>|,
        ~s|width="20mm" height="20mm" viewBox="0 0 20 20"|
      )

    assert {:ok, l} = SVG.layout(SVG.new(a))
    assert_in_delta l.report.area, 12, 1.0e-6
    assert_in_delta l.report.width, 7, 1.0e-6
    assert {:ok, {{x, y, _}, {xx, yy, _}}} = OCEx.bounds(l.result.shape)
    assert_in_delta x, 1, 1.0e-6
    assert_in_delta xx, 8, 1.0e-6
    assert_in_delta y, -5, 1.0e-6
    assert_in_delta yy, -2, 1.0e-6
    assert length(SVG.elements(a)) == 2
    assert {:ok, _} = SVG.layout(SVG.new(a, select: "pair"))
    assert {:error, _} = SVG.layout(SVG.new(a, select: "missing"))
  end

  test "quadratic, cubic, smooth and elliptical paths preserve geometry" do
    for d <- [
          "M0 0Q10 20 20 0Z",
          "M0 0C0 20 20 20 20 0Z",
          "M0 0q5 10 10 0t10 0Z",
          "M0 0c0 10 5 10 10 0s10 -10 10 0Z",
          "M0 10A10 5 30 1 1 20 10A10 5 30 1 1 0 10Z"
        ] do
      l = layout("<path d=\"#{d}\"/>", width: 20)
      assert l.report.area > 0
      assert {:ok, true} = OCEx.valid?(l.result.shape)
    end
  end

  test "SVG snapshots survive source edits and fit uses actual artwork bounds" do
    path = Path.join(System.tmp_dir!(), "smith-svg-#{System.unique_integer([:positive])}.svg")
    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      ~s|<svg viewBox="0 0 100 100"><rect x="40" y="45" width="20" height="10"/></svg>|
    )

    assert {:ok, a} = SVG.load(path)
    File.write!(path, "broken")
    assert {:ok, fitted} = SVG.fit(SVG.new(a), {22, 12}, margin: 1)
    assert {:ok, l} = SVG.layout(fitted)
    assert_in_delta l.report.width, 20, 1.0e-6
    assert_in_delta l.report.height, 10, 1.0e-6
    assert l.report.source_sha256 == a.sha256
  end

  test "malformed and unsupported SVGs fail without dropping visible content" do
    for body <- [
          ~s|<text>Hello</text>|,
          ~s|<image href="x.png"/>|,
          ~s|<path id="bad" d="M0 0L10 0" stroke="url(#paint)"/>|,
          ~s|<path d="M0 0L10 0" style="filter:blur(2px)"/>|,
          ~s|<use href="https://example.com/a.svg#x"/>|,
          ~s(<use id="a" href="#a"/>)
        ] do
      assert {:error, _} = asset(body)
    end

    assert {:error, _} =
             SVG.from_binary(~s|<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg/>|)

    assert {:error, _} = SVG.from_binary("<svg><g></svg>")
    assert {:error, _} = asset(~s|<path d="M0 nope"/>|)
  end

  test "explicitly hidden unsupported content does not affect the artwork" do
    assert {:ok, a} =
             asset(~s|<image display="none" href="unused"/><rect width="10" height="10"/>|)

    assert {:ok, _} = SVG.layout(SVG.new(a))
  end

  test "compact arc flags and commands following closepath follow SVG grammar" do
    alias Smith.SVG.PathData
    assert PathData.parse("M0 0A10 10 0 0110 10") == PathData.parse("M0 0 A10 10 0 0 1 10 10")

    assert [%{closed: true}, %{start: start}] =
             PathData.parse("M0 0L10 0L0 10Z L-10 0L0-10Z")

    assert start == {0, 0}
    assert {:error, _} = asset(~s|<path d="M0 0A10 10 0 2 1 10 10"/>|)
  end

  test "Bezier fill area is analytic, not a tessellated silhouette" do
    {:ok, a} =
      asset(~s|<path d="M0 0Q10 20 20 0Z"/>|, ~s|width="20mm" height="20mm" viewBox="0 0 20 20"|)

    {:ok, l} = SVG.layout(SVG.new(a))
    assert_in_delta l.report.area, 400 / 3, 1.0e-5
  end

  test "selected groups retain registration and optional selection fitting is explicit" do
    {:ok, a} =
      asset(
        ~s|<rect id="left" width="4" height="4"/><rect id="right" x="16" width="4" height="4"/>|
      )

    opts = [width: 20, align: {:center, :center}]
    {:ok, left} = SVG.layout(SVG.new(a, opts ++ [select: "left"]))
    {:ok, right} = SVG.layout(SVG.new(a, opts ++ [select: "right"]))
    assert_in_delta left.report.width, 4, 1.0e-6
    assert_in_delta right.report.width, 4, 1.0e-6
    assert {:ok, distance} = OCEx.closest_points(left.result.shape, right.result.shape)
    assert_in_delta distance.distance, 12, 1.0e-6
    {:ok, fitted} = SVG.layout(SVG.new(a, opts ++ [select: "left", reference: :selection]))
    assert_in_delta fitted.report.width, 20, 1.0e-6
  end

  test "artifacts contain matching revisions and filled outline SVGs can be reimported" do
    l =
      layout(~s|<path fill-rule="evenodd" d="M0 0H20V20H0Z M5 5H15V15H5Z"/>|,
        width: 20,
        on: Plane.yz(x: 4)
      )

    root =
      Path.join(System.tmp_dir!(), "smith-svg-artifacts-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, files} = SVG.write(l, root, width: 200, height: 200)
    assert File.read!(files.png) =~ <<137, 80, 78, 71>>
    assert JSON.decode!(File.read!(files.report))["revision"] == l.result.revision
    assert {:ok, outlines} = SVG.load(files.svg)
    assert {:ok, imported} = SVG.layout(SVG.new(outlines))
    assert_in_delta imported.report.area, l.report.area, 1.0e-5

    assert {:error, :revision_mismatch} =
             SVG.outline_svg(%{l | report: %{l.report | revision: "wrong"}})
  end

  test "open centerlines remain available for sweeps and placement follows the plane normal" do
    {:ok, a} = asset(~s|<path fill="none" stroke="black" d="M0 0L20 0"/>|)
    motif = SVG.new(a, width: 20, on: Plane.yz(x: 4))
    assert {:ok, [%{model: wire, closed: false}]} = SVG.paths(motif)
    assert {:ok, w} = Smith.evaluate(wire)
    assert {:ok, :wire} = OCEx.shape_type(w.shape)
    assert {:ok, result} = motif |> Smith.extrude(2) |> Smith.evaluate()
    assert {:ok, {{x, _, _}, {xx, _, _}}} = OCEx.bounds(result.shape)
    assert_in_delta x, 4, 1.0e-6
    assert_in_delta xx, 6, 1.0e-6
  end

  test "original stroked and outlined volleyballs produce equivalent engraving geometry" do
    root = Path.join(:code.priv_dir(:smith), "svg")
    {:ok, a} = SVG.load(Path.join(root, "volleyball.svg"))
    {:ok, b} = SVG.load(Path.join(root, "volleyball-outlined.svg"))
    {:ok, stroke} = SVG.layout(SVG.new(a, width: 18, align: {:center, :center}))
    {:ok, fill} = SVG.layout(SVG.new(b, width: 18, align: {:center, :center}))
    {:ok, missing} = OCEx.cut(stroke.result.shape, fill.result.shape)
    {:ok, extra} = OCEx.cut(fill.result.shape, stroke.result.shape)
    {:ok, missing_area} = OCEx.area(missing)
    {:ok, extra_area} = OCEx.area(extra)
    # 0.001 mm outline sampling, bounded by the measured boundary length.
    {:ok, edges} = OCEx.length(stroke.result.shape)
    assert missing_area + extra_area < edges * 0.001 * 2
    assert stroke.report.regions == 1
    assert fill.report.regions == 1
  end

  test "centerline paths can drive the existing sweep API" do
    {:ok, a} = asset(~s|<path fill="none" stroke="black" d="M0 0H20"/>|)
    {:ok, [%{path: path}]} = SVG.paths(SVG.new(a, width: 20))
    section = Smith.Sketch.circle(0.2, on: Plane.yz())
    assert {:ok, result} = section |> Smith.sweep(path) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, :math.pi() * 0.2 * 0.2 * 20, 1.0e-5
  end

  test "zero-length round and square strokes are retained as dots" do
    for {cap, expected} <- [{"round", :math.pi()}, {"square", 4}] do
      {:ok, a} =
        asset(
          ~s|<path fill="none" stroke="black" stroke-width="2" stroke-linecap="#{cap}" d="M10 10L10 10"/>|,
          ~s|width="20mm" height="20mm" viewBox="0 0 20 20"|
        )

      assert {:ok, l} = SVG.layout(SVG.new(a))
      assert_in_delta l.report.area, expected, 1.0e-6
    end
  end

  test "nonuniform source transforms affect source strokes but not a final-mm override" do
    {:ok, a} =
      asset(
        ~s|<path stroke="black" stroke-width="2" fill="none" transform="scale(2 3)" d="M0 0H10"/>|,
        ~s|width="20mm" height="20mm" viewBox="0 0 20 20"|
      )

    {:ok, source} = SVG.layout(SVG.new(a))
    {:ok, override} = SVG.layout(SVG.new(a, stroke_width: 2))
    assert_in_delta source.report.area, 120, 1.0e-5
    assert_in_delta override.report.area, 40, 1.0e-5
  end

  test "default-fill line elements and transparent paint do not manufacture filled silhouettes" do
    {:ok, a} = asset(~s|<line x1="0" y1="0" x2="10" y2="0" stroke="black"/>|)
    assert {:ok, line} = SVG.layout(SVG.new(a))

    {:ok, transparent} =
      asset(~s|<rect width="20" height="20" fill="transparent"/><line x2="10" stroke="black"/>|)

    assert {:ok, same} = SVG.layout(SVG.new(transparent))
    assert_in_delta line.report.area, same.report.area, 1.0e-6
  end

  test "invalid recipe options return tagged errors through evaluation" do
    {:ok, a} = asset(~s|<rect width="5" height="5"/>|)

    for opts <- [
          [mode: :bad],
          [width: 0],
          [width: 2, width: 3],
          [align: :bad],
          [tolerance: -1],
          [on: :wrong],
          [select: nil]
        ] do
      assert {:error, _} = a |> SVG.new(opts) |> Smith.evaluate()
    end

    assert {:error, _} = SVG.from_binary(<<255>>)
    assert {:error, _} = SVG.from_binary(~s|<svg title="&unknown;"/>|)

    assert {:error, _} =
             SVG.from_binary(~s|<svg><path d="M0 0L1 1"/><style>path {fill: red}</style></svg>|)
  end

  test "stylesheets in defs are rejected and local use expansion is bounded" do
    assert {:error, %{element: "style"}} =
             asset(~s|<defs><style>path {fill:none}</style></defs><path d="M0 0H10V10Z"/>|)

    definitions =
      for i <- 0..14 do
        if i == 0 do
          ~s|<g id="g0"><rect width="1" height="1"/></g>|
        else
          ~s|<g id="g#{i}"><use href="#g#{i - 1}"/><use href="#g#{i - 1}"/></g>|
        end
      end

    assert {:error, %{reason: :svg_complexity_limit}} =
             asset("<defs>#{Enum.join(definitions)}</defs><use href='#g14'/>")
  end

  test "numeric overflow and malformed fitting options remain tagged failures" do
    nested =
      String.duplicate(~s|<g transform="scale(1000000000000)">|, 40) <>
        ~s|<rect width="1" height="1"/>| <> String.duplicate("</g>", 40)

    assert {:error, %{reason: :invalid_numeric_range}} = asset(nested)
    assert {:error, _} = asset(~s|<path d="M0 0A1e-300 1e-300 0 0 1 1 1"/>|)
    {:ok, a} = asset(~s|<rect width="1" height="1"/>|)
    assert {:error, :invalid_options} = SVG.fit(SVG.new(a), {10, 10}, [1])
    assert {:error, :invalid_options} = SVG.fit(SVG.new(a, :invalid), {10, 10})
  end

  test "editor metadata is non-rendering, while alpha paints fail explicitly" do
    {:ok, a} =
      asset(
        ~s|<sodipodi:namedview/><metadata><rdf:RDF><dc:format>image/svg+xml</dc:format></rdf:RDF></metadata><rect width="5" height="5"/>|
      )

    assert {:ok, _} = SVG.layout(SVG.new(a))

    for color <- ["#0000", "#00000080", "rgba(0,0,0,0)"] do
      assert {:error, %{reason: {:unsupported_paint, "fill"}}} =
               asset(~s|<rect width="5" height="5" fill="#{color}"/>|)
    end
  end

  test "percentage radii use the SVG viewport basis and rounded rectangles copy a missing radius" do
    {:ok, a} =
      asset(
        ~s|<circle cx="10" cy="5" r="10%"/>|,
        ~s|width="20mm" height="10mm" viewBox="0 0 20 10"|
      )

    {:ok, l} = SVG.layout(SVG.new(a))
    assert_in_delta l.report.area, :math.pi() * 2.5, 1.0e-5

    {:ok, a} =
      asset(
        ~s|<rect width="40" height="20" rx="20%"/>|,
        ~s|width="40mm" height="20mm" viewBox="0 0 40 20"|
      )

    {:ok, l} = SVG.layout(SVG.new(a))
    assert_in_delta l.report.area, 800 - (4 - :math.pi()) * 64, 1.0e-5
  end
end
