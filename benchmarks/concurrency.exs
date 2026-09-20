{opts, _, []} = OptionParser.parse(System.argv(), strict: [output: :string])
{:ok, body} = OCEx.box(80, 80, 4)

tools =
  for i <- 0..15 do
    {:ok, cutter} = OCEx.cylinder(2, 6)
    {:ok, cutter} = OCEx.translate(cutter, {5 + 10 * rem(i, 8), 5 + 18 * div(i, 8), -1})
    cutter
  end

run = fn concurrency ->
  Task.async_stream(1..8, fn _ -> OCEx.cut_many(body, tools) end,
    max_concurrency: concurrency,
    timeout: 60_000
  )
  |> Enum.each(fn {:ok, {:ok, _}} -> :ok end)
end

{:ok, file} = File.open(Keyword.fetch!(opts, :output), [:write])
IO.write(file, "concurrency,sample,jobs,total_us\n")

for concurrency <- [1, 2, 4] do
  run.(concurrency)

  for sample <- 1..9 do
    {us, :ok} = :timer.tc(fn -> run.(concurrency) end)
    IO.write(file, "#{concurrency},#{sample},8,#{us}\n")
  end
end

File.close(file)
