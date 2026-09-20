# Experimental isolated kernels; not a production worker pool.
[{module, beam}] =
  Code.compile_string("""
  defmodule Smith.KernelWorkerExperiment do
    def build(count) do
      {:ok, body} = OCEx.box(160, 160, 8)
      if count == 0 do
        body
      else
        tools = for i <- 0..(count - 1) do
          {:ok, tool} = OCEx.cylinder(2, 10)
          {:ok, tool} = OCEx.translate(tool, {5 + rem(i, 16) * 9, 5 + div(i, 16) * 9, -1})
          tool
        end
        {:ok, result} = OCEx.cut_many(body, tools)
        result
      end
    end
    def serialized(count) do
      {:ok, brep} = build(count) |> OCEx.to_brep()
      brep
    end
  end
  """)

{opts, _, []} = OptionParser.parse(System.argv(), strict: [output: :string, samples: :integer])
paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

{startup, peers} =
  :timer.tc(fn ->
    for _ <- 1..4 do
      {:ok, peer, _} =
        :peer.start_link(%{
          connection: :standard_io,
          args: [~c"+S", ~c"2:2", ~c"+SDcpu", ~c"2"] ++ paths
        })

      {:ok, _} = :peer.call(peer, :application, :ensure_all_started, [:elixir])
      {:ok, _} = :peer.call(peer, :application, :ensure_all_started, [:ocex])

      {:module, ^module} =
        :peer.call(peer, :code, :load_binary, [module, ~c"kernel-workers.exs", beam])

      peer
    end
  end)

IO.puts("Four isolated workers startup: #{startup} us")

try do
  {:ok, file} = File.open(Keyword.fetch!(opts, :output), [:write])
  IO.write(file, "cutters,workers,sample,jobs,total_us\n")

  for cutters <- [0, 32, 128], workers <- [0, 1, 2, 4] do
    run = fn ->
      0..7
      |> Task.async_stream(
        fn i ->
          if workers == 0 do
            apply(module, :build, [cutters])
          else
            peer = Enum.at(peers, rem(i, workers))
            brep = :peer.call(peer, module, :serialized, [cutters], 120_000)
            {:ok, shape} = OCEx.from_brep(brep)
            shape
          end
        end, max_concurrency: max(workers, 1), timeout: 120_000)
      |> Enum.map(fn {:ok, shape} -> shape end)
    end

    run.()

    for sample <- 1..Keyword.get(opts, :samples, 5) do
      {us, shapes} = :timer.tc(run)

      for shape <- shapes do
        {:ok, true} = OCEx.valid?(shape)
        {:ok, volume} = OCEx.volume(shape)
        true = abs(volume - (160 * 160 * 8 - cutters * 4 * :math.pi() * 8)) < 1.0e-5
      end

      IO.write(file, "#{cutters},#{workers},#{sample},8,#{us}\n")
    end
  end

  File.close(file)
after
  Enum.each(peers, &:peer.stop/1)
end
