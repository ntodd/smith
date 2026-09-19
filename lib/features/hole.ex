defmodule Smith.Features.Hole do
  @moduledoc """
  Native evaluation of Smith's hole recipes.

  This module implements `Smith.hole/2`, `Smith.counterbore/2`, and
  `Smith.countersink/2`. Use those functions to build deferred recipes.
  The evaluator works on an already constructed OCEx shape and returns
  another shape; it does not create a `Smith.Model` or assign a recipe
  step number. It is an implementation module rather than a separate
  modeling interface.

  Placement is resolved against the incoming body. A pilot cut and its
  recess share that entry location, so cutting the pilot cannot move the
  recess when `on: :top` uses a face centroid. Every cut must remove
  material. OCEx operations preserve the incoming body's geometry.
  """
  alias Smith.Plane

  @doc """
  Evaluates one hole feature on an OCEx body.

  `kind` is `:hole`, `:counterbore`, or `:countersink`; `opts` uses
  the corresponding public Smith function's documented options. Returns
  `{:ok, shape}` or `{:error, reason}`. Option and geometry failures are
  returned without a `Smith.Error` wrapper; the recipe evaluator adds
  its operation and step context.

  Through-all cutters span a projected enclosing box with a 1 mm margin
  at each end. Finite cutters start at the entry plane and extend into its
  negative normal. Material removal must exceed 1.0e-9 mm³ for each cut;
  otherwise the reason is `:hole_misses_body` or `:recess_misses_body`.
  """
  @spec evaluate(OCEx.Shape.t(), :hole | :counterbore | :countersink, keyword()) ::
          {:ok, OCEx.Shape.t()} | {:error, atom()}
  def evaluate(body, kind, opts) do
    with {:ok, result, _bounds} <- evaluate(body, kind, opts, nil), do: {:ok, result}
  end

  # The recipe evaluator retains this envelope only across hole features.
  # Subtraction cannot extend it. Face selection still uses the current body.
  @doc false
  def evaluate(body, kind, opts, bounds) do
    with :ok <- validate(kind, opts),
         {:ok, tool, bounds} <- pilot(body, opts, bounds),
         {:ok, drilled} <- remove(body, tool, :hole_misses_body),
         {:ok, result} <- recess(drilled, body, kind, opts),
         do: {:ok, result, bounds}
  end

  # Only explicit-plane features reach this path. Prove that their complete
  # cutter envelopes are disjoint before validating them against the same body.
  # Any uncertainty or failure sends the original nodes back to sequential
  # evaluation, preserving per-feature errors and their original indices.
  @doc false
  def evaluate_batch(body, features, bounds) do
    if Code.ensure_loaded?(OCEx) and function_exported?(OCEx, :cut_many, 2) do
      with {:ok, prepared, bounds} <- prepare_batch(body, features, bounds),
           true <- independent?(prepared),
           :ok <- check_batch(body, prepared),
           tools =
             Enum.flat_map(prepared, fn {pilot, recess, _} ->
               if recess, do: [pilot, recess], else: [pilot]
             end),
           {:ok, result} <- apply(OCEx, :cut_many, [body, tools]),
           do: {:ok, result, bounds}
    else
      :sequential
    end
  end

  defp prepare_batch(body, features, bounds) do
    Enum.reduce_while(features, {:ok, [], bounds}, fn {kind, opts}, {:ok, acc, bounds} ->
      with :ok <- validate(kind, opts),
           {:ok, pilot, bounds} <- pilot(body, opts, bounds),
           {:ok, recess} <- prepared_recess(body, kind, opts),
           {:ok, box} <- cutter_bounds(pilot, recess) do
        {:cont, {:ok, acc ++ [{pilot, recess, box}], bounds}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp prepared_recess(_, :hole, _), do: {:ok, nil}

  defp prepared_recess(body, kind, opts) do
    with {:ok, frame} <- entry(body, opts),
         {:ok, tool, depth} <- recess_tool(kind, opts),
         do: below(tool, frame, depth)
  end

  defp cutter_bounds(pilot, nil), do: envelope(pilot, nil)

  defp cutter_bounds(pilot, recess) do
    with {:ok, {a, b}} <- envelope(pilot, nil),
         {:ok, {c, d}} <- envelope(recess, nil) do
      low = for i <- 0..2, do: min(elem(a, i), elem(c, i))
      high = for i <- 0..2, do: max(elem(b, i), elem(d, i))
      {:ok, {List.to_tuple(low), List.to_tuple(high)}}
    end
  end

  defp independent?([]), do: true

  defp independent?([{_, _, {low, high}} | rest]) do
    Enum.all?(rest, fn {_, _, {other_low, other_high}} ->
      Enum.any?(0..2, fn i ->
        elem(high, i) < elem(other_low, i) or elem(other_high, i) < elem(low, i)
      end)
    end) and independent?(rest)
  end

  defp check_batch(body, prepared) do
    Enum.reduce_while(prepared, :ok, fn {pilot, recess, _}, :ok ->
      with {:ok, removed} <- OCEx.common(body, pilot),
           {:ok, volume} when volume > 1.0e-9 <- OCEx.volume(removed),
           :ok <- check_recess(body, pilot, recess) do
        {:cont, :ok}
      else
        _ -> {:halt, :sequential}
      end
    end)
  end

  defp check_recess(_, _, nil), do: :ok

  defp check_recess(body, pilot, recess) do
    with {:ok, region} <- OCEx.common(body, recess),
         {:ok, added} <- OCEx.cut(region, pilot),
         {:ok, volume} when volume > 1.0e-9 <- OCEx.volume(added),
         do: :ok
  end

  defp validate(kind, opts) do
    extra =
      case kind do
        :hole -> []
        :counterbore -> [:bore_diameter, :bore_depth]
        :countersink -> [:sink_diameter, :angle]
      end

    with true <- Plane.keywords?(opts, [:on, :diameter, :through, :depth, :at] ++ extra),
         true <- opts[:on] == :top or match?(%Plane{}, opts[:on]),
         true <- positive?(opts[:diameter]),
         {x, y} when is_number(x) and is_number(y) <- Keyword.get(opts, :at, {0, 0}),
         true <- extent?(opts),
         true <- recess_options?(kind, opts) do
      :ok
    else
      _ -> {:error, :invalid_options}
    end
  end

  defp positive?(value), do: is_number(value) and value > 0

  defp extent?(opts) do
    case {Keyword.has_key?(opts, :through), Keyword.has_key?(opts, :depth)} do
      {true, false} -> opts[:through] == :all
      {false, true} -> positive?(opts[:depth])
      _ -> false
    end
  end

  defp recess_options?(:hole, _), do: true

  defp recess_options?(:counterbore, opts),
    do:
      positive?(opts[:bore_diameter]) and opts[:bore_diameter] > opts[:diameter] and
        positive?(opts[:bore_depth]) and fits?(opts[:bore_depth], opts)

  defp recess_options?(:countersink, opts) do
    angle = Keyword.get(opts, :angle, 90)

    positive?(opts[:sink_diameter]) and opts[:sink_diameter] > opts[:diameter] and
      is_number(angle) and angle > 0 and angle < 180 and fits?(sink_depth(opts), opts)
  end

  defp fits?(recess_depth, opts),
    do: opts[:through] == :all or recess_depth <= opts[:depth]

  defp sink_depth(opts),
    do:
      (opts[:sink_diameter] - opts[:diameter]) / 2 /
        :math.tan(Keyword.get(opts, :angle, 90) * :math.pi() / 360)

  defp pilot(body, opts, bounds) do
    if opts[:through] == :all do
      hole_tool(body, opts, bounds)
    else
      with {:ok, frame} <- entry(body, opts),
           {:ok, tool} <- OCEx.cylinder(opts[:diameter] / 2, opts[:depth]),
           {:ok, tool} <- below(tool, frame, opts[:depth]),
           do: {:ok, tool, bounds}
    end
  end

  defp recess(drilled, _, :hole, _), do: {:ok, drilled}

  defp recess(drilled, original, kind, opts) do
    with {:ok, frame} <- entry(original, opts),
         {:ok, tool, depth} <- recess_tool(kind, opts),
         {:ok, tool} <- below(tool, frame, depth),
         do: remove(drilled, tool, :recess_misses_body)
  end

  defp recess_tool(:counterbore, opts) do
    with {:ok, tool} <- OCEx.cylinder(opts[:bore_diameter] / 2, opts[:bore_depth]),
         do: {:ok, tool, opts[:bore_depth]}
  end

  defp recess_tool(:countersink, opts) do
    depth = sink_depth(opts)

    with {:ok, tool} <- OCEx.cone(opts[:diameter] / 2, opts[:sink_diameter] / 2, depth),
         do: {:ok, tool, depth}
  end

  defp entry(body, opts) do
    if opts[:on] == :top do
      with {:ok, face} <- top_face(body),
           {:ok, frame} <- Plane.frame(Plane.xy(origin: face.center)),
           do: {:ok, %{frame | origin: Plane.point(frame, Keyword.get(opts, :at, {0, 0}))}}
    else
      with {:ok, frame} <- Plane.frame(opts[:on]),
           do: {:ok, %{frame | origin: Plane.point(frame, Keyword.get(opts, :at, {0, 0}))}}
    end
  end

  defp below(tool, frame, depth),
    do:
      Plane.place(tool, %{frame | origin: Plane.add(frame.origin, Plane.scale(frame.n, -depth))})

  defp remove(body, tool, reason) do
    # Measure only the removed region. Integrating the two entire bodies
    # repeats expensive curved-surface work and subtracts nearly equal masses.
    # Keep the same native validity checks, integration accuracy and threshold.
    with {:ok, result, removed_volume} <- cut_removed(body, tool) do
      if removed_volume > 1.0e-9, do: {:ok, result}, else: {:error, reason}
    end
  end

  defp cut_removed(body, tool) do
    if Code.ensure_loaded?(OCEx.Internal) and function_exported?(OCEx.Internal, :cut_removed, 2) do
      apply(OCEx.Internal, :cut_removed, [body, tool])
    else
      with {:ok, result} <- OCEx.cut(body, tool),
           {:ok, removed} <- OCEx.common(body, tool),
           {:ok, volume} <- OCEx.volume(removed),
           do: {:ok, result, volume}
    end
  end

  defp envelope(body, nil) do
    # Exact extrema are unnecessary for cutter reach. Older OCEx releases
    # retain the precise-bounds path without changing recipe behavior.
    if Code.ensure_loaded?(OCEx.Internal) and function_exported?(OCEx.Internal, :envelope, 1),
      do: apply(OCEx.Internal, :envelope, [body]),
      else: OCEx.bounds(body)
  end

  defp envelope(body, bounds) do
    # Complete removal must still report the same empty-shape failure that
    # measuring the current body's bounds would report.
    case OCEx.vertices(body) do
      {:ok, []} -> {:error, :empty_shape}
      {:ok, [_ | _]} -> {:ok, bounds}
      error -> error
    end
  end

  defp hole_tool(body, opts, bounds) do
    if opts[:on] == :top do
      with {:ok, face} <- top_face(body),
           {:ok, {{_, _, bottom}, {_, _, top}} = bounds} <- envelope(body, bounds),
           {:ok, tool} <- OCEx.cylinder(opts[:diameter] / 2, top - bottom + 2),
           {cx, cy, _} = face.center,
           {dx, dy} = Keyword.get(opts, :at, {0, 0}),
           {:ok, tool} <- OCEx.translate(tool, {cx + dx, cy + dy, bottom - 1}),
           do: {:ok, tool, bounds}
    else
      alias Smith.Plane

      with {:ok, frame} <- Plane.frame(opts[:on]),
           {:ok, {low, high} = bounds} <- envelope(body, bounds) do
        center = Plane.point(frame, Keyword.get(opts, :at, {0, 0}))

        distances =
          for x <- [elem(low, 0), elem(high, 0)],
              y <- [elem(low, 1), elem(high, 1)],
              z <- [elem(low, 2), elem(high, 2)],
              do: Plane.dot(Plane.sub({x, y, z}, center), frame.n)

        bottom = Enum.min(distances) - 1
        height = Enum.max(distances) + 1 - bottom

        with {:ok, tool} <- OCEx.cylinder(opts[:diameter] / 2, height),
             {:ok, tool} <-
               Plane.place(tool, %{
                 frame
                 | origin: Plane.add(center, Plane.scale(frame.n, bottom))
               }),
             do: {:ok, tool, bounds}
      end
    end
  end

  defp top_face(body) do
    selector = Smith.Selector.facing(:z) |> Smith.Selector.at_max(:z)

    case Smith.Selector.select(body, :faces, selector) do
      {:ok, [face]} -> OCEx.face_info(face)
      {:ok, []} -> {:error, :no_top_face}
      {:ok, _} -> {:error, :ambiguous_top_face}
      error -> error
    end
  end
end
