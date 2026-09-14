defmodule Smith.Drawing do
  @moduledoc """
  Orthographic line drawings with visible and hidden edges.

  A drawing is a snapshot of evaluated geometry in a chosen view plane.
  OCEx computes visibility from the BREP and retains native curves. SVG and
  DXF export sample those curves into polylines; changing export tolerances
  does not recalculate visibility or change the drawing.

      iex> {:ok, drawing} = Smith.Drawing.new(Smith.box(20, 10, 4), on: :xy)
      iex> {:ok, svg} = Smith.Drawing.svg(drawing, hidden: false)
      iex> String.starts_with?(svg, "<svg")
      true

  <div class="smith-doc-preview" data-preview="api-drawing-0" data-model="svg" data-label="Top drawing">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  Use \x60Smith.Kino.render/2\x60 for a rotatable 3D preview. In Livebook, display
  a drawing with \x60Kino.Image.new(svg, :svg)\x60. See the
  [drawing guide](drawings.html) for view orientation and file export.
  """
  alias Smith.{Assembly, Plane, Result}
  defstruct [:visible, :hidden, :plane, :source_revision]

  @opaque t :: %__MODULE__{
            visible: OCEx.Shape.t(),
            hidden: OCEx.Shape.t(),
            plane: Plane.t(),
            source_revision: String.t()
          }
  @type source ::
          Smith.Model.t()
          | Smith.Sketch.t()
          | Smith.Path.t()
          | Assembly.t()
          | Result.t()
          | Assembly.Result.t()

  @doc """
  Evaluates a source and computes its orthographic drawing.

  Returns \x60{:ok, drawing}\x60. An existing result skips recipe evaluation;
  its BREP revision is checked before use. The drawing's \x60source_revision\x60
  identifies that source, while \x60visible\x60 and \x60hidden\x60 hold new native
  edge collections. Treat these fields as read-only.

  Options:

    * \x60:on\x60 — \x60:xy\x60 (default), \x60:xz\x60, \x60:yz\x60, or a \x60Smith.Plane\x60.
    * \x60:tangents\x60 — include smooth G1 boundaries between faces; default false.

  The viewer looks along the plane's negative normal. Plane-local X points
  right and local Y points up. Coordinates are millimeters relative to its
  origin; moving the origin only along the normal has no effect. Surface
  seams and isoparametric lines are excluded. Coincident projected edges
  may remain; the drawing is not a joined cutting contour.

  Assemblies show installed manufactured parts, excluding references and
  printable extras. To draw an exploded or display pose, pass the result
  of \x60Smith.Assembly.view/2\x60. Fetch a reference explicitly to draw it.

  Unknown/duplicate options return \x60:invalid_options\x60, invalid frames
  return \x60:invalid_plane\x60, and stale input results return
  \x60:revision_mismatch\x60. Recipe and native geometry errors propagate.
  """
  @spec new(source(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(source, opts \\ []) do
    with :ok <- options(opts, :new),
         plane = plane(Keyword.get(opts, :on, :xy)),
         {:ok, frame} <- Plane.frame(plane),
         {:ok, result} <- result(source),
         {:ok, curves} <-
           OCEx.drawing(result.shape, frame.origin, frame.n, frame.u,
             tangents: Keyword.get(opts, :tangents, false)
           ) do
      {:ok,
       %__MODULE__{
         visible: curves.visible,
         hidden: curves.hidden,
         plane: plane,
         source_revision: result.revision
       }}
    end
  end

  @doc """
  Samples drawing curves into view-local XY polylines.

  Returns \x60{:ok, %{visible: polylines, hidden: polylines}}\x60. Each polyline
  is a list of \x60{x, y}\x60 points for one native edge, including both
  endpoints. Closed curves repeat the starting point. Separate edges are
  not stitched or deduplicated.

  Options shared by SVG and DXF export:

    * \x60:tolerance\x60 — linear deflection in mm, default 0.03.
    * \x60:angular_tolerance\x60 — angular deflection in radians, default 0.1.
    * \x60:hidden\x60 — include hidden edges, default true.

  Both deflections must exceed 1.0e-7. Sampling uses
  \x60OCEx.polylines/3\x60; tolerances control that algorithm and are not a
  certified global error bound for arbitrary splines. Empty layers return
  empty lists. Invalid options return \x60:invalid_options\x60; native failures
  propagate. Passing something other than a drawing returns \x60:invalid_argument\x60.
  """
  @spec polylines(t(), keyword()) ::
          {:ok, %{visible: [[{float(), float()}]], hidden: [[{float(), float()}]]}}
          | {:error, term()}
  def polylines(drawing, opts \\ [])

  def polylines(%__MODULE__{} = drawing, opts) do
    with :ok <- options(opts, :sample), do: sample(drawing, opts)
  end

  def polylines(_, _), do: {:error, :invalid_argument}

  @doc """
  Serializes a drawing to a standalone SVG binary.

  Supports the sampling options in \x60polylines/2\x60, plus:

    * \x60:padding\x60 — nonnegative margin in mm, default 5.
    * \x60:stroke_width\x60 — positive line width in mm, default 0.25.
    * \x60:title\x60 — XML text for the accessible title, default "Smith drawing".

  SVG has explicit millimeter width/height and a viewBox matching drawing
  units. Its extent includes padding and half the stroke width at each
  boundary. Coordinates are reflected vertically for SVG's downward Y axis;
  the underlying drawing coordinates remain unchanged. Visible edges are
  solid black; hidden edges are gray with a 2 mm dash and 1 mm gap, painted
  first. There are no fills, scripts, external assets, or dimensions.

  Returns \x60{:ok, binary}\x60, or \x60{:error, :empty_drawing}\x60 when the
  selected layers contain no points. Options and native errors follow
  \x60polylines/2\x60. Title text is escaped; invalid XML characters fail.
  """
  @spec svg(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def svg(drawing, opts \\ [])

  def svg(%__MODULE__{} = drawing, opts) do
    with :ok <- options(opts, :svg),
         {:ok, lines} <- sample(drawing, opts),
         {:ok, {xmin, ymin, xmax, ymax}} <- extent(lines) do
      stroke = Keyword.get(opts, :stroke_width, 0.25)
      margin = Keyword.get(opts, :padding, 5) + stroke / 2
      width = xmax - xmin + 2 * margin
      height = ymax - ymin + 2 * margin
      viewbox = Enum.map_join([xmin - margin, -ymax - margin, width, height], " ", &number/1)
      title = escape(Keyword.get(opts, :title, "Smith drawing"))

      xml = [
        ~s|<svg xmlns="http://www.w3.org/2000/svg" width="#{number(width)}mm" height="#{number(height)}mm" viewBox="#{viewbox}" role="img">|,
        "<title>",
        title,
        "</title>",
        ~s|<g transform="scale(1,-1)" fill="none" stroke-width="#{number(stroke)}" stroke-linejoin="round" stroke-linecap="round">|,
        svg_layer("hidden", lines.hidden, ~s|stroke="#777" stroke-dasharray="2 1"|),
        svg_layer("visible", lines.visible, ~s|stroke="#111"|),
        "</g></svg>\n"
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  def svg(_, _), do: {:error, :invalid_argument}

  @doc """
  Serializes a drawing to ASCII DXF (AutoCAD 2000 / AC1015).

  Options are those in \x60polylines/2\x60. Coordinates retain local X/Y
  orientation with Z=0. \x60$INSUNITS\x60 is 4 (millimeters). Each sampled
  edge becomes an LWPOLYLINE on the VISIBLE or HIDDEN layer. Closed edges
  use the closed flag and omit the duplicate endpoint. Curves are polylines,
  not DXF ARC, CIRCLE, or SPLINE entities.

  VISIBLE uses continuous lines. HIDDEN uses a 2 mm dash / 1 mm gap
  linetype. Readers may apply their own display scaling to that pattern.
  Empty drawings produce a valid file without entities. This writer does
  not add dimensions, text, blocks, paper layouts, or toolpaths.

  Returns \x60{:ok, binary}\x60; options and native errors follow \x60polylines/2\x60.
  """
  @spec dxf(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def dxf(drawing, opts \\ [])

  def dxf(%__MODULE__{} = drawing, opts) do
    with {:ok, lines} <- polylines(drawing, opts) do
      header = [
        0,
        "SECTION",
        2,
        "HEADER",
        9,
        "$ACADVER",
        1,
        "AC1015",
        9,
        "$INSUNITS",
        70,
        4,
        9,
        "$MEASUREMENT",
        70,
        1,
        0,
        "ENDSEC"
      ]

      tables = [
        0,
        "SECTION",
        2,
        "TABLES",
        0,
        "TABLE",
        2,
        "LTYPE",
        70,
        2,
        linetype("CONTINUOUS", []),
        linetype("HIDDEN", [2, -1]),
        0,
        "ENDTAB",
        0,
        "TABLE",
        2,
        "LAYER",
        70,
        3,
        layer("0", "CONTINUOUS", 7),
        layer("VISIBLE", "CONTINUOUS", 7),
        layer("HIDDEN", "HIDDEN", 8),
        0,
        "ENDTAB",
        0,
        "ENDSEC"
      ]

      entities =
        for {name, paths} <- [{"HIDDEN", lines.hidden}, {"VISIBLE", lines.visible}],
            points <- paths,
            do: dxf_polyline(name, points)

      data = [header, tables, 0, "SECTION", 2, "ENTITIES", entities, 0, "ENDSEC", 0, "EOF"]
      {:ok, data |> List.flatten() |> Enum.map_join("\n", &number/1) |> Kernel.<>("\n")}
    end
  end

  def dxf(_, _), do: {:error, :invalid_argument}

  @doc """
  Writes an SVG or DXF file, inferring the format from its extension.

  Returns \x60{:ok, path}\x60. Options belong to the selected serializer.
  The parent directory must exist; an existing file is overwritten only
  after serialization succeeds. File-system failures return their reason.
  Other extensions return \x60:unsupported_format\x60. This writes a single
  drawing file without a model bundle, print validation, or manifest.
  """
  @spec write(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def write(drawing, path, opts \\ [])

  def write(%__MODULE__{} = drawing, path, opts) when is_binary(path) do
    serialized =
      case Path.extname(path) |> String.downcase() do
        ".svg" -> svg(drawing, opts)
        ".dxf" -> dxf(drawing, opts)
        _ -> {:error, :unsupported_format}
      end

    with {:ok, data} <- serialized, :ok <- File.write(path, data), do: {:ok, path}
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  defp result(%Result{} = result) do
    with {:ok, brep} <- OCEx.to_brep(result.shape) do
      if Base.encode16(:crypto.hash(:sha256, brep), case: :lower) == result.revision,
        do: {:ok, result},
        else: {:error, :revision_mismatch}
    end
  end

  defp result(%Assembly.Result{} = result) do
    with :ok <- Assembly.validate_result(result), do: {:ok, result}
  end

  defp result(source), do: Smith.evaluate(source)
  defp plane(:xy), do: Plane.xy()
  defp plane(:xz), do: Plane.xz()
  defp plane(:yz), do: Plane.yz()
  defp plane(%Plane{} = plane), do: plane

  defp options(opts, mode) do
    valid =
      is_list(opts) and Keyword.keyword?(opts) and
        length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))) and
        Enum.all?(opts, fn
          {:on, value} when mode == :new ->
            value in [:xy, :xz, :yz] or is_struct(value, Plane)

          {:tangents, value} when mode == :new ->
            is_boolean(value)

          {:hidden, value} when mode != :new ->
            is_boolean(value)

          {key, value} when key in [:tolerance, :angular_tolerance] and mode != :new ->
            is_number(value) and value > 1.0e-7

          {:padding, value} when mode == :svg ->
            is_number(value) and value >= 0

          {:stroke_width, value} when mode == :svg ->
            is_number(value) and value > 0

          {:title, value} when mode == :svg ->
            xml_text?(value)

          _ ->
            false
        end)

    if valid, do: :ok, else: {:error, :invalid_options}
  end

  defp sample(drawing, opts) do
    tolerance = Keyword.get(opts, :tolerance, 0.03)
    angular = Keyword.get(opts, :angular_tolerance, 0.1)

    with {:ok, visible} <- OCEx.polylines(drawing.visible, tolerance, angular),
         {:ok, hidden} <-
           if(Keyword.get(opts, :hidden, true),
             do: OCEx.polylines(drawing.hidden, tolerance, angular),
             else: {:ok, []}
           ) do
      xy = fn paths ->
        Enum.map(paths, fn points -> Enum.map(points, fn {x, y, _} -> {x, y} end) end)
      end

      {:ok, %{visible: xy.(visible), hidden: xy.(hidden)}}
    end
  end

  defp extent(lines) do
    case List.flatten(lines.visible ++ lines.hidden) do
      [] ->
        {:error, :empty_drawing}

      [{x, y} | rest] ->
        {:ok,
         Enum.reduce(rest, {x, y, x, y}, fn {x, y}, {a, b, c, d} ->
           {min(a, x), min(b, y), max(c, x), max(d, y)}
         end)}
    end
  end

  defp number(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp number(value), do: to_string(value)
  defp svg_layer(_, [], _), do: []

  defp svg_layer(name, lines, style) do
    [
      ~s|<g id="#{name}" #{style}>|,
      Enum.map(lines, fn points ->
        coordinates = Enum.map_join(points, " ", fn {x, y} -> number(x) <> "," <> number(y) end)
        ~s|<polyline points="#{coordinates}"/>|
      end),
      "</g>"
    ]
  end

  defp xml_text?(text) when is_binary(text) do
    String.valid?(text) and
      Enum.all?(String.to_charlist(text), fn c ->
        c in [9, 10, 13] or c in 0x20..0xD7FF or c in 0xE000..0xFFFD or c in 0x10000..0x10FFFF
      end)
  end

  defp xml_text?(_), do: false

  defp escape(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

  defp linetype(name, pattern) do
    [
      0,
      "LTYPE",
      100,
      "AcDbSymbolTableRecord",
      100,
      "AcDbLinetypeTableRecord",
      2,
      name,
      70,
      0,
      3,
      name,
      72,
      65,
      73,
      length(pattern),
      40,
      Enum.sum(Enum.map(pattern, &abs/1)),
      Enum.map(pattern, &[49, &1, 74, 0])
    ]
  end

  defp layer(name, line, color),
    do: [
      0,
      "LAYER",
      100,
      "AcDbSymbolTableRecord",
      100,
      "AcDbLayerTableRecord",
      2,
      name,
      70,
      0,
      62,
      color,
      6,
      line
    ]

  defp dxf_polyline(name, points) do
    {x, y} = hd(points)
    {u, v} = List.last(points)
    closed = length(points) > 3 and abs(x - u) <= 1.0e-7 and abs(y - v) <= 1.0e-7
    points = if closed, do: Enum.drop(points, -1), else: points

    [
      0,
      "LWPOLYLINE",
      100,
      "AcDbEntity",
      8,
      name,
      100,
      "AcDbPolyline",
      90,
      length(points),
      70,
      if(closed, do: 1, else: 0),
      Enum.map(points, fn {x, y} -> [10, x, 20, y] end)
    ]
  end
end
