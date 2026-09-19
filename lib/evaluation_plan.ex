defmodule Smith.EvaluationPlan do
  @moduledoc false

  # Only self-contained geometry recipes may be prepared speculatively.
  # Selectors, callbacks, retained results, and unknown/future operations are
  # barriers. Keep the original indexed nodes for sequential error recovery.
  @pure_operations ~w(box cylinder cone sphere torus edge arc spline bezier polygon
    profile compound translate rotate extrude clean mirror cut fuse common)a

  def compile(operations) do
    operations
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn
      {{operation, [%Smith.Model{} = tool]}, index} when operation in [:cut, :fuse] ->
        if pure?(tool), do: operation, else: {:barrier, index}

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

  defp pure?(%Smith.Model{operations: operations}) when is_list(operations) do
    operations != [] and
      Enum.all?(operations, fn
        {operation, args} -> operation in @pure_operations and pure?(args)
        _ -> false
      end)
  end

  defp pure?(%Smith.Model{}), do: false
  defp pure?([]), do: true
  defp pure?([head | tail]), do: pure?(head) and pure?(tail)
  defp pure?(value) when is_tuple(value), do: value |> Tuple.to_list() |> pure?()
  defp pure?(value) when is_map(value), do: value |> Map.to_list() |> pure?()
  defp pure?(value), do: is_number(value) or is_atom(value) or is_binary(value)
end
