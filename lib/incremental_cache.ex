defmodule Smith.IncrementalCache do
  @moduledoc false
  use GenServer

  # Store serialized geometry only: no native resources, selectors, callbacks,
  # or caller processes survive an evaluation. Both bytes and entries are capped.
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def fetch(keys, server \\ __MODULE__), do: request(server, {:fetch, keys}, :miss)
  def put(key, brep, server \\ __MODULE__), do: request(server, {:put, key, brep}, :ok)
  def clear(server \\ __MODULE__), do: request(server, :clear, :ok)

  defp request(server, message, fallback) do
    GenServer.call(server, message, 100)
  catch
    :exit, _ -> fallback
  end

  @impl true
  def init(opts) do
    state = %{
      entries: %{},
      bytes: 0,
      sequence: 0,
      max_bytes: Keyword.get(opts, :max_bytes, 32 * 1024 * 1024),
      max_entries: Keyword.get(opts, :max_entries, 128),
      ttl: Keyword.get(opts, :ttl, 120_000)
    }

    Process.send_after(self(), :expire, state.ttl)
    {:ok, state}
  end

  @impl true
  def handle_call(:clear, _, state), do: {:reply, :ok, %{state | entries: %{}, bytes: 0}}

  def handle_call({:fetch, keys}, _, state) do
    state = expire(state)

    case Enum.find(keys, &Map.has_key?(state.entries, &1)) do
      nil ->
        {:reply, :miss, state}

      key ->
        {brep, bytes, _, _} = Map.fetch!(state.entries, key)
        state = %{state | sequence: state.sequence + 1}
        entries = Map.put(state.entries, key, {brep, bytes, state.sequence, now() + state.ttl})
        {:reply, {key, brep}, %{state | entries: entries}}
    end
  end

  def handle_call({:put, key, brep}, _, state) do
    bytes = byte_size(key) + byte_size(brep)
    state = expire(state)

    if bytes <= state.max_bytes and byte_size(brep) <= 4 * 1024 * 1024 do
      state = remove(state, key)
      sequence = state.sequence + 1
      entries = Map.put(state.entries, key, {brep, bytes, sequence, now() + state.ttl})

      {:reply, :ok,
       trim(%{state | entries: entries, bytes: state.bytes + bytes, sequence: sequence})}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:expire, state) do
    Process.send_after(self(), :expire, state.ttl)
    {:noreply, expire(state)}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp expire(state) do
    current = now()

    Enum.reduce(state.entries, state, fn {key, {_, _, _, expires}}, acc ->
      if expires <= current, do: remove(acc, key), else: acc
    end)
  end

  defp remove(state, key) do
    case Map.pop(state.entries, key) do
      {nil, _} -> state
      {{_, bytes, _, _}, entries} -> %{state | entries: entries, bytes: state.bytes - bytes}
    end
  end

  defp trim(state)
       when state.bytes <= state.max_bytes and map_size(state.entries) <= state.max_entries,
       do: state

  defp trim(state) do
    {key, _} = Enum.min_by(state.entries, fn {_, {_, _, sequence, _}} -> sequence end)
    state |> remove(key) |> trim()
  end
end
