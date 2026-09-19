defmodule Smith.EvaluationCache do
  @moduledoc false
  @key {__MODULE__, :scope}

  # A scope belongs to this evaluation, not the process lifetime. Reentrant
  # evaluations (including those invoked by callbacks) receive separate scopes.
  def with_scope(recipe, fun) do
    previous = Process.get(@key, :absent)
    candidates = Smith.EvaluationPlan.reuse_candidates(recipe)
    Process.put(@key, {candidates, %{}})

    try do
      fun.()
    after
      if previous == :absent, do: Process.delete(@key), else: Process.put(@key, previous)
    end
  end

  def candidate?(recipe) do
    case Process.get(@key) do
      {candidates, _} -> MapSet.member?(candidates, recipe)
      _ -> false
    end
  end

  def fetch(recipe, fun) do
    {_, values} = Process.get(@key)

    case Map.fetch(values, recipe) do
      {:ok, shape} ->
        {:ok, shape}

      :error ->
        case fun.() do
          {:ok, shape} = result ->
            {candidates, values} = Process.get(@key)
            Process.put(@key, {candidates, Map.put(values, recipe, shape)})
            result

          error ->
            error
        end
    end
  end
end
