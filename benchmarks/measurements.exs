# Run after modeling.exs has saved the public deck-clip BREP fixture.
{opts, _, []} = OptionParser.parse(System.argv(), strict: [output: :string])
brep = File.read!("output/benchmarks/deck-clip.brep")
{:ok, body} = OCEx.from_brep(brep)
{:ok, expected} = OCEx.volume(body)
{:ok, file} = File.open(Keyword.fetch!(opts, :output), [:write])
IO.write(file, "case,sample,total_us,volume\n")

for mode <- [:cold, :warm], sample <- 1..15 do
  shape = if mode == :cold, do: elem(OCEx.from_brep(brep), 1), else: body
  {us, {:ok, value}} = :timer.tc(fn -> OCEx.volume(shape) end)
  true = value == expected
  IO.write(file, "#{mode},#{sample},#{us},#{value}\n")
end

File.close(file)
