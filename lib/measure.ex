defmodule Smith.Measure do
  @moduledoc """
  Dimensions measured from evaluated geometry, with world-space anchors.

  Measurements retain the source BREP revision, units, and the points used to
  locate them on a drawing. They do not drive the model or implement sketch
  constraints. Selectors must resolve to exactly one edge or face: an empty
  selection returns `:empty_selection`, multiple matches `:ambiguous_selection`.
  Use `Smith.inspect_edges/2` and `Smith.inspect_faces/2` to refine a selector.

  Sources may be recipes, evaluated results, or native subshapes. Existing
  results have their revision checked. Native geometry errors propagate.
  See [inspection and validation](inspection.html) for reports and drawings.
  """
  alias Smith.{Geometry, Selector}
  defstruct [:kind, :value, :unit, :points, :axis, :normal, :source_revision]
  @type source :: Smith.Drawing.source() | OCEx.Shape.t()
  @type anchor :: {:circle_center | :edge_start | :edge_end | :face_center, Selector.input()}
  @opaque t :: %__MODULE__{
            kind: atom(),
            value: number(),
            unit: :mm | :degrees,
            points: [OCEx.point3()],
            axis: atom() | nil,
            normal: OCEx.point3() | nil,
            source_revision: String.t()
          }

  @doc """
  Measures world-axis extent (`:x`, `:y`, or `:z`) from native bounds.

  Returns a linear measurement. Its anchors lie on the bounding envelope,
  not necessarily on a surface. Curved bounds are numerical; use a tolerance
  when checking them. Empty geometry returns `:empty_shape`.
  """
  @spec extent(source(), :x | :y | :z) :: {:ok, t()} | {:error, term()}
  def extent(source, axis) when axis in [:x, :y, :z] do
    with {:ok, result} <- Geometry.result(source),
         {:ok, {low, high}} <- OCEx.bounds(result.shape) do
      index = axis_index(axis)

      finish(
        result,
        :linear,
        elem(high, index) - elem(low, index),
        [low, put_elem(low, index, elem(high, index))],
        axis
      )
    end
  end

  def extent(_, _), do: {:error, :invalid_axis}

  @doc """
  Measures distance between two geometry anchors.

  Anchors are `{:circle_center, edge_selector}`, `{:edge_start, edge_selector}`,
  `{:edge_end, edge_selector}`, or `{:face_center, face_selector}`. A face center
  is its area centroid and may not lie on a curved or concave face. Circle
  centers also work for circular arcs; they are not arc centroids.

  `axis: :aligned` (default) measures Euclidean distance; `:x`, `:y`, or `:z`
  measures the absolute world-axis component. Unknown or duplicate options
  return `:invalid_options`. Unsupported anchor geometry returns
  `:wrong_geometry_type`. Arbitrary input coordinates are not measured features.
  """
  @spec distance(source(), anchor(), anchor(), keyword()) :: {:ok, t()} | {:error, term()}
  def distance(source, from, to, opts \\ []) do
    axis = if is_list(opts) and Keyword.keyword?(opts), do: Keyword.get(opts, :axis, :aligned)

    with true <- Geometry.options(opts, [:axis]) and axis in [:aligned, :x, :y, :z],
         {:ok, result} <- Geometry.result(source),
         {:ok, a} <- anchor(result, from),
         {:ok, b} <- anchor(result, to) do
      delta = Geometry.vector(b, a)

      value =
        if axis == :aligned, do: Geometry.norm(delta), else: abs(elem(delta, axis_index(axis)))

      finish(result, :linear, value, [a, b], axis)
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  @doc "Measures a selected circular edge's radius in mm, retaining its center, radial point, and axis."
  @spec radius(source(), Selector.input()) :: {:ok, t()} | {:error, term()}
  def radius(source, selector), do: circular(source, selector, :radius)

  @doc "Measures a selected circular edge's diameter in mm, including opposite radial anchors and its axis."
  @spec diameter(source(), Selector.input()) :: {:ok, t()} | {:error, term()}
  def diameter(source, selector), do: circular(source, selector, :diameter)

  @doc """
  Measures the angle between two straight edges, in degrees from 0 through 180.

  Uses the edges' directed traversal vectors. Reversing one edge changes the
  angle to its supplement. Parallel edges are measurable but cannot produce
  a nondegenerate angular drawing annotation. The edges need not intersect;
  the annotation uses their directions at the first edge's starting point.
  """
  @spec angle(source(), Selector.input(), Selector.input()) :: {:ok, t()} | {:error, term()}
  def angle(source, first, second) do
    with {:ok, result} <- Geometry.result(source),
         {:ok, a} <- edge(result, first),
         {:ok, b} <- edge(result, second),
         true <- a.type == :line and b.type == :line do
      value =
        :math.acos(max(-1.0, min(1.0, Geometry.dot(a.direction, b.direction)))) * 180 / :math.pi()

      {:ok,
       %__MODULE__{
         kind: :angle,
         value: value,
         unit: :degrees,
         points: [a.start, Geometry.add(a.start, a.direction), Geometry.add(a.start, b.direction)],
         source_revision: result.revision
       }}
    else
      false -> {:error, :wrong_geometry_type}
      error -> error
    end
  end

  defp circular(source, selector, kind) do
    with {:ok, result} <- Geometry.result(source),
         {:ok, info} <- edge(result, selector),
         true <- info.type == :circle do
      points =
        if kind == :radius,
          do: [info.center, info.start],
          else: [Geometry.add(info.center, Geometry.vector(info.center, info.start)), info.start]

      {:ok,
       %__MODULE__{
         kind: kind,
         value: info.radius * if(kind == :diameter, do: 2, else: 1),
         unit: :mm,
         points: points,
         normal: info.axis,
         source_revision: result.revision
       }}
    else
      false -> {:error, :wrong_geometry_type}
      error -> error
    end
  end

  defp anchor(result, {:face_center, selector}) do
    with {:ok, shapes} <- Selector.select(result.shape, :faces, selector),
         {:ok, shape} <- one(shapes),
         {:ok, info} <- OCEx.face_info(shape),
         do: {:ok, info.center}
  end

  defp anchor(result, {kind, selector}) when kind in [:circle_center, :edge_start, :edge_end] do
    with {:ok, info} <- edge(result, selector) do
      case kind do
        :circle_center when info.type == :circle -> {:ok, info.center}
        :edge_start -> {:ok, info.start}
        :edge_end -> {:ok, info.end}
        _ -> {:error, :wrong_geometry_type}
      end
    end
  end

  defp anchor(_, _), do: {:error, :invalid_anchor}

  defp edge(result, selector) do
    with {:ok, edges} <- Selector.select(result.shape, :edges, selector),
         {:ok, edge} <- one(edges),
         do: OCEx.edge_info(edge)
  end

  defp one([]), do: {:error, :empty_selection}
  defp one([shape]), do: {:ok, shape}
  defp one(_), do: {:error, :ambiguous_selection}
  defp axis_index(:x), do: 0
  defp axis_index(:y), do: 1
  defp axis_index(:z), do: 2

  defp finish(result, kind, value, points, axis),
    do:
      {:ok,
       %__MODULE__{
         kind: kind,
         value: value,
         unit: :mm,
         points: points,
         axis: axis,
         source_revision: result.revision
       }}
end
