# OCEX_PATH=../ocex mix run benchmarks/evaluator.exs --output=/tmp/evaluator.csv
{opts, _, []} =
  OptionParser.parse(System.argv(), strict: [output: :string, samples: :integer, cache: :boolean])

if opts[:cache] == false, do: Supervisor.terminate_child(Smith.Supervisor, Smith.IncrementalCache)
samples = Keyword.get(opts, :samples, 7)
rounded = Smith.box(30, 20, 10) |> Smith.fillet(edges: :all, radius: 1)

placed =
  Enum.reduce(1..12, rounded, fn i, model ->
    model |> Smith.rotate({1, 2, 3}, i * 3, {2, -1, 4}) |> Smith.translate({1, 2, -0.5})
  end)

body =
  Smith.box(100, 80, 8)
  |> Smith.cut(
    for i <- 0..31, do: Smith.cylinder(2, 10, at: {5 + rem(i, 8) * 12, 5 + div(i, 8) * 20, -1})
  )

edit = fn i ->
  body |> Smith.hole(on: Smith.Plane.xy(), at: {90, 10 + i}, diameter: 3, through: :all)
end

cases = [
  {"transforms24", fn _ -> placed end},
  {"repeat_exact", fn _ -> body end},
  {"edit_last_hole", edit},
  {"edit_primitive",
   fn i -> Smith.box(100 + i, 80, 8) |> Smith.fillet(edges: :all, radius: 1) end},
  {"tiny_box", fn i -> Smith.box(1 + i, 2, 3) end}
]

{:ok, file} = File.open(Keyword.fetch!(opts, :output), [:write])
IO.write(file, "case,sample,total_us\n")

for {name, recipe} <- cases do
  {:ok, _} = recipe.(0) |> Smith.evaluate()

  for i <- 1..samples do
    model = recipe.(i)
    :erlang.garbage_collect()
    {us, {:ok, result}} = :timer.tc(fn -> Smith.evaluate(model) end)
    {:ok, true} = OCEx.valid?(result.shape)
    IO.write(file, "#{name},#{i},#{us}\n")
  end
end

File.close(file)
