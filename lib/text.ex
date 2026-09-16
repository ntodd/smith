defmodule Smith.Text do
  @moduledoc """
  Deferred, font-backed planar text with measurable layout and fit validation.

  `new/2` keeps the font snapshot and options; `layout/1` constructs exact filled
  outlines and returns both an evaluated `result` and a serializable `report`.
  The report binds measured ink bounds, glyph positions, font hash and layout
  settings to the geometry revision. Use that same result for PNG/SVG previews
  and inspection. `Smith.extrude/2` follows the text plane's normal.

  Font size is the em size in millimeters, not capital height. Fit decisions
  use actual ink bounds, not character count or typographic advance. Holes,
  accents and disconnected dots are retained. Overlapping glyphs are unioned.
  HarfBuzz shapes one horizontal script/direction run; paragraphs, automatic bidi
  itemization, line wrapping, color fonts and variable-font axes are not exposed.
  """
  alias Smith.{Font, Geometry, Plane}
  defstruct [:string, options: []]
  @type t :: %__MODULE__{string: String.t(), options: keyword()}
  @type layout :: %{result: Smith.Result.t(), report: map()}

  @doc """
  Describes text without constructing geometry. Required: `font: %Smith.Font{}`
  and `size: mm`. Options:

    * `on: Smith.Plane.xy()` and `at: {0, 0}` set plane and local anchor.
    * `align: {:min, :baseline}` anchors the ink's left edge and baseline.
      X supports `:min`, `:center`, `:max`, `:origin`; Y supports `:min`,
      `:center`, `:max`, `:baseline`. Ink alignment excludes surrounding spaces.
    * `tracking: 0` adds mm between shaped clusters; nonzero disables optional
      ligatures. Required script shaping is retained.
    * `direction: :auto` (`:ltr` or `:rtl`) and `language: ""` control shaping.

  Unknown/duplicate options fail at evaluation. Unsupported glyphs return
  `:missing_glyph`; empty/whitespace-only text fails instead of making a blank tag.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(string, opts \\ []), do: %__MODULE__{string: string, options: opts}

  @doc """
  Evaluates text and returns `%{result: result, report: report}`.

  Report dimensions, `ink_bounds` and glyph `origin`/`bounds` are in local plane
  coordinates (mm); `world_bounds` describes the positioned BREP. `baseline`
  is the local baseline origin. `advance` includes whitespace and tracking.
  `area` is unioned filled area (mm²), `faces` counts connected face regions.
  `font` records SHA-256, face index, family and style. `revision` matches result.
  Glyph clusters are UTF-8 byte offsets, not character indices. Spaces have nil
  bounds. Glyph bounds precede union; overall bounds measure the final shape.
  No native handles or font bytes are included in the report.
  """
  @spec layout(t()) :: {:ok, layout()} | {:error, term()}
  def layout(%__MODULE__{string: string, options: opts}) do
    with true <-
           Geometry.options(opts, [
             :font,
             :size,
             :on,
             :at,
             :align,
             :tracking,
             :direction,
             :language
           ]),
         font = Keyword.get(opts, :font),
         :ok <- Font.validate(font),
         {:ok, frame} <- Plane.frame(Keyword.get(opts, :on, Plane.xy())),
         {:ok, native} <-
           OCEx.text(string, font.bytes, Keyword.get(opts, :size),
             face_index: font.face_index,
             tracking: Keyword.get(opts, :tracking, 0),
             direction: Keyword.get(opts, :direction, :auto),
             language: Keyword.get(opts, :language, "")
           ),
         {:ok, shift} <- placement(native.ink_bounds, opts),
         {:ok, local} <- OCEx.translate(native.shape, shift),
         {:ok, positioned} <- Plane.place(local, frame),
         {:ok, result} <- Geometry.snapshot(positioned),
         {:ok, bounds} <- OCEx.bounds(local),
         {:ok, world_bounds} <- OCEx.bounds(positioned),
         {:ok, area} <- OCEx.area(positioned),
         {:ok, faces} <- OCEx.faces(positioned) do
      {{x0, y0, _}, {x1, y1, _}} = bounds

      report =
        native
        |> Map.drop([:shape, :ink_bounds, :family, :style])
        |> Map.merge(%{
          text: string,
          size: Keyword.fetch!(opts, :size),
          tracking: Keyword.get(opts, :tracking, 0),
          language: Keyword.get(opts, :language, ""),
          align: Keyword.get(opts, :align, {:min, :baseline}),
          plane: frame,
          font: %{
            sha256: font.sha256,
            face_index: font.face_index,
            family: native.family,
            style: native.style
          },
          revision: result.revision,
          ink_bounds: {{x0, y0}, {x1, y1}},
          world_bounds: world_bounds,
          width: x1 - x0,
          height: y1 - y0,
          area: area,
          faces: length(faces),
          baseline: {elem(shift, 0), elem(shift, 1)},
          units: "mm",
          glyphs: Enum.map(native.glyphs, &shift_glyph(&1, shift))
        })

      {:ok, %{result: result, report: report}}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def layout(_), do: {:error, :invalid_text}

  @doc """
  Uniformly sizes text to a `{width, height}` ink envelope, retaining placement.

  Options: `margin: 0` mm on each side, `min_size: 0` mm em size, `grow: false`.
  Scales size and tracking together to preserve proportions. Default only
  shrinks. Returns a new recipe after remeasuring its geometry; it never clips,
  stretches or silently removes letters. `:text_too_small` means the required
  size is below `min_size`; `:text_does_not_fit` means remeasured bounds fail.
  This fits dimensions only; use `validate/2` to verify the actual placement.
  """
  @spec fit(t(), {number(), number()}, keyword()) :: {:ok, t()} | {:error, term()}
  def fit(text, envelope, opts \\ []) do
    with true <- Geometry.options(opts, [:margin, :min_size, :grow]),
         {:ok, {width, height, margin}} <- envelope(envelope, Keyword.get(opts, :margin, 0)),
         minimum = Keyword.get(opts, :min_size, 0),
         grow = Keyword.get(opts, :grow, false),
         true <- is_number(minimum) and minimum >= 0 and is_boolean(grow),
         {:ok, layout} <- layout(text) do
      factor =
        min(
          (width - 2 * margin) / layout.report.width,
          (height - 2 * margin) / layout.report.height
        )

      factor = if grow, do: factor, else: min(factor, 1)
      size = layout.report.size * factor

      if size < minimum or size <= 1.0e-7 do
        {:error, :text_too_small}
      else
        fitted = %{
          text
          | options:
              text.options
              |> Keyword.put(:size, size)
              |> Keyword.put(:tracking, layout.report.tracking * factor)
        }

        with {:ok, check} <- layout(fitted) do
          if check.report.width <= width - 2 * margin + 1.0e-6 and
               check.report.height <= height - 2 * margin + 1.0e-6,
             do: {:ok, fitted},
             else: {:error, :text_does_not_fit}
        end
      end
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  @doc """
  Measures and checks actual local ink placement and visible height.

  Required `within: {{xmin, ymin}, {xmax, ymax}}` is a local rectangular region.
  Options: `margin: 0`, `min_height: 0`, `tolerance: 1.0e-6`, all in mm.
  Returns the layout with `report.status` (`:passed` or `:failed`) and explicit
  measured checks. A produced report is not necessarily a pass. Malformed
  inputs return errors. This is a bounds/readability check, not a certified
  minimum stroke thickness or printer-resolution check; inspect a geometry
  preview and verify the final fused/cut solid with `Smith.Inspection`.
  """
  @spec validate(t(), keyword()) :: {:ok, layout()} | {:error, term()}
  def validate(text, opts) do
    with true <- Geometry.options(opts, [:within, :margin, :min_height, :tolerance]),
         {{x0, y0}, {x1, y1}} <- Keyword.get(opts, :within),
         true <- Enum.all?([x0, y0, x1, y1], &is_number/1),
         {:ok, {_, _, margin}} <- envelope({x1 - x0, y1 - y0}, Keyword.get(opts, :margin, 0)),
         minimum = Keyword.get(opts, :min_height, 0),
         tolerance = Keyword.get(opts, :tolerance, 1.0e-6),
         true <- is_number(minimum) and minimum >= 0 and is_number(tolerance) and tolerance >= 0,
         {:ok, layout} <- layout(text) do
      {{a, b}, {c, d}} = layout.report.ink_bounds

      fits =
        a >= x0 + margin - tolerance and b >= y0 + margin - tolerance and
          c <= x1 - margin + tolerance and d <= y1 - margin + tolerance

      readable = layout.report.height + tolerance >= minimum

      checks = [
        %{
          kind: :ink_bounds,
          status: status(fits),
          measured: layout.report.ink_bounds,
          within: {{x0 + margin, y0 + margin}, {x1 - margin, y1 - margin}},
          tolerance: tolerance
        },
        %{
          kind: :min_height,
          status: status(readable),
          measured: layout.report.height,
          minimum: minimum,
          tolerance: tolerance
        }
      ]

      {:ok,
       %{
         layout
         | report: Map.merge(layout.report, %{status: status(fits and readable), checks: checks})
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_options}
    end
  end

  @doc """
  Writes a layout's measured JSON report, PNG preview and outline SVG together.

  Takes the output of `layout/1` or `validate/2`, preserving that exact snapshot.
  A new revision-named directory beneath `root` prevents stale overwrites.
  Options: `width: 960`, `height: 320` in pixels. Both images look directly at
  the text plane. SVG contains geometry paths, so viewing needs no installed
  font. JSON includes artifact paths and the source revision; native resources
  and font bytes are excluded. A failed write may leave partial images but
  does not publish report.json. Returns directory, report, png and svg paths.
  """
  @spec write(layout(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write(layout, root, opts \\ [])

  def write(
        %{
          result: %Smith.Result{} = result,
          report:
            %{revision: revision, text: title, plane: %{origin: origin, n: normal, u: direction}} =
              report
        },
        root,
        opts
      )
      when is_binary(root) and is_binary(title) and is_binary(revision) do
    with true <- Geometry.options(opts, [:width, :height]),
         {:ok, result} <- Geometry.result(result),
         :ok <- matching_revision(result.revision, revision),
         plane = Plane.new(origin: origin, normal: normal, x_direction: direction),
         {:ok, _} <- Plane.frame(plane),
         directory =
           Path.join(
             root,
             result.revision <> "-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
           ),
         :ok <- File.mkdir_p(directory),
         png = Path.join(directory, "text.png"),
         svg = Path.join(directory, "text.svg"),
         {:ok, _} <-
           Smith.Render.write(result, png,
             view: plane,
             width: Keyword.get(opts, :width, 960),
             height: Keyword.get(opts, :height, 320)
           ),
         {:ok, drawing} <- Smith.Drawing.new(result, on: plane),
         {:ok, _} <- Smith.Drawing.write(drawing, svg, title: report.text),
         json =
           report
           |> Map.put(:schema_version, 1)
           |> Map.put(:artifacts, %{png: "text.png", svg: "text.svg"})
           |> Geometry.json()
           |> JSON.encode!(),
         path = Path.join(directory, "report.json"),
         :ok <- File.write(path, json) do
      {:ok, %{directory: directory, report: path, png: png, svg: svg}}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  defp matching_revision(revision, revision), do: :ok
  defp matching_revision(_, _), do: {:error, :revision_mismatch}

  @doc false
  def evaluate(text) do
    with {:ok, layout} <- layout(text), do: {:ok, layout.result.shape}
  end

  @doc false
  def extrude(%__MODULE__{options: opts} = text, distance)
      when is_number(distance) and distance != 0 do
    with {:ok, shape} <- evaluate(text),
         {:ok, normal} <- Plane.normal(Keyword.get(opts, :on, Plane.xy())),
         do: OCEx.extrude(shape, Plane.scale(normal, distance))
  end

  def extrude(_, _), do: {:error, :invalid_extrusion}

  defp status(true), do: :passed
  defp status(false), do: :failed

  defp envelope({width, height}, margin)
       when is_number(width) and is_number(height) and is_number(margin) and margin >= 0 and
              width > 2 * margin and height > 2 * margin,
       do: {:ok, {width, height, margin}}

  defp envelope(_, _), do: {:error, :invalid_options}

  defp placement({{x0, y0, _}, {x1, y1, _}}, opts) do
    with {x, y} <- Keyword.get(opts, :at, {0, 0}),
         {horizontal, vertical} <- Keyword.get(opts, :align, {:min, :baseline}),
         true <-
           is_number(x) and is_number(y) and horizontal in [:min, :center, :max, :origin] and
             vertical in [:min, :center, :max, :baseline] do
      {:ok, {x - anchor(horizontal, x0, x1), y - anchor(vertical, y0, y1), 0}}
    else
      _ -> {:error, :invalid_alignment}
    end
  end

  defp anchor(:min, low, _), do: low
  defp anchor(:max, _, high), do: high
  defp anchor(:center, low, high), do: (low + high) / 2
  defp anchor(_, _, _), do: 0

  defp shift_glyph(glyph, shift) do
    bounds =
      case glyph.bounds do
        nil -> nil
        {low, high} -> {Geometry.add(low, shift), Geometry.add(high, shift)}
      end

    %{glyph | origin: Geometry.add(glyph.origin, shift), bounds: bounds}
  end
end
