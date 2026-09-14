defmodule Smith.Export do
  @moduledoc """
  Part bundles containing geometry files, a preview mesh, and check results.

  Use `Smith.export/3` or `write/3` with an evaluated part. Each call writes
  a new directory identified by the geometry revision and a random export
  ID. `current.json` points to the latest records by name; previous export
  directories remain available.

  Print placement affects STL and 3MF. STEP and BREP retain the evaluated
  geometry's placement. Print meshes are checked after STL serialization,
  and requested STEP files are reimported and measured. These checks catch
  common export failures; they do not establish dimensional fit, strength,
  printer settings, or freedom from every mesh self-intersection.

  See `write/3` for all options and returned fields, `mesh/3` for the
  precise checks, and the [exporting guide](exporting.html) for examples.
  Assembly exports go through `Smith.export/3`; this module's writers
  accept individual `Smith.Result` values.
  """
  alias Smith.{Mesh, Result}

  @doc """
  Writes a checked export bundle for one evaluated `Smith.Result`.

  `root` is an output directory, created as needed. Returns
  `{:ok, record}` after writing files and updating `current.json`.
  `Smith.export/3` delegates here for individual results.

  ## Options

  | Option | Default | Meaning |
  | --- | --- | --- |
  | `:name` | Required | String starting with an ASCII letter/digit; remaining characters may also include `_` or `-` |
  | `:formats` | `[:step, :stl, :three_mf]` | Nonempty unique subset of these formats |
  | `:tolerance` | `0.03` | Print mesh linear deflection in mm |
  | `:angular_tolerance` | `0.5` | Print mesh angular deflection in radians |
  | `:step_tolerance` | `1.0e-6` | Relative STEP volume error threshold; greater than zero and at most `1.0e-5` |
  | `:print_rotation` | `nil` | `{axis, degrees}` about world zero |
  | `:print_offset` | `{0, 0, 0}` | World translation after print rotation |
  | `:on_bed` | `false` | Centers rotated bounds in XY and puts minimum Z at zero |
  | `:display_orientation` | `:print` | `:print` or `:installed` orientation for the preview mesh |
  | `:display_offset` | `{0, 0, 0}` | World translation of the preview mesh only |
  | `:metadata` | `%{}` | JSON-encodable map added to the verification report |

  `:on_bed` cannot be combined with `:print_offset`. Linear and angular
  deflections must exceed 1.0e-7. Metadata tuples become JSON arrays;
  generated verification fields take precedence over colliding metadata keys.

  ## Files and returned record

  Files are placed under `root/name/revision/export_id/`. Requested formats
  produce `model.step`, `model.stl`, and `model.3mf`. `model.brep`,
  `model.json`, and `verification.json` are always written. STEP and BREP
  retain evaluated placement; STL and 3MF use print placement. 3MF contains
  millimeter geometry without printer or slicer settings.

  The record contains `:name`, `:revision`, `:export_id`, `:step`,
  `:stl`, `:three_mf`, native `:volume`, display `:mesh`, and
  `:verification`. Unrequested format paths are `nil`. Paths retain
  the form of `root`: use an absolute root if consuming them elsewhere.
  The display mesh uses fixed 0.03 mm / 0.5 rad settings, independently
  of print mesh settings.

  ## Checks and failures

  The result's BREP must match its revision. All bundles run `mesh/3`
  checks, even STEP-only bundles. Each requested STEP is read back and
  checked for native validity, solid count, and relative volume error
  strictly below `:step_tolerance`. This is not a boundary-distance or
  dimensional comparison. 3MF is serialized from the checked mesh; it is
  not read back independently by this exporter.

  Failures return `{:error, reason}`, including `:revision_mismatch`,
  `:invalid_options`, `:invalid_metadata`, mesh/STEP check errors, and
  file-system errors. Failed exports may leave new files, but preserve the
  previous manifest and earlier export directories. Run writers to one
  root sequentially.
  """
  @spec write(Result.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write(%Result{} = result, root, opts) when is_binary(root) do
    with {:ok, record} <- write_files(result, root, opts),
         {:ok, :ok} <- publish(record, root),
         do: {:ok, record}
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  @doc """
  Writes several part bundles and publishes their records together.

  `entries` is a nonempty list of `{result, options}` pairs. Each result
  is a `Smith.Result`; options follow `write/3`. Names must be distinct.
  Returns `{:ok, records}` in input order.

  Invalid batch options return `:invalid_options`. A part write failure
  returns `{:error, {:export_failed, name, reason}}`. Nothing is published
  until every bundle passes, although completed unpublished files may
  remain. This groups exports without creating a named assembly or ZIP.
  """
  @spec write_many([{Result.t(), keyword()}], String.t()) :: {:ok, [map()]} | {:error, term()}
  def write_many(entries, root) when is_list(entries) and is_binary(root) do
    with {:ok, records} <- stage_many(entries, root),
         {:ok, :ok} <- publish(records, root),
         do: {:ok, records}
  end

  def write_many(_, _), do: {:error, :invalid_argument}

  @doc false
  def stage_many(entries, root) do
    with :ok <- batch_options(entries), do: write_entries(entries, root)
  end

  defp write_entries(entries, root) do
    Enum.reduce_while(entries, {:ok, []}, fn {result, opts}, {:ok, records} ->
      case write_files(result, root, opts) do
        {:ok, record} -> {:cont, {:ok, [record | records]}}
        {:error, reason} -> {:halt, {:error, {:export_failed, opts[:name], reason}}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  defp write_files(result, root, opts) do
    with :ok <- options(opts),
         {:ok, brep} <- OCEx.to_brep(result.shape),
         :ok <- ensure(revision(brep) == result.revision, :revision_mismatch),
         {:ok, metadata} <- metadata(Keyword.get(opts, :metadata, %{})),
         {:ok, printable, placement} <- place(result.shape, opts),
         {:ok, print} <-
           mesh(
             printable,
             Keyword.get(opts, :tolerance, 0.03),
             Keyword.get(opts, :angular_tolerance, 0.5)
           ),
         :ok <- check_bed(print, opts),
         {:ok, display} <-
           OCEx.translate(
             if(opts[:display_orientation] == :installed, do: result.shape, else: printable),
             Keyword.get(opts, :display_offset, {0, 0, 0})
           ),
         {:ok, display_mesh} <- OCEx.mesh(display, 0.03),
         {:ok, volume} <- OCEx.volume(result.shape) do
      export_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      directory = Path.join([root, opts[:name], result.revision, export_id])
      formats = Keyword.get(opts, :formats, [:step, :stl, :three_mf])
      step = if :step in formats, do: Path.join(directory, "model.step")
      stl = if :stl in formats, do: Path.join(directory, "model.stl")
      three_mf = if :three_mf in formats, do: Path.join(directory, "model.3mf")

      with :ok <- File.mkdir_p(directory),
           {:ok, step_error} <-
             verified_step(result.shape, step, Keyword.get(opts, :step_tolerance, 1.0e-6)),
           :ok <- File.write(Path.join(directory, "model.brep"), brep),
           :ok <- write_optional(stl, fn -> print.stl end),
           :ok <- write_optional(three_mf, fn -> Mesh.to_3mf(print.mesh) end) do
        record = %{
          name: opts[:name],
          revision: result.revision,
          export_id: export_id,
          step: step,
          stl: stl,
          three_mf: three_mf,
          volume: volume,
          mesh: display_mesh,
          verification:
            Map.merge(metadata, %{
              mesh: print.checks,
              print_placement: placement,
              step_relative_volume_error: step_error,
              step_volume_tolerance: Keyword.get(opts, :step_tolerance, 1.0e-6)
            })
        }

        with :ok <- File.write(Path.join(directory, "model.json"), encode(record)),
             :ok <-
               File.write(Path.join(directory, "verification.json"), encode(record.verification)),
             do: {:ok, record}
      end
    end
  end

  @doc """
  Builds a printable mesh and checks its binary STL representation.

  Accepts an `OCEx.Shape`, linear deflection in mm (default 0.03), and
  angular deflection in radians (default 0.5). The shape must contain solids
  and have positive total volume. Native mesh vertices are welded with
  `Smith.Mesh.weld/2`, then serialized as binary STL and parsed back.

  The parsed mesh must have:

    * Exactly two triangles sharing every edge, with opposite edge directions.
    * As many edge-connected triangle components as native solids.
    * Signed volume within 0.5% of native volume (strictly less than 0.005
      relative error).

  Returns `{:ok, %{mesh: mesh, stl: binary, checks: report}}`. The mesh is
  the welded pre-STL mesh; checks describe the parsed STL. The report has
  the fields from `Smith.Mesh.inspect/1`, plus `:relative_volume_error`,
  `:linear_deflection`, and `:angular_deflection`.

  Failures include `:no_solids`, `:non_positive_volume`,
  `:invalid_print_mesh`, and `:mesh_volume_mismatch`. A coarse curved mesh
  can fail the volume check; decrease deflections and retry. Component
  matching also rejects otherwise valid designs with multiple disconnected
  boundary shells per solid, such as a fully enclosed cavity. It is not
  a general self-intersection or manufacturability test.

      iex> {:ok, box} = OCEx.box(2, 3, 4)
      iex> {:ok, print} = Smith.Export.mesh(box)
      iex> {print.checks.watertight, print.checks.components, byte_size(print.stl)}
      {true, 1, 684}

  <div class="smith-doc-preview" data-preview="api-export-0" data-model="box" data-label="Printable box">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @spec mesh(OCEx.Shape.t(), number(), number()) :: {:ok, map()} | {:error, term()}
  def mesh(shape, tolerance \\ 0.03, angular_tolerance \\ 0.5) do
    with {:ok, solids} <- OCEx.solids(shape),
         :ok <- ensure(solids != [], :no_solids),
         {:ok, volume} <- OCEx.volume(shape),
         :ok <- ensure(volume > 0, :non_positive_volume),
         {:ok, raw} <- OCEx.mesh(shape, tolerance, angular_tolerance) do
      mesh = Mesh.weld(raw)
      stl = Mesh.to_stl(mesh)
      checks = stl |> Mesh.from_stl() |> Mesh.inspect()
      error = abs(checks.volume / volume - 1)

      with :ok <-
             ensure(
               checks.watertight and checks.winding_consistent and
                 checks.components == length(solids),
               :invalid_print_mesh
             ),
           :ok <- ensure(error < 0.005, :mesh_volume_mismatch) do
        {:ok,
         %{
           mesh: mesh,
           stl: stl,
           checks:
             Map.merge(checks, %{
               relative_volume_error: error,
               linear_deflection: tolerance,
               angular_deflection: angular_tolerance
             })
         }}
      end
    end
  end

  @doc """
  Updates `current.json` with existing export records.

  Accepts one record map or a nonempty list of records with distinct string
  `:name` values and string `:revision` values. Returns `{:ok, :ok}`.
  Records with matching names are replaced; unrelated models and assemblies
  remain. Standalone records cannot overwrite assembly-owned part names.

  This function only updates the manifest. It does **not** write or verify
  geometry files, hashes, or paths. Use `write/3` or `write_many/2` for
  the complete checked export flow.

  Malformed records return `:invalid_argument`, malformed existing
  manifests return `:invalid_manifest`, and ownership conflicts return
  `:assembly_part_conflict`. File-system errors are returned unchanged.
  The manifest is replaced through a temporary file; writers to one root
  must run sequentially.
  """
  @spec publish(map() | [map()], String.t()) :: {:ok, :ok} | {:error, term()}
  def publish(record, root) when is_map(record), do: publish([record], root)

  def publish(records, root) when is_list(records) and is_binary(root),
    do: publish_records(records, root, nil)

  def publish(_, _), do: {:error, :invalid_argument}

  @doc false
  def publish_assembly(report, records, root) do
    with {:ok, [report]} <- normalize_records([report]),
         do: publish_records(records, root, report)
  end

  defp publish_records(records, root, assembly) do
    path = Path.join(root, "current.json")

    with {:ok, records} <- normalize_records(records),
         {:ok, manifest} <- current_manifest(path),
         :ok <- ownership(manifest["models"], records, assembly),
         {:ok, version} <- OCEx.version() do
      models =
        if assembly do
          Enum.reject(manifest["models"], &(&1["assembly"] == assembly["name"]))
        else
          manifest["models"]
        end

      assemblies = Map.get(manifest, "assemblies", [])

      manifest =
        manifest
        |> Map.put("toolkit", version)
        |> Map.put("models", replace_named(models, records))
        |> Map.put(
          "assemblies",
          if(assembly, do: replace_named(assemblies, [assembly]), else: assemblies)
        )

      with :ok <- File.mkdir_p(root),
           :ok <- File.write(path <> ".tmp", encode(manifest)),
           :ok <- File.rename(path <> ".tmp", path),
           do: {:ok, :ok}
    end
  end

  defp ownership(current, records, assembly) do
    names = Enum.map(records, & &1["name"])
    owner = if assembly, do: assembly["name"]

    ensure(
      not Enum.any?(
        current,
        &(&1["name"] in names and
            &1["assembly"] != nil and &1["assembly"] != owner)
      ),
      :assembly_part_conflict
    )
  end

  defp replace_named(current, records) do
    Enum.reduce(records, current, fn record, models ->
      case Enum.find_index(models, &(&1["name"] == record["name"])) do
        nil -> models ++ [record]
        index -> List.replace_at(models, index, record)
      end
    end)
  end

  defp normalize_records(records) do
    valid =
      records != [] and
        Enum.all?(records, fn
          %{name: name, revision: revision} -> is_binary(name) and is_binary(revision)
          _ -> false
        end)

    if valid and unique?(Enum.map(records, & &1.name)),
      do: {:ok, records |> encode() |> JSON.decode!()},
      else: {:error, :invalid_argument}
  rescue
    _ -> {:error, :invalid_argument}
  end

  defp batch_options(entries) do
    valid =
      entries != [] and
        Enum.all?(entries, fn
          {%Result{}, opts} -> options(opts) == :ok
          _ -> false
        end)

    ensure(
      valid and unique?(Enum.map(entries, fn {_, opts} -> opts[:name] end)),
      :invalid_options
    )
  end

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp place(shape, opts) do
    with {:ok, rotated} <- rotate(shape, opts[:print_rotation]),
         {:ok, offset} <- print_offset(rotated, opts),
         {:ok, printable} <- OCEx.translate(rotated, offset) do
      {:ok, printable,
       %{
         rotation: opts[:print_rotation],
         offset: offset,
         on_bed: Keyword.get(opts, :on_bed, false)
       }}
    end
  end

  defp print_offset(shape, opts) do
    if opts[:on_bed] do
      with {:ok, {{lx, ly, lz}, {hx, hy, _}}} <- OCEx.bounds(shape),
           do: {:ok, {-(lx + hx) / 2, -(ly + hy) / 2, -lz}}
    else
      {:ok, Keyword.get(opts, :print_offset, {0, 0, 0})}
    end
  end

  defp check_bed(print, opts) do
    if opts[:on_bed] do
      # Curved mesh extrema can differ from exact CAD bounds by the linear deflection.
      vertices = Mesh.from_stl(print.stl).vertices

      bounds =
        for axis <- 0..2 do
          coordinates = Enum.map(vertices, &elem(&1, axis))
          {Enum.min(coordinates), Enum.max(coordinates)}
        end

      tolerance = Keyword.get(opts, :tolerance, 0.03)
      [{lx, hx}, {ly, hy}, {lz, _}] = bounds

      ensure(
        lz >= -1.0e-5 and lz <= tolerance + 1.0e-5 and
          abs(lx + hx) <= 2 * tolerance + 1.0e-5 and
          abs(ly + hy) <= 2 * tolerance + 1.0e-5,
        :invalid_bed_placement
      )
    else
      :ok
    end
  end

  @doc false
  def verified_step(_, nil, _), do: {:ok, nil}

  def verified_step(shape, path, tolerance) do
    with {:ok, volume} <- OCEx.volume(shape),
         {:ok, :ok} <- OCEx.write_step(shape, path),
         do: check_step(path, shape, volume, tolerance)
  end

  defp write_optional(nil, _), do: :ok
  defp write_optional(path, content), do: File.write(path, content.())

  @doc false
  def valid_formats?(formats),
    do:
      is_list(formats) and formats != [] and unique?(formats) and
        Enum.all?(formats, &(&1 in [:step, :stl, :three_mf]))

  defp check_step(path, original, volume, tolerance) do
    with {:ok, restored} <- OCEx.read_step(path),
         {:ok, true} <- OCEx.valid?(restored),
         {:ok, before} <- OCEx.solids(original),
         {:ok, after_solids} <- OCEx.solids(restored),
         :ok <- ensure(length(before) == length(after_solids), :step_solid_count_mismatch),
         {:ok, restored_volume} <- OCEx.volume(restored) do
      error = abs(restored_volume / volume - 1)
      with :ok <- ensure(error < tolerance, :step_volume_mismatch), do: {:ok, error}
    else
      {:ok, false} -> {:error, :invalid_shape}
      error -> error
    end
  end

  defp options(opts) when is_list(opts) do
    allowed = [
      :name,
      :formats,
      :tolerance,
      :angular_tolerance,
      :step_tolerance,
      :on_bed,
      :print_rotation,
      :print_offset,
      :display_offset,
      :display_orientation,
      :metadata
    ]

    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
         Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
         valid_formats?(Keyword.get(opts, :formats, [:step, :stl, :three_mf])) and
         Keyword.get(opts, :display_orientation, :print) in [:print, :installed] and
         Keyword.get(opts, :on_bed, false) in [true, false] and
         not (opts[:on_bed] == true and Keyword.has_key?(opts, :print_offset)) and
         is_number(Keyword.get(opts, :step_tolerance, 1.0e-6)) and
         Keyword.get(opts, :step_tolerance, 1.0e-6) > 0 and
         Keyword.get(opts, :step_tolerance, 1.0e-6) <= 1.0e-5 and
         is_binary(opts[:name]) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, opts[:name]),
       do: :ok,
       else: {:error, :invalid_options}
  end

  defp options(_), do: {:error, :invalid_options}
  defp rotate(shape, nil), do: {:ok, shape}
  defp rotate(shape, {axis, degrees}), do: OCEx.rotate(shape, {0, 0, 0}, axis, degrees)
  defp rotate(_, _), do: {:error, :invalid_options}
  defp ensure(true, _), do: :ok
  defp ensure(false, reason), do: {:error, reason}
  defp revision(brep), do: :crypto.hash(:sha256, brep) |> Base.encode16(case: :lower)

  defp current_manifest(path) do
    case File.read(path) do
      {:ok, binary} -> decode_manifest(binary)
      {:error, :enoent} -> {:ok, %{"models" => [], "assemblies" => []}}
      error -> error
    end
  end

  defp decode_manifest(binary) do
    case JSON.decode!(binary) do
      %{"models" => models} = manifest when is_list(models) ->
        assemblies = Map.get(manifest, "assemblies", [])

        if named_records?(models) and named_records?(assemblies),
          do: {:ok, manifest},
          else: {:error, :invalid_manifest}

      _ ->
        {:error, :invalid_manifest}
    end
  rescue
    _ -> {:error, :invalid_manifest}
  end

  defp named_records?(records),
    do:
      is_list(records) and
        Enum.all?(records, &(is_map(&1) and is_binary(&1["name"]))) and
        unique?(Enum.map(records, & &1["name"]))

  defp metadata(value) when is_map(value) do
    _ = encode(value)
    {:ok, value}
  rescue
    _ -> {:error, :invalid_metadata}
  end

  defp metadata(_), do: {:error, :invalid_metadata}
  defp encode(value), do: value |> json() |> JSON.encode!()
  defp json(value) when is_tuple(value), do: value |> Tuple.to_list() |> json()
  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, json(v)} end)
  defp json(value), do: value
end
