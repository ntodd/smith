# Run with OCEX_PATH=../ocex mix run benchmarks/performance.exs --output=/tmp/baseline.csv
# Fixture construction and compilation are excluded. Each sample uses a fresh process.
defmodule Smith.Performance do
  def run do
    {opts, _, []} =
      OptionParser.parse(System.argv(),
        strict: [output: :string, samples: :integer, reference_mesh: :string]
      )

    if source = opts[:reference_mesh] do
      previous = Code.compiler_options(ignore_module_conflict: true)
      Code.compile_file(source)
      Code.compiler_options(previous)
      IO.puts("Reference mesh implementation: #{source}")
    end

    samples = Keyword.get(opts, :samples, 15)
    true = samples > 0
    {:ok, sphere} = OCEx.sphere(20)
    {:ok, box} = OCEx.box(40, 30, 10)
    {:ok, tool} = OCEx.cylinder(5, 20)
    {:ok, raw} = OCEx.mesh(sphere, 0.03, 0.25)
    welded = Smith.Mesh.weld(raw)
    stl = Smith.Mesh.to_stl(welded)
    grid = grid(100)
    small_grid = grid(50)
    islands = islands(5000)
    small_islands = islands(1000)
    fan = fan(2000)
    small_fan = fan(1000)

    recipe =
      Smith.cylinder(5, 10)
      |> Smith.cut(Smith.cylinder(2, 12) |> Smith.translate({0, 0, -1}))
      |> Smith.rotate({1, 0, 0}, 90)
      |> Smith.clean()

    {:ok, font} = Smith.Font.load("priv/fonts/Graduate-Regular.ttf")
    text = Smith.Text.new("TEAM", font: font, size: 10)

    {:ok, svg} =
      Smith.SVG.from_binary(
        ~s|<svg viewBox="0 0 20 20"><path fill-rule="evenodd" d="M0 0H20V20H0Z M5 5H15V15H5Z"/></svg>|
      )

    artwork = Smith.SVG.new(svg, width: 20)

    cases = [
      {"native/box", fn -> OCEx.box(40, 30, 10) end},
      {"native/cut", fn -> OCEx.cut(box, tool) end},
      {"native/mesh_sphere", fn -> OCEx.mesh(sphere, 0.03, 0.25) end},
      {"native/brep", fn -> OCEx.to_brep(sphere) end},
      {"native/volume", fn -> OCEx.volume(sphere) end},
      {"recipe/evaluate", fn -> Smith.evaluate(recipe) end},
      {"text/layout", fn -> Smith.Text.layout(text) end},
      {"svg/layout", fn -> Smith.SVG.layout(artwork) end},
      {"mesh/weld_sphere", fn -> Smith.Mesh.weld(raw) end},
      {"mesh/inspect_sphere", fn -> Smith.Mesh.inspect(welded) end},
      {"mesh/inspect_grid_5000", fn -> Smith.Mesh.inspect(small_grid) end},
      {"mesh/inspect_grid_20000", fn -> Smith.Mesh.inspect(grid) end},
      {"mesh/inspect_islands_1000", fn -> Smith.Mesh.inspect(small_islands) end},
      {"mesh/inspect_islands_5000", fn -> Smith.Mesh.inspect(islands) end},
      {"mesh/inspect_fan_1000", fn -> Smith.Mesh.inspect(small_fan) end},
      {"mesh/inspect_fan_2000", fn -> Smith.Mesh.inspect(fan) end},
      {"mesh/to_stl", fn -> Smith.Mesh.to_stl(welded) end},
      {"mesh/from_stl", fn -> Smith.Mesh.from_stl(stl) end},
      {"mesh/to_3mf", fn -> Smith.Mesh.to_3mf(welded) end},
      {"export/checked_sphere", fn -> Smith.Export.mesh(sphere, 0.03, 0.25) end}
    ]

    IO.puts(
      "Elixir #{System.version()}, OTP #{System.otp_release()}, schedulers #{System.schedulers_online()}"
    )

    IO.inspect(OCEx.version(), label: "OCCT")
    IO.puts("sphere: #{length(welded.vertices)} vertices, #{length(welded.triangles)} triangles")

    rows =
      for {name, fun} <- cases do
        for _ <- 1..3, do: sample(fun)
        measurements = for _ <- 1..samples, do: sample(fun)
        times = Enum.sort(Enum.map(measurements, &elem(&1, 0)))
        reductions = Enum.sort(Enum.map(measurements, &elem(&1, 1)))

        row = [
          name,
          samples,
          hd(times),
          percentile(times, 0.5),
          percentile(times, 0.95),
          percentile(reductions, 0.5)
        ]

        IO.puts(Enum.join(row, ","))
        row
      end

    csv =
      "case,samples,min_us,median_us,p95_us,median_reductions\n" <>
        Enum.map_join(rows, "\n", &Enum.join(&1, ",")) <> "\n"

    if opts[:output], do: File.write!(opts[:output], csv)
  end

  defp percentile(values, p), do: Enum.at(values, ceil(length(values) * p) - 1)

  defp sample(fun) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        :erlang.garbage_collect()
        {:reductions, before} = Process.info(self(), :reductions)
        {elapsed, result} = :timer.tc(fun)
        {:reductions, after_count} = Process.info(self(), :reductions)

        case result do
          {:error, reason} -> raise "benchmark failed: #{inspect(reason)}"
          _ -> :ok
        end

        send(parent, {self(), elapsed, after_count - before})
      end)

    receive do
      {^pid, elapsed, reductions} ->
        Process.demonitor(ref, [:flush])
        {elapsed, reductions}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise "benchmark process failed: #{inspect(reason)}"
    after
      120_000 ->
        Process.exit(pid, :kill)
        raise "benchmark timed out"
    end
  end

  defp grid(n) do
    vertices = for y <- 0..n, x <- 0..n, do: {x * 1.0, y * 1.0, 0.0}

    triangles =
      for y <- 0..(n - 1),
          x <- 0..(n - 1),
          a = y * (n + 1) + x,
          triangle <- [{a, a + 1, a + n + 2}, {a, a + n + 2, a + n + 1}],
          do: triangle

    %{vertices: vertices, triangles: triangles}
  end

  defp islands(n) do
    vertices =
      for i <- 0..(n - 1),
          point <- [{i * 2.0, 0.0, 0.0}, {i * 2.0 + 1, 0.0, 0.0}, {i * 2.0, 1.0, 0.0}],
          do: point

    %{vertices: vertices, triangles: for(i <- 0..(n - 1), do: {i * 3, i * 3 + 1, i * 3 + 2})}
  end

  defp fan(n) do
    %{
      vertices: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0} | for(i <- 1..n, do: {0.0, i * 1.0, 1.0})],
      triangles: for(i <- 2..(n + 1), do: {0, 1, i})
    }
  end
end

Smith.Performance.run()
