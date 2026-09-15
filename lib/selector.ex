defmodule Smith.Selector do
  @moduledoc """
  Composable queries over the edges or faces of one evaluated body.

  A selector is an immutable sequence of filters. Each filter operates on
  the preceding selection; extrema retain all ties within 1.0e-7 mm.
  Queries return native handles from the supplied revision, in kernel order
  unless explicitly sorted. Sorts are stable; tied values retain their order.
  That order and those handles are not persistent names across operations.

      iex> top = Smith.Selector.type(:plane) |> Smith.Selector.facing(:z)
      iex> {:ok, body} = Smith.box(10, 8, 6) |> Smith.evaluate()
      iex> {:ok, faces} = Smith.faces(body, top)
      iex> length(faces)
      1

  <div class="smith-doc-preview" data-preview="api-selector-0" data-model="faces" data-label="Selected top face">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  Use these values in `Smith.fillet/2`, `Smith.chamfer/2`, or
  `Smith.shell/2` to resolve a selection at that recipe step.
  `Smith.edges/2` and `Smith.faces/2` inspect an already evaluated result.
  Queries may return an empty list. Features requiring geometry reject an
  empty selection, and their optional `:count` guards against ambiguity.
  """
  import Kernel, except: [length: 1]

  defstruct steps: []
  @opaque t :: %__MODULE__{steps: list()}
  @type axis :: :x | :y | :z
  @type input :: t() | :all | {:parallel, axis()} | (map() -> boolean())

  @doc "Returns a selector containing no filters; it selects every candidate."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Retains a geometry type reported by OCEx.

  Edge types are `:line`, `:circle`, and `:other`. Face types are
  `:plane`, `:cylinder`, `:sphere`, and `:other`. Splines fall under
  `:other`. A valid type absent from the candidates selects nothing.
  """
  @spec type(t(), atom()) :: t()
  def type(selector \\ new(), kind), do: append(selector, {:type, kind})

  @doc """
  Retains straight edges parallel to a world axis, ignoring direction sign.

  On faces it retains planes whose normals are parallel to that axis.
  Curved edges and surfaces do not match. Alignment uses a unit-vector
  component threshold of 1 - 1.0e-9.
  """
  @spec parallel(t(), axis()) :: t()
  def parallel(selector \\ new(), axis), do: append(selector, {:parallel, axis})

  @doc """
  Retains planar faces facing a signed world axis.

  Accepts `:x`, `:y`, `:z` for positive directions or
  `{:x, :negative}` (and corresponding Y/Z tuples). Uses oriented face
  normals and a unit-vector component threshold of 1 - 1.0e-9.
  This filter is invalid for an edge query.
  """
  @spec facing(t(), axis() | {axis(), :negative}) :: t()
  def facing(selector \\ new(), axis), do: append(selector, {:facing, axis})

  @doc """
  Keeps candidates with the greatest center coordinate along a world axis.

  Faces use their area centroid; edges use their curve parameter midpoint,
  which need not be halfway along arc length. This is not a bounding-box
  extremum. All ties within 1.0e-7 mm are retained; empty input stays empty.
  """
  @spec at_max(t(), axis()) :: t()
  def at_max(selector \\ new(), axis), do: append(selector, {:extreme, axis, :max})

  @doc "Keeps the least center coordinate, with the same rules as `at_max/2`."
  @spec at_min(t(), axis()) :: t()
  def at_min(selector \\ new(), axis), do: append(selector, {:extreme, axis, :min})

  @doc """
  Filters candidates using a boolean predicate over geometry metadata.

  Edge metadata is `OCEx.edge_info/1` plus `:bounds` and `:midpoint`.
  A degenerate edge with no tangent uses its endpoint as the midpoint.
  Face metadata is `OCEx.face_info/1` plus `:bounds`. Coordinates are world
  coordinates. Returning anything except a boolean produces
  `:invalid_selector_result`; exceptions from the predicate propagate.
  """
  @spec where(t(), (map() -> boolean())) :: t()
  def where(selector \\ new(), predicate), do: append(selector, {:where, predicate})

  @type measurement :: non_neg_integer() | float() | {number(), number()}
  @type property :: :length | :area | :radius | axis()

  @doc "Matches length using the default tolerance; see `length/3`."
  @spec length(measurement()) :: t()
  def length(value), do: length(new(), value, [])
  @doc "Matches length in a pipeline, or accepts a value and options; see `length/3`."
  @spec length(t() | measurement(), measurement() | keyword()) :: t()
  def length(%__MODULE__{} = selector, value), do: length(selector, value, [])
  def length(value, opts), do: length(new(), value, opts)

  @doc """
  Retains edges whose length matches a value or inclusive `{minimum, maximum}` range.

  Accepts `tolerance:` (default 1.0e-7 mm), applied to equality and both
  range endpoints. Measurements and tolerance must be nonnegative; ranges
  must be ordered. Invalid arguments fail when the selector is evaluated.
  Length filters are invalid for face queries.
  """
  @spec length(t(), measurement(), keyword()) :: t()
  def length(selector, value, opts), do: append(selector, {:measure, :length, value, opts})

  @doc "Matches area using the default tolerance; see `area/3`."
  @spec area(measurement()) :: t()
  def area(value), do: area(new(), value, [])
  @doc "Matches area in a pipeline, or accepts a value and options; see `area/3`."
  @spec area(t() | measurement(), measurement() | keyword()) :: t()
  def area(%__MODULE__{} = selector, value), do: area(selector, value, [])
  def area(value, opts), do: area(new(), value, opts)

  @doc """
  Retains faces by area in mm², using the value/range rules of `length/3`.

  The default tolerance is 1.0e-7 mm². Invalid for edge queries.
  """
  @spec area(t(), measurement(), keyword()) :: t()
  def area(selector, value, opts), do: append(selector, {:measure, :area, value, opts})

  @doc "Matches radius using the default tolerance; see `radius/3`."
  @spec radius(measurement()) :: t()
  def radius(value), do: radius(new(), value, [])
  @doc "Matches radius in a pipeline, or accepts a value and options; see `radius/3`."
  @spec radius(t() | measurement(), measurement() | keyword()) :: t()
  def radius(%__MODULE__{} = selector, value), do: radius(selector, value, [])
  def radius(value, opts), do: radius(new(), value, opts)

  @doc """
  Retains circular edges or cylindrical/spherical faces by radius in mm.

  Uses the value/range rules of `length/3`. Candidates without a reported
  radius are excluded; they are never treated as radius zero.
  """
  @spec radius(t(), measurement(), keyword()) :: t()
  def radius(selector, value, opts), do: append(selector, {:measure, :radius, value, opts})

  @doc """
  Sorts candidates by `:length`, `:area`, `:radius`, or a world axis.

  Length is valid only for edges, area only for faces. Axis values use the
  same centers as `at_max/2`. Order is `:asc` (default) or `:desc`.
  Equal values retain their preceding order. Missing radii come last in
  either direction. Sorting does not imply persistent topology identity.
  """
  @spec sort_by(t(), property(), :asc | :desc) :: t()
  def sort_by(selector, property, order), do: append(selector, {:sort, property, order})

  @doc "Sorts ascending by a property; see `sort_by/3`."
  @spec sort_by(property()) :: t()
  def sort_by(property), do: sort_by(new(), property, :asc)

  @doc "Sorts a pipeline ascending, or accepts a property and order; see `sort_by/3`."
  @spec sort_by(t() | property(), property() | :asc | :desc) :: t()
  def sort_by(%__MODULE__{} = selector, property), do: sort_by(selector, property, :asc)
  def sort_by(property, order), do: sort_by(new(), property, order)

  @doc """
  Keeps the first nonnegative integer number of candidates in the current order.

  Zero selects nothing; a count larger than the selection retains everything.
  Use after `sort_by/3` to choose the smallest or largest items. This can
  discard ties; use extrema when every tied candidate should be retained.
  """
  @spec take(t(), non_neg_integer()) :: t()
  def take(selector \\ new(), count), do: append(selector, {:take, count})

  @doc """
  Retains the union of queries evaluated against the preceding selection.

  Accepts a list of selector inputs, including predicates and `:all`.
  Each branch starts from the same current candidates. Output preserves
  their preceding order and contains no duplicates, regardless of branch
  sorting or overlap. An empty list selects nothing. Pipeline ordinary
  filters to express intersection.
  """
  @spec any_of(t(), [input()]) :: t()
  def any_of(selector \\ new(), queries), do: append(selector, {:any, queries})

  @doc """
  Removes candidates matched by a query against the preceding selection.

  Preserves the order of surviving candidates. Nested selectors obey the
  same validation and callback rules as a top-level query.
  """
  @spec exclude(t(), input()) :: t()
  def exclude(selector \\ new(), query), do: append(selector, {:exclude, query})

  defp append(%__MODULE__{} = selector, step), do: %{selector | steps: selector.steps ++ [step]}

  @doc false
  def select(body, kind, :all) when kind in [:edges, :faces], do: apply(OCEx, kind, [body])

  def select(body, kind, input) when kind in [:edges, :faces] do
    with {:ok, candidates} <- query(body, kind, input, false),
         do: {:ok, Enum.map(candidates, &elem(&1, 0))}
  end

  @doc false
  def inspect(body, kind, input) do
    with {:ok, candidates} <- query(body, kind, input, true),
         do: {:ok, Enum.map(candidates, fn {shape, info} -> Map.put(info, :shape, shape) end)}
  end

  defp query(body, kind, input, detailed?) do
    with {:ok, steps} <- steps(input),
         true <- Enum.all?(steps, &valid?(&1, kind)),
         {:ok, shapes} <- apply(OCEx, kind, [body]),
         metadata_steps = if(detailed?, do: [{:where, nil} | steps], else: steps),
         {:ok, candidates} <- describe(shapes, kind, metadata_steps) do
      run(candidates, steps)
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  defp run(candidates, steps) do
    Enum.reduce_while(steps, {:ok, candidates}, fn step, {:ok, current} ->
      case filter(current, step) do
        {:ok, selected} -> {:cont, {:ok, selected}}
        error -> {:halt, error}
      end
    end)
  end

  defp steps(%__MODULE__{steps: steps}) when is_list(steps), do: {:ok, steps}
  defp steps({:parallel, axis}), do: {:ok, [{:parallel, axis}]}
  defp steps(predicate) when is_function(predicate, 1), do: {:ok, [{:where, predicate}]}
  defp steps(:all), do: {:ok, []}
  defp steps(_), do: {:error, :invalid_options}
  defp valid?({:type, type}, _), do: type in [:line, :circle, :plane, :cylinder, :sphere, :other]
  defp valid?({:parallel, axis}, _), do: axis in [:x, :y, :z]
  defp valid?({:facing, {axis, :negative}}, :faces), do: axis in [:x, :y, :z]
  defp valid?({:facing, axis}, :faces), do: axis in [:x, :y, :z]
  defp valid?({:extreme, axis, order}, _), do: axis in [:x, :y, :z] and order in [:min, :max]
  defp valid?({:where, predicate}, _), do: is_function(predicate, 1)

  defp valid?({:measure, property, value, opts}, kind),
    do:
      property?(property, kind) and measurement?(value) and
        Smith.Plane.keywords?(opts, [:tolerance]) and
        is_number(Keyword.get(opts, :tolerance, 1.0e-7)) and
        Keyword.get(opts, :tolerance, 1.0e-7) >= 0

  defp valid?({:sort, property, order}, kind),
    do: property?(property, kind) and order in [:asc, :desc]

  defp valid?({:take, count}, _), do: is_integer(count) and count >= 0

  defp valid?({:any, queries}, kind) when is_list(queries),
    do: Enum.all?(queries, &query_valid?(&1, kind))

  defp valid?({:exclude, query}, kind), do: query_valid?(query, kind)
  defp valid?(_, _), do: false

  defp property?(:length, :edges), do: true
  defp property?(:area, :faces), do: true
  defp property?(property, _), do: property in [:radius, :x, :y, :z]

  defp measurement?({low, high}),
    do: is_number(low) and is_number(high) and low >= 0 and high >= low

  defp measurement?(value), do: is_number(value) and value >= 0

  defp query_valid?(input, kind) do
    case steps(input) do
      {:ok, steps} -> Enum.all?(steps, &valid?(&1, kind))
      _ -> false
    end
  end

  defp flatten_steps(steps) do
    Enum.flat_map(steps, fn
      {:any, queries} ->
        Enum.flat_map(queries, fn query ->
          {:ok, nested} = steps(query)
          flatten_steps(nested)
        end)

      {:exclude, query} ->
        {:ok, nested} = steps(query)
        flatten_steps(nested)

      step ->
        [step]
    end)
  end

  defp describe(shapes, kind, steps) do
    steps = flatten_steps(steps)
    bounds? = Enum.any?(steps, &match?({:where, _}, &1))

    midpoint? =
      bounds? or
        Enum.any?(
          steps,
          &(match?({:extreme, _, _}, &1) or match?({:sort, axis, _} when axis in [:x, :y, :z], &1))
        )

    Enum.reduce_while(shapes, {:ok, []}, fn shape, {:ok, acc} ->
      with {:ok, info} <- metadata(shape, kind, midpoint?),
           {:ok, info} <- with_bounds(shape, info, bounds?) do
        {:cont, {:ok, [{shape, info} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, candidates} -> {:ok, Enum.reverse(candidates)}
      error -> error
    end
  end

  defp with_bounds(_, info, false), do: {:ok, info}

  defp with_bounds(shape, info, true) do
    with {:ok, bounds} <- OCEx.bounds(shape), do: {:ok, Map.put(info, :bounds, bounds)}
  end

  defp metadata(shape, :faces, _), do: OCEx.face_info(shape)
  defp metadata(shape, :edges, false), do: OCEx.edge_info(shape)

  defp metadata(shape, :edges, true) do
    with {:ok, info} <- OCEx.edge_info(shape),
         {:ok, midpoint} <- midpoint(shape, info),
         do: {:ok, Map.put(info, :midpoint, midpoint)}
  end

  defp midpoint(shape, info) do
    case OCEx.edge_sample(shape, 0.5) do
      {:ok, sample} -> {:ok, sample.point}
      {:error, :undefined_tangent} when info.length <= 1.0e-7 -> {:ok, info.start}
      error -> error
    end
  end

  defp filter(candidates, {:take, count}), do: {:ok, Enum.take(candidates, count)}

  defp filter(candidates, {:sort, property, order}) do
    {known, missing} =
      Enum.split_with(candidates, fn {_, info} -> value(info, property) != nil end)

    {:ok, Enum.sort_by(known, fn {_, info} -> value(info, property) end, order) ++ missing}
  end

  defp filter(candidates, {:any, queries}) do
    Enum.reduce_while(queries, {:ok, MapSet.new()}, fn query, {:ok, selected} ->
      {:ok, steps} = steps(query)

      case run(candidates, steps) do
        {:ok, branch} -> {:cont, {:ok, MapSet.union(selected, MapSet.new(branch))}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, selected} -> {:ok, Enum.filter(candidates, &MapSet.member?(selected, &1))}
      error -> error
    end
  end

  defp filter(candidates, {:exclude, query}) do
    {:ok, steps} = steps(query)

    with {:ok, excluded} <- run(candidates, steps) do
      excluded = MapSet.new(excluded)
      {:ok, Enum.reject(candidates, &MapSet.member?(excluded, &1))}
    end
  end

  defp filter([], {:extreme, _, _}), do: {:ok, []}

  defp filter(candidates, {:extreme, axis, order}) do
    coordinate = fn {_, info} -> elem(info[:midpoint] || info[:center], index(axis)) end
    values = Enum.map(candidates, coordinate)
    limit = if order == :max, do: Enum.max(values), else: Enum.min(values)
    {:ok, Enum.filter(candidates, &(abs(coordinate.(&1) - limit) <= 1.0e-7))}
  end

  defp filter(candidates, step) do
    Enum.reduce_while(candidates, {:ok, []}, fn {_, info} = candidate, {:ok, acc} ->
      case matches?(info, step) do
        true -> {:cont, {:ok, [candidate | acc]}}
        false -> {:cont, {:ok, acc}}
        _ -> {:halt, {:error, :invalid_selector_result}}
      end
    end)
    |> case do
      {:ok, selected} -> {:ok, Enum.reverse(selected)}
      error -> error
    end
  end

  defp matches?(info, {:measure, property, expected, opts}) do
    actual = value(info, property)
    tolerance = Keyword.get(opts, :tolerance, 1.0e-7)
    {low, high} = if is_tuple(expected), do: expected, else: {expected, expected}
    is_number(actual) and actual >= low - tolerance and actual <= high + tolerance
  end

  defp matches?(info, {:type, type}), do: info.type == type
  defp matches?(info, {:where, predicate}), do: predicate.(info)

  defp matches?(info, {:parallel, axis}) do
    direction = Map.get(info, :direction, info[:normal])
    direction != nil and abs(elem(direction, index(axis))) > 1 - 1.0e-9
  end

  defp matches?(info, {:facing, {axis, :negative}}), do: facing?(info, axis, -1)
  defp matches?(info, {:facing, axis}), do: facing?(info, axis, 1)

  defp facing?(info, axis, sign),
    do: info.normal != nil and sign * elem(info.normal, index(axis)) > 1 - 1.0e-9

  defp value(info, axis) when axis in [:x, :y, :z],
    do: elem(info[:midpoint] || info[:center], index(axis))

  defp value(info, property), do: Map.get(info, property)

  defp index(:x), do: 0
  defp index(:y), do: 1
  defp index(:z), do: 2
end
