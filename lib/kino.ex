defmodule Smith.Kino do
  @moduledoc """
  Interactive 3D previews for Livebook through Kino.JS.

  Add Kino alongside Smith in the notebook setup. `render/2` returns a
  tagged Kino value; unwrap it before displaying it. Each output holds an
  independent mesh snapshot with its own camera.

  The renderer and controls are Smith's JavaScript/WebGL code. Kino supplies
  Livebook's asset and data integration; OCEx supplies the mesh. Rendering
  does not use a CDN or a server-side graphics process.

  Previews support rotation, zoom, fullscreen, and PNG download. They show
  one surface color and do not provide part selection, dimensions, or
  automatic exploded assembly views. See the [Livebook guide](livebook.html)
  for stage-by-stage examples and local dependency setup.
  """

  @doc """
  Creates an interactive preview, returning `{:ok, kino}` or a tagged error.

  Accepts a model, sketch, assembly, or evaluated result. Recipes are
  evaluated on each call; passing an existing result skips that step.
  The shape is then meshed into a snapshot. Assemblies show installed
  manufactured parts only. Sketches show their faces; edge-only recipes
  have no triangle surface to display.

  ## Options

    * `:label` — toolbar text, default `"Smith preview"`.
    * `:tolerance` — linear mesh deflection in mm, default 0.03.
    * `:angular_tolerance` — angular mesh deflection in radians, default 0.5.

  Deflections must satisfy OCEx's native minimum (greater than 1.0e-7).
  Unknown or duplicate options return `:invalid_options`. Geometry and
  meshing failures are returned unchanged. The preview does not run the
  print export checks.

  ## Display in Livebook

  Unwrap the result and leave the Kino as the cell's last value:

      iex> {:ok, preview} = Smith.Kino.render(Smith.box(20, 10, 4), label: "Blank")
      iex> is_struct(preview, Kino.JS)
      true

  In a notebook, end the cell with `preview`, or pass it to
  `Kino.render/1`. Drag to rotate, scroll to zoom, and use the toolbar for
  fullscreen or PNG download. PNG captures the current browser canvas;
  there is no server-side image renderer.

  ## Optional dependency

  Smith must be compiled with Kino available. Otherwise this returns
  `{:error, :kino_not_available}`. Add `{:kino, "~> 0.19.0"}` to the
  same dependency list and rebuild Smith. In a notebook, restart the
  runtime and run `Mix.install(deps, force: true)` once if Smith was
  previously compiled without Kino.
  """
  @spec render(
          Smith.Model.t()
          | Smith.Sketch.t()
          | Smith.Assembly.t()
          | Smith.Result.t()
          | Smith.Assembly.Result.t(),
          keyword()
        ) ::
          {:ok, Kino.JS.t()} | {:error, term()}
  def render(model, opts \\ []) do
    with :ok <- available(),
         :ok <- options(opts),
         {:ok, result} <- result(model),
         {:ok, mesh} <-
           OCEx.mesh(
             result.shape,
             Keyword.get(opts, :tolerance, 0.03),
             Keyword.get(opts, :angular_tolerance, 0.5)
           ) do
      apply(Smith.Kino.Renderer, :new, [
        %{
          vertices: Enum.map(mesh.vertices, &Tuple.to_list/1),
          triangles: Enum.map(mesh.triangles, &Tuple.to_list/1),
          revision: result.revision,
          label: Keyword.get(opts, :label, "Smith preview")
        }
      ])
    end
  end

  defp available do
    if Code.ensure_loaded?(Smith.Kino.Renderer), do: :ok, else: {:error, :kino_not_available}
  end

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
