# Wall-time tracing identifies native call categories; do not use traced runs as benchmarks.
for path <- ["models/plant_stand.exs", "models/deck_clip.exs"] do
  {:__block__, _, forms} = path |> File.read!() |> Code.string_to_quoted!()
  Code.compile_quoted({:__block__, [], Enum.filter(forms, &match?({:defmodule, _, _}, &1))}, path)
end

defmodule Smith.ModelProfile do
  def collect(stack, totals) do
    receive do
      {:trace_ts, _, :call, {OCEx.Native, :call, [op, _]}, timestamp} ->
        collect([{op, timestamp} | stack], totals)

      {:trace_ts, _, :return_from, {OCEx.Native, :call, 2}, _, timestamp} ->
        [{op, start} | rest] = stack
        us = System.convert_time_unit(timestamp - start, :native, :microsecond)
        totals = Map.update(totals, op, {1, us}, fn {n, t} -> {n + 1, t + us} end)
        collect(rest, totals)

      {:results, parent} ->
        send(parent, {:results, totals})
    end
  end

  def run(model) do
    Code.ensure_loaded!(OCEx.Native)
    tracer = spawn(fn -> collect([], %{}) end)
    :erlang.trace_pattern({OCEx.Native, :call, 2}, [{:_, [], [{:return_trace}]}], [:local])
    :erlang.trace(self(), true, [:call, :monotonic_timestamp, {:tracer, tracer}])

    try do
      {:ok, _} = Smith.evaluate(model)
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({OCEx.Native, :call, 2}, false, [:local])
    end

    ref = :erlang.trace_delivered(self())
    receive do: ({:trace_delivered, _, ^ref} -> :ok)
    send(tracer, {:results, self()})
    receive do: ({:results, totals} -> totals)
  end
end

IO.puts("model,operation,calls,inclusive_us")

for {name, model} <- [
      {"plant-stand", Models.PlantStand.build()},
      {"deck-clip", Models.DeckClip.build()}
    ] do
  for {op, {n, us}} <- Smith.ModelProfile.run(model) |> Enum.sort_by(fn {_, {_, us}} -> -us end),
      do: IO.puts("#{name},#{op},#{n},#{us}")
end
