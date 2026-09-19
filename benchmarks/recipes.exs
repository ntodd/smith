# OCEX_PATH=../ocex mix run benchmarks/recipes.exs --output=benchmarks/results/recipes-current.csv
{opts, _, []} =
  OptionParser.parse(System.argv(),
    strict: [reference_smith: :string, output: :string, samples: :integer]
  )

if source = opts[:reference_smith] do
  previous = Code.compiler_options(ignore_module_conflict: true)
  Code.compile_file(source)
  Code.compiler_options(previous)
end

samples = Keyword.get(opts, :samples, 15)
base = Smith.box(80, 80, 4)

cutters =
  for i <- 0..31,
      do: Smith.cylinder(2, 6) |> Smith.translate({5 + 10 * rem(i, 8), 5 + 18 * div(i, 8), -1})

ribs = for i <- 0..31, do: Smith.box(80, 1, 4) |> Smith.translate({0, 2 + i * 2.3, 2})
boxes = for i <- 0..99, do: Smith.box(2, 3, 4) |> Smith.translate({i * 4, 0, 0})
rounded = Smith.box(20, 10, 5) |> Smith.fillet(edges: :all, radius: 1)
repeat = fn model -> for i <- 0..15, do: model |> Smith.translate({i * 25, 0, 0}) end

cases = [
  {"cut32/chain", fn -> base |> Smith.cut(cutters) |> Smith.evaluate() end,
   25600 - 512 * :math.pi()},
  {"fuse32/chain", fn -> base |> Smith.fuse(ribs) |> Smith.evaluate() end, 30720},
  {"compound100", fn -> Smith.compound(boxes) |> Smith.evaluate() end, 2400},
  {"pattern16/rebuild", fn -> rounded |> repeat.() |> Smith.compound() |> Smith.evaluate() end,
   nil},
  {"pattern16/snapshot_including_preparation",
   fn ->
     {:ok, source} = Smith.evaluate(rounded)
     source |> Smith.from_result() |> repeat.() |> Smith.compound() |> Smith.evaluate()
   end, nil}
]

cases =
  if function_exported?(Smith, :cut_many, 2),
    do:
      cases ++
        [
          {"cut32/batch", fn -> base |> Smith.cut_many(cutters) |> Smith.evaluate() end,
           25600 - 512 * :math.pi()},
          {"fuse32/batch", fn -> base |> Smith.fuse_many(ribs) |> Smith.evaluate() end, 30720}
        ],
    else: cases

{:ok, file} = File.open(Keyword.fetch!(opts, :output), [:write])
IO.write(file, "case,sample,total_us\n")

for {name, fun, expected} <- cases do
  {:ok, warm} = fun.()
  {:ok, true} = OCEx.valid?(warm.shape)
  {:ok, volume} = OCEx.volume(warm.shape)
  if expected && abs(volume - expected) > 1.0e-5, do: raise("wrong volume for #{name}")

  for sample <- 1..samples do
    :erlang.garbage_collect()
    {us, {:ok, result}} = :timer.tc(fun)
    {:ok, true} = OCEx.valid?(result.shape)
    IO.write(file, "#{name},#{sample},#{us}\n")
    IO.puts("#{name},#{sample},#{us}")
  end
end

File.close(file)
