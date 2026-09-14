defmodule Smith.Path do
  @moduledoc """
  An ordered, open chain of world-coordinate edge recipes.

  Use `Smith.line/2`, `Smith.arc/6`, and `Smith.spline/2` to describe
  the edges. Their directed endpoints must meet in the supplied order within
  1.0e-7 mm. Smith does not reorder or reverse them to make a connection.
  Geometry is created only when the path or a consuming sweep is evaluated.

      iex> path = Smith.Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])
      iex> {:ok, wire} = Smith.evaluate(path)
      iex> OCEx.length(wire.shape)
      {:ok, 10.0}

  <div class="smith-doc-preview" data-preview="api-path-0" data-model="wire" data-label="Straight path">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  A path evaluates to a wire, not a printable solid. Pass it to
  `Smith.sweep/3` with a placed sketch to create one. Paths do not currently
  support closed loops or automatic profile placement. A connected path can
  still self-intersect; connection checks are not a collision test.
  """
  defstruct edges: []
  @type t :: %__MODULE__{edges: [Smith.Model.t()]}

  @doc """
  Records an ordered nonempty list of edge recipes.

  Validation is deferred. Empty lists, non-edge results, disconnected edges,
  and closed paths fail when evaluated. Each edge keeps its own world placement.
  """
  @spec new([Smith.Model.t()]) :: t()
  def new(edges), do: %__MODULE__{edges: edges}

  @doc "Returns a new path with one edge recipe appended to its end."
  @spec append(t(), Smith.Model.t()) :: t()
  def append(%__MODULE__{} = path, edge), do: %{path | edges: path.edges ++ [edge]}

  @doc false
  def evaluate(%__MODULE__{edges: edges}) when is_list(edges) and edges != [] do
    Enum.reduce_while(edges, {:ok, [], nil, nil}, fn recipe, {:ok, acc, first, previous} ->
      with {:ok, result} <- Smith.evaluate(recipe),
           {:ok, info} <- OCEx.edge_info(result.shape),
           true <- previous == nil or near?(previous, info.start) do
        {:cont, {:ok, [result.shape | acc], first || info.start, info.end}}
      else
        false -> {:halt, {:error, :disconnected_path}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, edges, first, last} ->
        if near?(first, last), do: {:error, :closed_path}, else: OCEx.wire(Enum.reverse(edges))

      error ->
        error
    end
  end

  def evaluate(_), do: {:error, :invalid_path}

  defp near?({a, b, c}, {x, y, z}),
    do: (a - x) * (a - x) + (b - y) * (b - y) + (c - z) * (c - z) <= 1.0e-14
end
