defmodule Smith.Assembly.Export do
  @moduledoc false
  alias Smith.{Assembly, Export}

  def write(result, root, opts) when is_binary(root) do
    with :ok <- options(result, opts),
         :ok <- Assembly.validate_result(result),
         {:ok, staged} <- Export.stage_many(part_entries(result, opts), root),
         records = annotate(staged, result, opts[:name]),
         {:ok, report} <- artifacts(result, records, root, opts),
         {:ok, :ok} <- Export.publish_assembly(report, records, root),
         do: {:ok, report}
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  defp options(result, opts) do
    allowed = [
      :name,
      :formats,
      :tolerance,
      :angular_tolerance,
      :step_tolerance,
      :metadata,
      :part_metadata
    ]

    valid =
      is_list(opts) and Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
        is_binary(opts[:name]) and Assembly.valid_name?(opts[:name]) and
        Export.valid_formats?(Keyword.get(opts, :formats, [:step, :stl, :three_mf])) and
        positive?(Keyword.get(opts, :tolerance, 0.03)) and
        positive?(Keyword.get(opts, :angular_tolerance, 0.5)) and
        positive?(Keyword.get(opts, :step_tolerance, 1.0e-6)) and
        Keyword.get(opts, :step_tolerance, 1.0e-6) <= 1.0e-5

    if valid do
      metadata = Keyword.get(opts, :metadata, %{})
      per_part = Keyword.get(opts, :part_metadata, %{})
      keys = for entry <- result.entries, entry.kind == :part, do: entry.key

      if is_map(metadata) and is_map(per_part) and
           Enum.all?(per_part, fn {name, value} ->
             Assembly.key(name) in keys and is_map(value)
           end) and
           length(Enum.map(per_part, fn {name, _} -> Assembly.key(name) end) |> Enum.uniq()) ==
             map_size(per_part) do
        _ = encode({metadata, per_part})
        :ok
      else
        {:error, :invalid_metadata}
      end
    else
      {:error, :invalid_options}
    end
  rescue
    _ -> {:error, :invalid_metadata}
  end

  defp part_entries(result, opts) do
    metadata =
      Map.new(Keyword.get(opts, :part_metadata, %{}), fn {name, value} ->
        {Assembly.key(name), value}
      end)

    for entry <- result.entries, entry.kind == :part do
      print = Keyword.get(entry.options, :print, [])

      placement =
        for {key, value} <- print do
          {case key do
             :rotation -> :print_rotation
             :offset -> :print_offset
             :on_bed -> :on_bed
           end, value}
        end

      data =
        Map.merge(Map.get(metadata, entry.key, %{}), %{
          assembly: opts[:name],
          part: entry.key,
          exploded_offset: Keyword.get(entry.options, :exploded_offset, {0, 0, 0})
        })

      {entry.result,
       Keyword.take(opts, [:formats, :tolerance, :angular_tolerance, :step_tolerance]) ++
         placement ++
         [
           name: opts[:name] <> "-" <> entry.key,
           display_orientation: :installed,
           display_offset: Keyword.get(entry.options, :display_offset, {0, 0, 0}),
           metadata: data
         ]}
    end
  end

  defp annotate(records, result, name) do
    entries = Enum.filter(result.entries, &(&1.kind == :part))

    Enum.zip_with(records, entries, fn record, entry ->
      Map.merge(record, %{
        assembly: name,
        part: entry.key,
        installed: Keyword.get(entry.options, :installed, true)
      })
    end)
  end

  defp artifacts(result, records, root, opts) do
    export_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    directory = Path.join([root, opts[:name], result.revision, export_id])
    formats = Keyword.get(opts, :formats, [:step, :stl, :three_mf])
    tolerance = Keyword.get(opts, :step_tolerance, 1.0e-6)
    step = if :step in formats, do: Path.join(directory, "assembly.step")
    references = Enum.filter(result.entries, &(&1.kind == :reference))

    reference_step =
      if :step in formats and references != [],
        do: Path.join(directory, "references-DO-NOT-PRINT.step")

    report_path = Path.join(directory, "assembly.json")

    with :ok <- File.mkdir_p(directory),
         {:ok, step_error} <- Export.verified_step(result.shape, step, tolerance),
         {:ok, reference_error} <- reference_step(references, reference_step, tolerance),
         {:ok, pack} <- print_pack(records, directory),
         {:ok, brep} <- OCEx.to_brep(result.shape),
         :ok <- File.write(Path.join(directory, "assembly.brep"), brep) do
      report = %{
        name: opts[:name],
        revision: result.revision,
        export_id: export_id,
        assembly_step: step,
        references_step: reference_step,
        print_pack: pack,
        report: report_path,
        formats: formats,
        step_relative_volume_error: step_error,
        references_step_relative_volume_error: reference_error,
        metadata: Keyword.get(opts, :metadata, %{}),
        parts: Enum.map(records, &Map.drop(&1, [:mesh])),
        references: Enum.map(references, &%{name: &1.key, revision: &1.result.revision})
      }

      with :ok <- File.write(report_path, encode(report)), do: {:ok, report}
    end
  end

  defp reference_step(_, nil, _), do: {:ok, nil}

  defp reference_step(entries, path, tolerance) do
    with {:ok, shape} <- OCEx.compound(Enum.map(entries, & &1.result.shape)),
         do: Export.verified_step(shape, path, tolerance)
  end

  defp print_pack(records, directory) do
    paths =
      for record <- records,
          {extension, path} <- [{"stl", record.stl}, {"3mf", record.three_mf}],
          path != nil,
          do: {String.to_charlist(record.name <> "." <> extension), path}

    if paths == [] do
      {:ok, nil}
    else
      with {:ok, files} <- read_files(paths),
           {:ok, {_, archive}} <- :zip.create(~c"printables.zip", files, [:memory]),
           path = Path.join(directory, "printables.zip"),
           :ok <- File.write(path, archive),
           do: {:ok, path}
    end
  end

  defp read_files(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn {name, path}, {:ok, files} ->
      case File.read(path) do
        {:ok, bytes} -> {:cont, {:ok, files ++ [{name, bytes}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp positive?(n), do: is_number(n) and n > 0
  defp encode(value), do: value |> json() |> JSON.encode!()
  defp json(value) when is_tuple(value), do: value |> Tuple.to_list() |> json()
  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_map(value), do: Map.new(value, fn {key, item} -> {key, json(item)} end)
  defp json(value), do: value
end
