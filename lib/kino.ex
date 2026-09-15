defmodule Smith.Kino do
  @moduledoc """
  Interactive 3D previews for Livebook through Kino.JS.

  Add Kino alongside Smith in the notebook setup. `render/2` returns a
  Kino directly; leave the call as the last expression in a Livebook cell.
  Each output holds an independent mesh snapshot with its own camera.

  The renderer and controls are Smith's JavaScript/WebGL code. Kino supplies
  Livebook's asset and data integration; OCEx supplies the mesh. Rendering
  does not use a CDN or a server-side graphics process.

  Previews support named orthographic views, rotation, zoom, edges, clipping,
  fullscreen, and PNG download. Colored layers can show modeling differences.
  They do not provide part selection, dimension editing, or automatic exploded
  assembly views. Use `Smith.Assembly.view/2` to create a
  display or exploded snapshot before rendering. See the [Livebook guide](livebook.html)
  for stage-by-stage examples and notebook setup.
  """

  @doc """
  Creates an interactive preview and returns the Kino directly.

  Accepts a model, sketch, path, assembly, native shape, evaluated result, or `{:ok, result}`
  from `Smith.evaluate/1` or `Smith.Assembly.view/2`. Recipes are
  evaluated on each call; passing an existing result skips that step.
  The shape is then meshed into a snapshot. Assemblies show installed
  manufactured parts only. Sketches show their faces; paths and edge-only
  recipes show sampled curves. A mixed shape with faces displays its surfaces.

  A `Smith.Drawing` (or `{:ok, drawing}`) produces a responsive 2D SVG preview
  with fullscreen and SVG download. The drawing fills the available width;
  its exported millimeter dimensions remain unchanged. Drawings accept `:label`
  and the options of `Smith.Drawing.svg/2`. Choose their plane with
  `Smith.Drawing.new/2`; 3D camera, edge, and clipping options do not apply.

  ## Options for 3D previews

    * `:label` — toolbar text, default `"Smith preview"`.
    * `:view` — initial orthographic view: `:isometric` (default), `:top`,
      `:bottom`, `:front`, `:back`, `:left`, or `:right`. Top looks from +Z,
      front from −Y, and right from +X, matching `Smith.Render`.
    * `:edges` — show sampled native edges initially, default false.
    * `:clip` — `{Smith.Plane.t(), :positive | :negative}` to retain one side
      visually. This clips the preview without capping or modifying geometry.
      Use `Smith.section/2` for a measured cross-section.
    * `:tolerance` — linear mesh deflection in mm, default 0.03.
    * `:angular_tolerance` — angular mesh deflection in radians, default 0.5.

  Deflections must satisfy OCEx's native minimum (greater than 1.0e-7).
  Invalid options, evaluation failures, and meshing failures raise
  `RuntimeError` with the failure reason. Passing `{:error, reason}` raises
  the same error; modeling failures include the `Smith.Error` fields, such
  as operation and step. To handle modeling failures yourself, match on
  `Smith.evaluate/1` before rendering. The preview does not run the print
  export checks.

  A list of `{source, {red, green, blue}}` layers creates a colored scene;
  RGB channels are integers from 0 through 255. This is useful for rendering
  the added and removed results of `Smith.Inspection.compare/2`. Layers are
  opaque. Toolbar controls select views, show edges, and move axis-aligned
  clipping planes. A supplied arbitrary clipping plane is also supported.

  ## Display in Livebook

  Leave the render call as the cell's last expression:

      iex> blank = Smith.box(20, 10, 4)
      iex> preview = Smith.Kino.render(blank, label: "Blank")
      iex> is_struct(preview, Kino.JS)
      true

  <div class="smith-doc-preview" data-preview="api-kino-0" data-model="blank" data-label="Blank">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  Evaluation results can be piped straight into the preview:

      iex> blank = Smith.box(20, 10, 4)
      iex> blank |> Smith.evaluate() |> Smith.Kino.render() |> is_struct(Kino.JS)
      true

  <div class="smith-doc-preview" data-preview="api-kino-1" data-model="blank" data-label="Piped evaluation">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  Use `Kino.render/1` to display an additional preview before the cell's
  final expression. Drag to rotate, scroll to zoom, and use the toolbar for
  fullscreen or PNG download. PNG captures the current browser canvas;
  there is no server-side image renderer.

  ## Optional dependency

  Smith must be compiled with Kino available. Otherwise this raises
  `RuntimeError` with reason `:kino_not_available`. Add `{:kino, "~> 0.19.0"}`
  to the same dependency list and rebuild Smith. In a notebook, restart the
  runtime and run `Mix.install(deps, force: true)` once if Smith was
  previously compiled without Kino.
  """
  @spec render(
          OCEx.Shape.t()
          | [{Smith.Measure.source(), Smith.Render.color()}]
          | Smith.Drawing.t()
          | {:ok, Smith.Drawing.t()}
          | Smith.Model.t()
          | Smith.Path.t()
          | Smith.Sketch.t()
          | Smith.Assembly.t()
          | Smith.Result.t()
          | Smith.Assembly.Result.t()
          | {:ok, Smith.Result.t() | Smith.Assembly.Result.t()}
          | {:error, term()},
          keyword()
        ) ::
          Kino.JS.t()
  def render(model, opts \\ []) do
    case preview(model, opts) do
      {:ok, kino} -> kino
      {:error, reason} -> raise "cannot render Smith preview: #{inspect(reason)}"
    end
  end

  defp preview({:ok, %Smith.Drawing{} = drawing}, opts), do: preview(drawing, opts)

  defp preview(%Smith.Drawing{} = drawing, opts) do
    with :ok <- available(),
         true <-
           Smith.Geometry.options(opts, [
             :label,
             :hidden,
             :tolerance,
             :angular_tolerance,
             :padding,
             :stroke_width,
             :title
           ]) and is_binary(Keyword.get(opts, :label, "Smith drawing")),
         {:ok, svg} <- Smith.Drawing.svg(drawing, Keyword.delete(opts, :label)) do
      apply(Smith.Kino.Renderer, :new, [
        %{
          svg: svg,
          label: Keyword.get(opts, :label, "Smith drawing"),
          revision: drawing.source_revision
        }
      ])
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  defp preview(layers, opts) when is_list(layers) do
    with :ok <- available(),
         :ok <- options(opts),
         {:ok, data} <- Smith.Kino.Data.build_layers(layers, opts),
         do: apply(Smith.Kino.Renderer, :new, [data])
  end

  defp preview(model, opts) do
    with :ok <- available(),
         :ok <- options(opts),
         {:ok, result} <- result(model),
         {:ok, data} <- Smith.Kino.Data.build(result, opts) do
      apply(Smith.Kino.Renderer, :new, [data])
    end
  end

  defp available do
    if Code.ensure_loaded?(Smith.Kino.Renderer), do: :ok, else: {:error, :kino_not_available}
  end

  defp result(%OCEx.Shape{} = shape), do: Smith.Geometry.snapshot(shape)
  defp result({:ok, %OCEx.Shape{} = shape}), do: Smith.Geometry.snapshot(shape)
  defp result({:ok, %Smith.Result{} = result}), do: {:ok, result}
  defp result({:ok, %Smith.Assembly.Result{} = result}), do: {:ok, result}
  defp result({:error, _} = error), do: error
  defp result(%Smith.Result{} = result), do: {:ok, result}
  defp result(%Smith.Assembly.Result{} = result), do: {:ok, result}
  defp result(model), do: Smith.evaluate(model)

  defp options(opts) when is_list(opts) do
    valid? =
      Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Enum.all?(opts, fn
          {:label, value} ->
            is_binary(value)

          {:view, value} ->
            value in [:isometric, :top, :bottom, :front, :back, :left, :right]

          {:edges, value} ->
            is_boolean(value)

          {:clip, {%Smith.Plane{} = plane, keep}} ->
            keep in [:positive, :negative] and match?({:ok, _}, Smith.Plane.frame(plane))

          {key, value} when key in [:tolerance, :angular_tolerance] ->
            is_number(value) and value > 0

          _ ->
            false
        end)

    if valid?, do: :ok, else: {:error, :invalid_options}
  end

  defp options(_), do: {:error, :invalid_options}
end

if Code.ensure_loaded?(Kino.JS) do
  defmodule Smith.Kino.Renderer do
    @moduledoc false
    use Kino.JS, assets_path: "priv/kino"
    def new(data), do: {:ok, Kino.JS.new(__MODULE__, data)}
  end
end
