# OCEX_PATH=../ocex mix run benchmarks/modeling.exs --output=benchmarks/results/modeling-current.csv
# Load only model module definitions, excluding Mix.install and export side effects.
for path <- ["models/plant_stand.exs", "models/deck_clip.exs"] do
  {:__block__, _, forms} = path |> File.read!() |> Code.string_to_quoted!()
  Code.compile_quoted({:__block__, [], Enum.filter(forms, &match?({:defmodule, _, _}, &1))}, path)
end

Code.require_file("models/support/verification.exs")
Code.require_file("models/test/plant_stand_checks.exs")
Code.require_file("models/test/deck_clip_checks.exs")

defmodule Smith.ModelingBenchmark do
  def batch(%Smith.Model{operations: ops}, modes, native \\ true) do
    ops = Enum.map(ops, fn {op, args} -> {op, Enum.map(args, &nested(&1, modes, native))} end)
    ops = ops |> Enum.reverse() |> Enum.chunk_by(fn {op, _} -> op end)

    ops =
      Enum.flat_map(ops, fn group ->
        {op, _} = hd(group)

        if op in modes and length(group) > 1 and
             Enum.all?(group, &match?({_, [%Smith.Model{}]}, &1)) do
          tools = Enum.map(group, fn {_, [tool]} -> tool end)

          if native,
            do: [{if(op == :cut, do: :cut_many, else: :fuse_many), [tools]}],
            else: [{op, [Smith.compound(tools)]}]
        else
          group
        end
      end)

    %Smith.Model{operations: Enum.reverse(ops)}
  end

  defp nested(%Smith.Model{} = model, modes, native), do: batch(model, modes, native)
  defp nested(value, _, _), do: value

  def run do
    {opts, _, []} =
      OptionParser.parse(System.argv(),
        strict: [
          output: :string,
          reference_smith: :string,
          variants: :string,
          samples: :integer,
          models: :string
        ]
      )

    if source = opts[:reference_smith] do
      previous = Code.compiler_options(ignore_module_conflict: true)
      Code.compile_file(source)
      Code.compiler_options(previous)
    end

    variants =
      String.split(Keyword.get(opts, :variants, "baseline,native-cut,native-cut-fuse"), ",")

    samples = Keyword.get(opts, :samples, 5)
    models = String.split(Keyword.get(opts, :models, "plant-stand,deck-clip"), ",")

    root = Path.expand("../output/benchmarks", __DIR__)
    File.mkdir_p!(root)
    {:ok, file} = File.open(Keyword.get(opts, :output, Path.join(root, "modeling.csv")), [:write])
    IO.write(file, "model,variant,sample,evaluate_us,volume,faces,solids\n")

    for {name, recipe} <- [
          {"plant-stand", Models.PlantStand.build()},
          {"deck-clip", Models.DeckClip.build()}
        ],
        name in models do
      {:ok, baseline} = Smith.evaluate(recipe)
      {:ok, expected} = OCEx.volume(baseline.shape)
      {:ok, expected_bounds} = OCEx.bounds(baseline.shape)
      {:ok, expected_solids} = OCEx.solids(baseline.shape)
      {:ok, brep} = OCEx.to_brep(baseline.shape)
      File.write!(Path.join(root, name <> ".brep"), brep)

      for {variant, model} <- [
            {"baseline", recipe},
            {"compound-cut", batch(recipe, [:cut], false)},
            {"compound-cut-fuse", batch(recipe, [:cut, :fuse], false)},
            {"native-cut", batch(recipe, [:cut])},
            {"native-cut-fuse", batch(recipe, [:cut, :fuse])}
          ],
          variant in variants do
        case Smith.evaluate(model) do
          {:ok, result} ->
            {:ok, volume} = OCEx.volume(result.shape)
            {:ok, bounds} = OCEx.bounds(result.shape)
            {:ok, faces} = OCEx.faces(result.shape)
            {:ok, solids} = OCEx.solids(result.shape)
            true = length(solids) == length(expected_solids)
            assert_close(volume, expected, 1.0e-7 * expected)

            for {a, b} <- Enum.zip(Tuple.to_list(bounds), Tuple.to_list(expected_bounds)),
                {x, y} <- Enum.zip(Tuple.to_list(a), Tuple.to_list(b)),
                do: assert_close(x, y, 1.0e-5)

            # Both differences must have negligible volume, not just equal mass.
            for {a, b} <- [{baseline.shape, result.shape}, {result.shape, baseline.shape}],
                variant != "baseline" do
              {:ok, delta} = OCEx.cut(a, b)
              {:ok, delta_volume} = OCEx.volume(delta)
              assert_close(delta_volume, 0, 1.0e-7 * expected)
            end

            checks =
              if name == "plant-stand",
                do: Models.PlantStandChecks.verify(result.shape),
                else: Models.DeckClipChecks.verify(result.shape)

            IO.inspect(checks, label: "Functional checks: #{name}/#{variant}")

            for sample <- 1..samples do
              :erlang.garbage_collect()
              {us, {:ok, measured}} = :timer.tc(fn -> Smith.evaluate(model) end)
              {:ok, true} = OCEx.valid?(measured.shape)

              IO.write(
                file,
                "#{name},#{variant},#{sample},#{us},#{volume},#{length(faces)},#{length(solids)}\n"
              )

              IO.puts("#{name}/#{variant}: #{Float.round(us / 1000, 2)} ms")
            end

          {:error, reason} ->
            IO.puts("REJECTED #{name}/#{variant}: #{inspect(reason)}")
        end
      end
    end

    File.close(file)
  end

  defp assert_close(a, b, tolerance) do
    if abs(a - b) > tolerance, do: raise("geometry mismatch: #{a} != #{b}")
  end
end

Smith.ModelingBenchmark.run()
