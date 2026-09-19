defmodule Smith.EvaluationPlan do
  @moduledoc false

  # Only self-contained geometry recipes may be prepared speculatively.
  # Selectors, callbacks, retained results, and unknown/future operations are
  # barriers. Keep the original indexed nodes for sequential error recovery.
  @pure_operations ~w(box cylinder cone sphere torus edge arc spline bezier polygon
    profile compound translate rotate extrude clean mirror cut fuse common)a
  @reuse_operations @pure_operations ++ [:fillet, :chamfer, :hole, :counterbore, :countersink]

  def reuse_candidates(recipe) do
    recipe
    |> count_bases(%{})
    |> Enum.filter(fn {_, count} -> count > 1 end)
    # Bound native retention even for very large assemblies. This cap affects
    # reuse only; every recipe still evaluates normally if it is not selected.
    |> Enum.take(128)
    |> MapSet.new(fn {base, _} -> base end)
  end

  def placement_base(%Smith.Model{operations: operations}) do
    {placements, source} =
      Enum.split_while(operations, fn
        {op, args} when op in [:translate, :rotate, :mirror] -> pure?(args)
        _ -> false
      end)

    {%Smith.Model{operations: source}, placements}
  end

  defp count_bases(%Smith.Model{} = model, counts) do
    {base, _} = placement_base(model)

    counts =
      if pure?(base, @reuse_operations), do: Map.update(counts, base, 1, &(&1 + 1)), else: counts

    count_bases(model.operations, counts)
  end

  defp count_bases([head | tail], counts), do: count_bases(tail, count_bases(head, counts))

  defp count_bases(value, counts) when is_tuple(value),
    do: count_bases(Tuple.to_list(value), counts)

  defp count_bases(value, counts) when is_map(value), do: count_bases(Map.values(value), counts)
  defp count_bases(_, counts), do: counts

  def compile(operations) do
    operations
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn
      {{operation, [%Smith.Model{} = tool]}, index} when operation in [:cut, :fuse] ->
        if pure?(tool), do: operation, else: {:barrier, index}

      {{operation, opts}, index} when operation in [:hole, :counterbore, :countersink] ->
        if is_list(opts) and Keyword.keyword?(opts) and match?(%Smith.Plane{}, opts[:on]) and
             pure?(opts),
           do: :independent_holes,
           else: {:barrier, index}

      {_, index} ->
        {:barrier, index}
    end)
    # Two-tool groups cost more on the measured clip than sequential cuts.
    # Reserve native batching for longer runs where repeated cleanup dominates.
    |> Enum.flat_map(fn
      [first, second] -> [[first], [second]]
      group -> [group]
    end)
  end

  defp pure?(value), do: pure?(value, @pure_operations)

  defp pure?(%Smith.Model{operations: operations}, allowed) when is_list(operations) do
    operations != [] and
      Enum.all?(operations, fn
        {operation, args} -> operation in allowed and pure?(args, allowed)
        _ -> false
      end)
  end

  defp pure?(%Smith.Model{}, _), do: false
  defp pure?([], _), do: true
  defp pure?([head | tail], allowed), do: pure?(head, allowed) and pure?(tail, allowed)
  defp pure?(value, allowed) when is_tuple(value), do: pure?(Tuple.to_list(value), allowed)
  defp pure?(value, allowed) when is_map(value), do: pure?(Map.to_list(value), allowed)
  defp pure?(value, _), do: is_number(value) or is_atom(value) or is_binary(value)
end
