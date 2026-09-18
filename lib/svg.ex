defmodule Smith.SVG.Asset do
  @moduledoc "Immutable SVG bytes, SHA-256 provenance, and parsed vector elements. Create with `Smith.SVG.load/1` or `Smith.SVG.from_binary/1`."
  @derive {Inspect, only: [:sha256]}
  defstruct [:bytes, :sha256, :document]
  @opaque t :: %__MODULE__{bytes: binary(), sha256: String.t(), document: map()}
end

defmodule Smith.SVG do
  @moduledoc """
  Deferred SVG artwork as planar CAD regions, with fills, strokes and holes.

  `load/1` snapshots a local file; `new/2` records a recipe. `layout/1` evaluates
  actual geometry and returns a result and revision-linked measurements.
  Extrude the recipe with `Smith.extrude/2`, then fuse raised artwork or cut
  an engraving. SVG's downward Y axis is converted to upward CAD Y.

  Supported: paths (all commands), basic shapes, groups, local use references,
  affine transforms, viewBox, physical units, inherited presentation attributes
  and inline styles. Fill curves remain native curves; stroke centerlines are
  sampled with an explicit final-mm tolerance. Fill rules retain holes,
  self-intersections and disconnected islands.

  Painted mode unions selected fill and stroke regions. Paint colors are
  metadata, not Boolean operations or material assignments. No scripts, DTDs,
  external resources, stylesheets, raster tracing, masks, filters, gradients,
  dashes or partial opacity are rendered. Unsupported visible content returns
  an element-specific error. Convert embedded text to paths or use `Smith.Text`.
  """
  alias Smith.SVG.{Asset, Document, XML}
  alias Smith.SVG.Geometry, as: G
  alias Smith.{Geometry, Plane}
  defstruct [:asset, options: []]
  @type t :: %__MODULE__{asset: Asset.t(), options: keyword()}
  @type layout :: %{result: Smith.Result.t(), report: map()}
  @options [
    :mode,
    :width,
    :height,
    :align,
    :at,
    :on,
    :select,
    :stroke_width,
    :tolerance,
    :bounds,
    :reference
  ]

  @doc "Reads and snapshots a local SVG (up to 4 MiB). Subsequent file edits do not change the asset."
  @spec load(String.t()) :: {:ok, Asset.t()} | {:error, term()}
  def load(path) when is_binary(path) do
    with {:ok, %{size: size}} when size <= 4_194_304 <- File.stat(path),
         {:ok, bytes} <- File.read(path) do
      from_binary(bytes)
    else
      {:ok, _} -> {:error, :svg_size_limit}
      error -> error
    end
  end

  def load(_), do: {:error, :invalid_svg}

  @doc "Parses SVG bytes without native geometry or external resource access. Errors identify unsupported elements."
  @spec from_binary(binary()) :: {:ok, Asset.t()} | {:error, term()}
  def from_binary(bytes) do
    with {:ok, xml} <- XML.parse(bytes), {:ok, document} <- Document.parse(xml) do
      {:ok, %Asset{bytes: bytes, sha256: Geometry.hash(bytes), document: document}}
    end
  end

  @doc """
  Records an SVG recipe. Options:

    * `mode: :painted` (union of fills and strokes), `:fill`, or `:strokes`.
    * `width:` or `height:` in mm; both form a contain-fit box, never stretching.
    * `bounds: :artwork` (default) or `:viewport` determines sizing/alignment.
    * `align: {:origin, :origin}` preserves the source origin. Each axis also
      accepts `:min`, `:center`, `:max`. `at: {0,0}`, `on: Plane.xy()` place it.
    * `select: :all`, an ID/group-label string, a list of strings, an element
      index, or `{:fill, color}` / `{:stroke, color}` selects artwork.
    * `reference: :document` retains shared size/alignment across selections;
      use `:selection` to fit and center only the chosen elements.
    * `stroke_width:` overrides stroke width in final mm. Otherwise original
      stroke widths follow SVG transforms and artwork scaling.
    * `tolerance: 0.01` controls stroke sampling in final mm (must exceed 1e-6).

  Construction makes no native calls. Validation occurs during evaluation.
  """
  @spec new(Asset.t(), keyword()) :: t()
  def new(asset, opts \\ []), do: %__MODULE__{asset: asset, options: opts}

  @doc "Lists visible elements with stable indices, IDs, groups, and paint metadata for selection."
  @spec elements(Asset.t()) :: [map()]
  def elements(%Asset{document: doc}),
    do: Enum.map(doc.elements, &Map.take(&1, [:index, :id, :label, :groups, :kind, :style]))

  @doc "Evaluates positioned planar faces and returns their actual bounds, area, region count, source hash and geometry revision."
  @spec layout(t()) :: {:ok, layout()} | {:error, term()}
  def layout(%__MODULE__{asset: %Asset{} = asset, options: opts}) do
    guarded(fn ->
      validate(asset, opts)
      chosen = select(asset.document.elements, Keyword.get(opts, :select, :all))
      if chosen == [], do: throw({:svg, :empty_selection})

      reference =
        if Keyword.get(opts, :reference, :document) == :document,
          do: asset.document.elements,
          else: chosen

      {scale, reference_bounds} = sizing(reference, asset.document.viewport, opts)
      shape = G.build(chosen, opts, scale)
      if G.unwrap(OCEx.faces(shape)) == [], do: throw({:svg, :empty_svg})
      shift = placement(reference_bounds, opts)
      local = shape |> OCEx.translate(shift) |> G.unwrap()
      frame = Plane.frame(Keyword.get(opts, :on, Plane.xy())) |> G.unwrap()
      positioned = Plane.place(local, frame) |> G.unwrap()
      result = Geometry.snapshot(positioned) |> G.unwrap()
      {{x0, y0, _}, {x1, y1, _}} = bounds = OCEx.bounds(local) |> G.unwrap()

      report = %{
        source_sha256: asset.sha256,
        revision: result.revision,
        width: x1 - x0,
        height: y1 - y0,
        area: OCEx.area(positioned) |> G.unwrap(),
        regions: length(OCEx.faces(positioned) |> G.unwrap()),
        ink_bounds: bounds,
        world_bounds: OCEx.bounds(positioned) |> G.unwrap(),
        scale: scale,
        plane: frame,
        elements: Enum.map(chosen, & &1.index),
        settings: Map.new(Keyword.delete(opts, :on)),
        tolerance: Keyword.get(opts, :tolerance, 0.01),
        diagnostics: []
      }

      %{result: result, report: report}
    end)
  end

  def layout(_), do: {:error, :invalid_svg}

  @doc "Uniformly fits artwork within `{width,height}` mm, with optional `margin: 0`. Preserves placement and selection."
  @spec fit(t(), {number(), number()}, keyword()) :: {:ok, t()} | {:error, term()}
  def fit(recipe, box, opts \\ [])

  def fit(%__MODULE__{} = recipe, {w, h}, opts) when is_number(w) and is_number(h) do
    margin = if Geometry.options(opts, [:margin]), do: Keyword.get(opts, :margin, 0), else: nil

    if Geometry.options(opts, [:margin]) and Geometry.options(recipe.options, @options) and
         is_number(margin) and margin >= 0 and
         min(w, h) > 2 * margin do
      fitted = %{
        recipe
        | options:
            recipe.options
            |> Keyword.put(:width, w - 2 * margin)
            |> Keyword.put(:height, h - 2 * margin)
      }

      with {:ok, _} <- layout(fitted), do: {:ok, fitted}
    else
      {:error, :invalid_options}
    end
  end

  def fit(_, _, _), do: {:error, :invalid_options}

  @doc "Writes JSON measurements and PNG/SVG previews of the converted CAD geometry. Accepts a recipe or its evaluated layout."
  @spec write(t() | layout(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write(value, directory, opts \\ [])

  def write(%__MODULE__{} = recipe, directory, opts) do
    with {:ok, layout} <- layout(recipe), do: write(layout, directory, opts)
  end

  def write(%{result: result, report: %{revision: revision, plane: frame} = report}, root, opts)
      when is_binary(root) do
    with true <- Geometry.options(opts, [:width, :height]),
         {:ok, result} <- Geometry.result(result),
         true <- result.revision == revision,
         plane = Plane.new(origin: frame.origin, normal: frame.n, x_direction: frame.u),
         directory =
           Path.join(
             root,
             revision <> "-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
           ),
         :ok <- File.mkdir_p(directory),
         png = Path.join(directory, "artwork.png"),
         svg = Path.join(directory, "artwork.svg"),
         {:ok, _} <-
           Smith.Render.write(result, png,
             view: plane,
             width: Keyword.get(opts, :width, 640),
             height: Keyword.get(opts, :height, 640)
           ),
         {:ok, outlines} <- outline_svg(%{result: result, report: report}),
         :ok <- File.write(svg, outlines),
         json =
           report
           |> Map.put(:schema_version, 1)
           |> Map.put(:artifacts, %{png: "artwork.png", svg: "artwork.svg"})
           |> Geometry.json()
           |> JSON.encode!(),
         path = Path.join(directory, "report.json"),
         :ok <- File.write(path, json) do
      {:ok, %{directory: directory, report: path, png: png, svg: svg}}
    else
      false -> {:error, :invalid_layout_or_options}
      error -> error
    end
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  @doc """
  Serializes an evaluated layout as filled, even-odd SVG outlines in its local
  plane. Wires are sampled with `tolerance: 0.005` mm; the output records the
  source geometry revision and is independent of fonts and external resources.
  This is a geometry export, not a round trip of source styles or groups.
  """
  @spec outline_svg(layout(), keyword()) :: {:ok, binary()} | {:error, term()}
  def outline_svg(layout, opts \\ [])

  def outline_svg(%{result: result, report: report}, opts) do
    guarded(fn ->
      unless Geometry.options(opts, [:tolerance]), do: throw({:svg, :invalid_options})
      tolerance = Keyword.get(opts, :tolerance, 0.005)
      unless is_number(tolerance) and tolerance > 1.0e-7, do: throw({:svg, :invalid_options})
      result = Geometry.result(result) |> G.unwrap()
      unless result.revision == report.revision, do: throw({:svg, :revision_mismatch})
      frame = report.plane

      paths =
        for face <- G.unwrap(OCEx.faces(result.shape)) do
          loops =
            for wire <- G.unwrap(OCEx.wires(face)) do
              points =
                for p <- G.unwrap(OCEx.wire_points(wire, tolerance)) do
                  local = Plane.sub(p, frame.origin)
                  {Plane.dot(local, frame.u), -Plane.dot(local, frame.v)}
                end

              [first | rest] = Enum.map(points, fn {x, y} -> "#{x},#{y}" end)
              "M" <> first <> "L" <> Enum.join(rest, " ") <> "Z"
            end

          ~s(<path fill-rule="evenodd" d="#{Enum.join(loops, " ")}"/>)
        end

      {{x0, y0, _}, {x1, y1, _}} = report.ink_bounds

      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{x1 - x0}mm" height="#{y1 - y0}mm" viewBox="#{x0} #{-y1} #{x1 - x0} #{y1 - y0}"><desc>Geometry #{result.revision}; tolerance #{tolerance} mm</desc><g fill="black" stroke="none">#{Enum.join(paths)}</g></svg>)
    end)
  end

  def outline_svg(_, _), do: {:error, :invalid_layout}

  @doc "Returns positioned native wire recipes for centerline sweeps or projection, retaining open/closed subpaths and element metadata."
  @spec paths(t()) :: {:ok, [map()]} | {:error, term()}
  def paths(%__MODULE__{asset: %Asset{} = asset, options: opts}) do
    guarded(fn ->
      validate(asset, opts)
      chosen = select(asset.document.elements, Keyword.get(opts, :select, :all))
      if chosen == [], do: throw({:svg, :empty_selection})

      reference =
        if Keyword.get(opts, :reference, :document) == :document,
          do: asset.document.elements,
          else: chosen

      {scale, reference_bounds} = sizing(reference, asset.document.viewport, opts)
      shift = placement(reference_bounds, opts)
      frame = Plane.frame(Keyword.get(opts, :on, Plane.xy())) |> G.unwrap()

      Enum.flat_map(chosen, fn element ->
        Enum.flat_map(element.paths, fn path ->
          case G.wire(path) do
            nil ->
              []

            wire ->
              shape =
                wire
                |> OCEx.affine_transform(G.matrix(element, scale))
                |> G.unwrap()
                |> OCEx.translate(shift)
                |> G.unwrap()
                |> Plane.place(frame)
                |> G.unwrap()

              result = Geometry.snapshot(shape) |> G.unwrap()

              path_recipe =
                if path.closed do
                  nil
                else
                  edges =
                    for edge <- G.unwrap(OCEx.edges(shape)) do
                      edge |> Geometry.snapshot() |> G.unwrap() |> Smith.from_result()
                    end

                  Smith.Path.new(edges)
                end

              [
                %{
                  model: Smith.from_result(result),
                  path: path_recipe,
                  closed: path.closed,
                  element: element.index,
                  id: element.id
                }
              ]
          end
        end)
      end)
    end)
  end

  def paths(_), do: {:error, :invalid_svg}

  @doc false
  def evaluate(recipe), do: with({:ok, l} <- layout(recipe), do: {:ok, l.result.shape})
  @doc false
  def extrude(%__MODULE__{options: opts} = recipe, distance)
      when is_number(distance) and distance != 0 do
    with {:ok, shape} <- evaluate(recipe),
         {:ok, normal} <- Plane.normal(Keyword.get(opts, :on, Plane.xy())),
         do: OCEx.extrude(shape, Plane.scale(normal, distance))
  end

  def extrude(_, _), do: {:error, :invalid_extrusion}

  defp guarded(fun) do
    try do
      {:ok, fun.()}
    rescue
      ArithmeticError -> {:error, :invalid_numeric_range}
    catch
      {:svg, reason} -> {:error, reason}
    end
  end

  defp validate(asset, opts) do
    unless Geometry.options(opts, @options), do: throw({:svg, :invalid_options})
    unless Geometry.hash(asset.bytes) == asset.sha256, do: throw({:svg, :svg_revision_mismatch})

    unless Keyword.get(opts, :mode, :painted) in [:painted, :fill, :strokes] and
             Keyword.get(opts, :bounds, :artwork) in [:artwork, :viewport] and
             Keyword.get(opts, :reference, :document) in [:document, :selection],
           do: throw({:svg, :invalid_options})

    for key <- [:width, :height, :stroke_width] do
      if Keyword.has_key?(opts, key) and not (is_number(opts[key]) and opts[key] > 1.0e-6),
        do: throw({:svg, :invalid_options})
    end

    tolerance = Keyword.get(opts, :tolerance, 0.01)
    unless is_number(tolerance) and tolerance > 1.0e-6, do: throw({:svg, :invalid_options})
  end

  defp select(elements, :all), do: elements
  defp select(elements, n) when is_integer(n), do: Enum.filter(elements, &(&1.index == n))

  defp select(elements, {paint, color}) when paint in [:fill, :stroke] and is_binary(color),
    do: Enum.filter(elements, &(&1.style[Atom.to_string(paint)] == color))

  defp select(elements, id) when is_binary(id),
    do: Enum.filter(elements, &(&1.id == id or &1.label == id or id in &1.groups))

  defp select(elements, ids) when is_list(ids),
    do: ids |> Enum.flat_map(&select(elements, &1)) |> Enum.uniq_by(& &1.index)

  defp select(_, _), do: throw({:svg, :invalid_selection})
  defp sizing(elements, viewport, opts), do: sizing(elements, viewport, opts, 1.0, 0)

  defp sizing(elements, viewport, opts, scale, iteration) do
    bounds =
      if Keyword.get(opts, :bounds, :artwork) == :viewport do
        {{0, -viewport.height * scale, 0}, {viewport.width * scale, 0, 0}}
      else
        shape = G.build(elements, opts, scale)
        if G.unwrap(OCEx.faces(shape)) == [], do: throw({:svg, :empty_svg})
        OCEx.bounds(shape) |> G.unwrap()
      end

    {{x, y, _}, {xx, yy, _}} = bounds
    ratios = [] |> ratio(opts[:width], xx - x) |> ratio(opts[:height], yy - y)
    factor = if ratios == [], do: 1.0, else: Enum.min(ratios)

    cond do
      abs(factor - 1) < 1.0e-7 -> {scale, bounds}
      iteration >= 16 -> throw({:svg, :size_unreachable})
      true -> sizing(elements, viewport, opts, scale * factor, iteration + 1)
    end
  end

  defp ratio(acc, nil, _), do: acc
  defp ratio(acc, target, actual) when actual > 1.0e-7, do: [target / actual | acc]
  defp ratio(_, _, _), do: throw({:svg, :empty_svg})

  defp placement({{x, y, _}, {xx, yy, _}}, opts) do
    case {Keyword.get(opts, :align, {:origin, :origin}), Keyword.get(opts, :at, {0, 0})} do
      {{ax, ay}, {px, py}}
      when ax in [:min, :center, :max, :origin] and ay in [:min, :center, :max, :origin] and
             is_number(px) and is_number(py) ->
        {px - anchor(ax, x, xx), py - anchor(ay, y, yy), 0}

      _ ->
        throw({:svg, :invalid_options})
    end
  end

  defp anchor(:origin, _, _), do: 0
  defp anchor(:min, a, _), do: a
  defp anchor(:max, _, b), do: b
  defp anchor(:center, a, b), do: (a + b) / 2
end
