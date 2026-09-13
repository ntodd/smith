defmodule Smith.Assembly.Export do
  @moduledoc """
  Verified export bundles for named assemblies.

  `Smith.export/3` delegates here for a `Smith.Assembly.Result`.
  Manufactured parts receive individual bundles and print placement;
  installed parts also form the combined assembly STEP. References are
  written to a separate STEP and excluded from printable files. Nested
  assemblies retain their tree in the JSON report; each manufactured leaf
  receives its own bundle. Parts
  marked `installed: false` remain in the print pack.

  All geometry and export checks finish before the current manifest is
  replaced. A failed export preserves the previous current assembly, but
  may leave unpublished files in the newly allocated directories.
  Writers targeting one output root must run sequentially.

  See `write/3` for options and report fields, and the
  [assembly guide](assemblies.html) for a complete example.
  """
  alias Smith.{Assembly, Export}

  @doc """
  Writes an assembly bundle and publishes its checked records to `current.json`.

  `result` must be an evaluated `Smith.Assembly.Result`. `root` is
  created as needed. Returns `{:ok, report}` after every manufactured
  part passes mesh checks and every requested STEP passes a round trip.

  ## Options

  | Option | Default | Meaning |
  | --- | --- | --- |
  | `:name` | Required | Export name string, following `Smith.Assembly.new/1` naming rules |
  | `:formats` | `[:step, :stl, :three_mf]` | Nonempty unique subset of these formats |
  | `:tolerance` | `0.03` | Print mesh linear deflection in mm |
  | `:angular_tolerance` | `0.5` | Print mesh angular deflection in radians |
  | `:step_tolerance` | `1.0e-6` | Relative STEP volume error threshold, positive and at most `1.0e-5` |
  | `:metadata` | `%{}` | JSON-encodable metadata on the assembly report |
  | `:part_metadata` | `%{}` | Metadata maps keyed by manufactured leaf paths |

  Mesh deflections must exceed 1.0e-7. Per-part names are normalized as in
  `Smith.Assembly.fetch/2`; unknown names or duplicate normalized keys
  fail. Paths accept lists such as `[:left, :base]` or slash strings such as
  `"left/base"`. A single name still addresses a top-level leaf.
  Metadata tuples become JSON arrays. Generated assembly, part, and
  exploded-offset fields override colliding per-part metadata keys.

  Print/display placement comes from assembly member options, not this
  option list. Part bundles follow `Smith.Export.write/3`, with installed
  preview orientation. Top-level names remain `<assembly>-<part>`. Nested
  paths join normalized segments with `__`, as in `fixture-left__base`.
  Normalized segments contain no underscores, so this encoding is unambiguous.

  ## Files and report

  The assembly directory is `root/name/revision/export_id/`. It contains
  `assembly.brep` and `assembly.json`, plus `assembly.step` when
  requested. References get `references-DO-NOT-PRINT.step` when STEP is
  requested and references exist. `printables.zip` contains the selected
  STL/3MF files for every manufactured part; STEP-only exports have no ZIP.

  The returned report contains `:name`, `:revision`, `:export_id`,
  `:assembly_step`, `:references_step`, `:print_pack`, `:report`,
  `:formats`, `:metadata`, `:parts`, `:references`, `:tree`, `:joints`, and `:connections`. It also
  includes `:step_relative_volume_error` and
  `:references_step_relative_volume_error`. Unrequested paths/checks are
  `nil`. Part records follow `Smith.Export.write/3` without the display
  mesh, plus `:assembly`, `:part`, and `:installed`. Reference records
  contain name and revision. Part identities and reference names use slash
  paths. File paths retain the form of the supplied root.

  `:tree` is a list of nodes in insertion order. Each has normalized `:name`,
  `:path` segments, `:kind`, effective `:installed`, `:revision`, and local
  `:options`, plus a resolved world `:pose` frame. Subassembly nodes also
  have `:children`, `:joints`, and `:connections`. Display/exploded
  offsets in part reports accumulate world vectors from all ancestors.
  Print options remain on leaves and act on their final world geometry.

  Joint records contain normalized name, member path relative to their containing
  assembly, and final world frame. Connection records contain normalized `:from`
  and `:to` joint paths, motion `:kind`, coordinate `:values`, and `:limits`.
  These describe the evaluated pose; STEP contains geometry without joint semantics.

  ## Checks and failures

  Every member and subassembly shape must agree with its recorded revision. Print meshes
  are checked even for STEP-only exports. Each emitted STEP is reimported
  and checked for native validity, solid count, and relative volume error.
  The combined STEP is an unfused compound, without named product-tree
  instances or materials. 3MF contains geometry, not slicer settings.

  Passing an unevaluated assembly, a part result, or a non-string root returns
  `{:error, :invalid_argument}`. Other errors include `:invalid_options`,
  `:invalid_metadata`, revision and
  geometry errors, file-system errors, and
  `{:export_failed, part_name, reason}` for a failed part bundle.
  New files may remain after failure; the previous manifest is preserved.
  Successful replacement removes retired parts from the current assembly
  while preserving unrelated manifest records. See `Smith.Export.mesh/3`
  for the scope and limits of mesh verification.
  """
  @spec write(Smith.Assembly.Result.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def write(%Assembly.Result{} = result, root, opts) when is_binary(root) do
    with :ok <- options(result, opts),
         :ok <- Assembly.validate_result(result),
         {:ok, leaves} <- Assembly.members(result),
         {:ok, staged} <- Export.stage_many(part_entries(leaves, opts), root),
         records = annotate(staged, leaves, opts[:name]),
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
      {:ok, leaves} = Assembly.members(result)
      keys = for entry <- leaves, entry.kind == :part, do: entry.key

      if is_map(metadata) and is_map(per_part) and
           Enum.all?(per_part, fn {name, value} ->
             Assembly.path_key(name) in keys and is_map(value)
           end) and
           length(Enum.map(per_part, fn {name, _} -> Assembly.path_key(name) end) |> Enum.uniq()) ==
             map_size(per_part) do
        _ =
          encode(
            {metadata,
             Map.new(per_part, fn {name, value} -> {Assembly.path_key(name), value} end)}
          )

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

  defp part_entries(leaves, opts) do
    metadata =
      Map.new(Keyword.get(opts, :part_metadata, %{}), fn {name, value} ->
        {Assembly.path_key(name), value}
      end)

    for entry <- leaves, entry.kind == :part do
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
           name: opts[:name] <> "-" <> Enum.join(entry.path, "__"),
           display_orientation: :installed,
           display_offset: Keyword.get(entry.options, :display_offset, {0, 0, 0}),
           metadata: data
         ]}
    end
  end

  defp annotate(records, leaves, name) do
    entries = Enum.filter(leaves, &(&1.kind == :part))

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
    {:ok, leaves} = Assembly.members(result)
    references = Enum.filter(leaves, &(&1.kind == :reference))

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
        references: Enum.map(references, &%{name: &1.key, revision: &1.result.revision}),
        tree: tree(result, [], true),
        joints: Smith.Assembly.Joint.records(result.joints),
        connections: result.connections
      }

      with :ok <- File.write(report_path, encode(report)), do: {:ok, report}
    end
  end

  defp tree(result, prefix, installed) do
    Enum.map(result.entries, fn entry ->
      path = prefix ++ [entry.key]

      installed =
        installed and Keyword.get(entry.options, :installed, true) and entry.kind != :reference

      node = %{
        name: entry.key,
        path: path,
        kind: entry.kind,
        installed: installed,
        revision: entry.result.revision,
        pose: entry.pose,
        options: Map.new(entry.options)
      }

      if entry.kind == :assembly,
        do:
          Map.merge(node, %{
            children: tree(entry.result, path, installed),
            joints: Smith.Assembly.Joint.records(entry.result.joints),
            connections: entry.result.connections
          }),
        else: node
    end)
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
