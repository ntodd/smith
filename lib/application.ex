defmodule Smith.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([{Smith.IncrementalCache, []}],
      strategy: :one_for_one,
      name: Smith.Supervisor
    )
  end
end
