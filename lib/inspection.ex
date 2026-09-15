defmodule Smith.Inspection do
  @moduledoc """
  Named geometry snapshots, explicit checks, and reports for scripts and agents.

  `run/2` evaluates named sources once and records their revisions, bounds,
  validity, area, volume, and topology counts. Checks return measured values
  and tolerances; failed requirements are `:failed`, while missing geometry,
  invalid checks, and kernel failures are `:error`. Neither is a passing check.
  A successful `{:ok, report}` means the report was produced: inspect its status.

  Names describe snapshots you supply, not persistent face identities. Rebuild
  selections after edits. `topology/3` exposes bounded pages of geometry metadata
  without native resource handles. No renderer or Livebook is required.

  See [inspection and validation](inspection.html) for a complete script.
  """
  alias Smith.{Geometry, Measure, Result}
  defstruct [:status, :revision, :models, :checks, sources: %{}, diagnostics: %{}]

  @opaque t :: %__MODULE__{
            status: :passed | :failed | :error,
            revision: String.t(),
            models: map(),
            checks: [map()],
            sources: map(),
            diagnostics: map()
          }
  @type name :: atom() | String.t()
  @type check ::
          {:topology, name(), :solids | :faces | :edges | :vertices, keyword()}
          | {:bounds, name(), OCEx.bounds3(), keyword()}
          | {:contained | :clearance, name(), name(), keyword()}
          | {:measurement, name(), Measure.t(), keyword()}

  @doc """
  Inspects a nonempty map of named sources and evaluates ordered checks.

  Options: `checks: []`. Supported checks (all tolerances are explicit):

    * `{:bounds, name, {low, high}, tolerance: mm}` — the model's native
      bounding box must stay inside that envelope, allowing the stated margin.
    * `{:contained, candidate, container, tolerance: amount}` — subtracts the
      container and measures excess volume (mm³), area (mm²), or length (mm),
      according to the candidate's highest dimension. The container must have
      solids. Empty candidates are an error, not vacuously contained.
    * `{:clearance, a, b, minimum: mm, tolerance: mm}` — minimum material
      distance, allowing the linear tolerance. Both inputs must contain solids.
      Positive interference volume also fails, using `volume_tolerance: mm3`
      (default 1.0e-7). Zero distance alone cannot distinguish contact from overlap.
    * `{:topology, name, :solids | :faces | :edges | :vertices, expected: count}`
      — requires an exact topology count, useful for one solid or a connected
      section represented by one face. Counts are representation-dependent.
    * `{:measurement, name, measurement, expected: number, tolerance: number}`
      — compares a `Smith.Measure` to its target in the measurement's units.
      The measurement revision must match the named source.

  Names normalize to strings; atom/string duplicates are rejected. Invalid
  options and source evaluation failures return `{:error, reason}`. Failures
  while executing a check are recorded with their reason in the report.
  Each check includes `elapsed_ms` to expose expensive validations.
  No defaults silently relax geometric requirements.
  """
  @spec run(%{name() => Measure.source()}, keyword()) :: {:ok, t()} | {:error, term()}
  def run(sources, opts \\ []) do
    with true <-
           is_map(sources) and map_size(sources) > 0 and Geometry.options(opts, [:checks]) and
             is_list(Keyword.get(opts, :checks, [])),
         {:ok, pairs} <- names(sources),
         {:ok, evaluated} <-
           Geometry.collect(pairs, fn {name, source} ->
             with {:ok, result} <- Geometry.result(source), do: {:ok, {name, result}}
           end),
         {:ok, summaries} <-
           Geometry.collect(evaluated, fn {name, result} ->
             with {:ok, summary} <- summary(result), do: {:ok, {name, summary}}
           end) do
      snapshots = Map.new(evaluated)

      {checks, diagnostics} =
        Keyword.get(opts, :checks, [])
        |> Enum.with_index(1)
        |> Enum.map_reduce(%{}, fn {spec, index}, diagnostics ->
          {microseconds, outcome} = :timer.tc(fn -> check(spec, snapshots) end)

          case outcome do
            {:ok, value, geometry} ->
              {Map.merge(value, %{index: index, elapsed_ms: microseconds / 1000}),
               if(geometry, do: Map.put(diagnostics, index, geometry), else: diagnostics)}

            {:error, reason} ->
              {%{index: index, status: :error, reason: reason, elapsed_ms: microseconds / 1000},
               diagnostics}
          end
        end)

      status =
        cond do
          Enum.any?(checks, &(&1.status == :error)) -> :error
          Enum.any?(checks, &(&1.status == :failed)) -> :failed
          true -> :passed
        end

      revision =
        evaluated
        |> Enum.map(fn {n, r} -> {n, r.revision} end)
        |> :erlang.term_to_binary()
        |> Geometry.hash()

      {:ok,
       %__MODULE__{
         status: status,
         revision: revision,
         models: Map.new(summaries),
         checks: checks,
         sources: snapshots,
         diagnostics: diagnostics
       }}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  @doc """
  Returns a bounded page of face or edge metadata for a source snapshot.

  Options are `selector: :all`, `offset: 0`, and `limit: 20` (1–100).
  Returns revision, total matches, items, and `next_offset` (nil at the end).
  Items follow native topology order; offsets are meaningful only within the
  same revision. Each includes a zero-based index and geometry metadata.
  Refine selectors to keep inspection output small. Callback exceptions propagate.
  """
  @spec topology(Measure.source(), :faces | :edges, keyword()) :: {:ok, map()} | {:error, term()}
  def topology(source, kind, opts \\ []) do
    with true <- Geometry.options(opts, [:selector, :offset, :limit]) and kind in [:faces, :edges],
         offset = Keyword.get(opts, :offset, 0),
         limit = Keyword.get(opts, :limit, 20),
         true <- is_integer(offset) and offset >= 0 and is_integer(limit) and limit in 1..100,
         {:ok, result} <- Geometry.result(source),
         {:ok, shapes} <-
           Smith.Selector.select(result.shape, kind, Keyword.get(opts, :selector, :all)),
         {:ok, items} <-
           shapes
           |> Enum.slice(offset, limit)
           |> Enum.with_index(offset)
           |> Geometry.collect(fn {shape, index} ->
             with {:ok, info} <-
                    apply(OCEx, if(kind == :faces, do: :face_info, else: :edge_info), [shape]),
                  do: {:ok, Map.put(info, :index, index)}
           end) do
      {:ok,
       %{
         revision: result.revision,
         total: length(shapes),
         items: items,
         next_offset: if(offset + length(items) < length(shapes), do: offset + length(items))
       }}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  @doc """
  Computes added and removed solid material between two stages.

  Returns `added` and `removed` as evaluated results, their volumes in mm³,
  and both source revisions. Empty differences are valid results with zero
  volume. Both stages must contain solids. Boolean comparison can be expensive
  for coincident spline surfaces; this performs actual geometry operations,
  not a bounding-box or mesh comparison.
  """
  @spec compare(Measure.source(), Measure.source()) :: {:ok, map()} | {:error, term()}
  def compare(before_source, after_source) do
    with {:ok, a} <- Geometry.result(before_source),
         {:ok, b} <- Geometry.result(after_source),
         :ok <- solids(a.shape),
         :ok <- solids(b.shape),
         {:ok, added} <- OCEx.cut(b.shape, a.shape),
         {:ok, removed} <- OCEx.cut(a.shape, b.shape),
         {:ok, added_result} <- Geometry.snapshot(added),
         {:ok, removed_result} <- Geometry.snapshot(removed),
         {:ok, av} <- OCEx.volume(added),
         {:ok, rv} <- OCEx.volume(removed) do
      {:ok,
       %{
         added: added_result,
         removed: removed_result,
         added_mm3: av,
         removed_mm3: rv,
         before_revision: a.revision,
         after_revision: b.revision
       }}
    end
  end

  @doc """
  Serializes a report as JSON without native handles or renderer dependencies.

  Includes schema version 1, millimeter units, status, source revisions, model
  summaries, and check outcomes. Coordinates become arrays. The report revision
  identifies its named geometry set, not its checks or artifact options.
  """
  @spec json(t()) :: {:ok, String.t()} | {:error, term()}
  def json(%__MODULE__{} = report) do
    data = %{
      schema_version: 1,
      units: "mm",
      status: report.status,
      revision: report.revision,
      models: report.models,
      checks: report.checks
    }

    {:ok, data |> Geometry.json() |> JSON.encode!()}
  end

  def json(_), do: {:error, :invalid_argument}

  @doc """
  Writes a report and headless PNG views into a new directory beneath `root`.

  Options: `views: [:isometric]`, `width: 640`, `height: 480`, and
  `sections: []` (a list of `Smith.Plane` values). Each source receives each
  view. Sections are evaluated with `Smith.section/2` and rendered separately.
  Excess material from failed containment checks receives a red diagnostic
  image. The JSON manifest links every artifact to its geometry revision.

  Returns `{:ok, %{directory: path, report: path, artifacts: list}}`.
  A unique subdirectory prevents a later run from overwriting an earlier
  report. On failure, no report.json is written, though partial images may
  remain. Model names never become filesystem paths. PNGs are tessellated
  observations; report measurements come from the BREP.
  """
  @spec write(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write(report, root, opts \\ [])

  def write(%__MODULE__{} = report, root, opts) when is_binary(root) do
    with true <- Geometry.options(opts, [:views, :width, :height, :sections]),
         views = Keyword.get(opts, :views, [:isometric]),
         sections = Keyword.get(opts, :sections, []),
         true <- is_list(views) and is_list(sections),
         directory =
           Path.join(
             root,
             report.revision <> "-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
           ),
         :ok <- File.mkdir_p(directory),
         {:ok, artifacts} <-
           write_images(report, directory, views, sections, Keyword.take(opts, [:width, :height])),
         {:ok, json} <- json(report),
         data = JSON.decode!(json) |> Map.put("artifacts", Geometry.json(artifacts)),
         path = Path.join(directory, "report.json"),
         :ok <- File.write(path, JSON.encode!(data)) do
      {:ok, %{directory: directory, report: path, artifacts: artifacts}}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  def write(_, _, _), do: {:error, :invalid_argument}

  defp write_images(report, directory, views, sections, opts) do
    jobs =
      Enum.sort(report.sources)
      |> Enum.flat_map(fn {name, result} ->
        Enum.map(views, &{name, result, {:view, &1}}) ++
          Enum.map(sections, &{name, result, {:section, &1}})
      end)

    jobs =
      jobs ++
        Enum.map(Enum.sort(report.diagnostics), fn {index, result} ->
          {"check-#{index}", result, {:diagnostic, :isometric}}
        end)

    jobs
    |> Enum.with_index(1)
    |> Geometry.collect(fn {{name, source, {kind, view}}, index} ->
      with {:ok, result} <-
             if(kind == :section,
               do: source |> Smith.from_result() |> Smith.section(view) |> Smith.evaluate(),
               else: {:ok, source}
             ),
           file = "view-#{index}.png",
           {:ok, _} <-
             Smith.Render.write(
               result,
               Path.join(directory, file),
               opts ++
                 [
                   view: view,
                   color: if(kind == :diagnostic, do: {210, 55, 45}, else: {62, 153, 183})
                 ]
             ) do
        {:ok,
         %{
           model: name,
           kind: kind,
           view: view,
           source_revision: source.revision,
           geometry_revision: result.revision,
           path: file
         }}
      end
    end)
  end

  defp names(sources) do
    if Enum.all?(Map.keys(sources), &(is_atom(&1) or is_binary(&1))) do
      pairs =
        sources
        |> Enum.map(fn {name, value} -> {to_string(name), value} end)
        |> Enum.sort_by(&elem(&1, 0))

      if length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))),
        do: {:ok, pairs},
        else: {:error, :duplicate_name}
    else
      {:error, :invalid_name}
    end
  end

  defp fetch(sources, name) when is_atom(name) or is_binary(name) do
    case Map.fetch(sources, to_string(name)) do
      {:ok, r} -> {:ok, r}
      :error -> {:error, :unknown_model}
    end
  end

  defp fetch(_, _), do: {:error, :invalid_name}

  defp summary(%Result{} = result) do
    with {:ok, valid} <- OCEx.valid?(result.shape),
         {:ok, volume} <- OCEx.volume(result.shape),
         {:ok, area} <- OCEx.area(result.shape),
         {:ok, counts} <-
           Geometry.collect([:solids, :faces, :edges, :vertices], fn kind ->
             with {:ok, items} <- apply(OCEx, kind, [result.shape]),
                  do: {:ok, {kind, length(items)}}
           end) do
      {:ok,
       %{
         revision: result.revision,
         valid: valid,
         volume_mm3: volume,
         area_mm2: area,
         bounds: bounds(result.shape),
         topology: Map.new(counts)
       }}
    end
  end

  defp bounds(shape) do
    case OCEx.bounds(shape) do
      {:ok, b} -> b
      {:error, :empty_shape} -> nil
    end
  end

  defp solids(shape) do
    case OCEx.solids(shape) do
      {:ok, [_ | _]} -> :ok
      {:ok, []} -> {:error, :wrong_shape_type}
      error -> error
    end
  end

  defp amount(shape, kind), do: apply(OCEx, kind, [shape])

  defp dimension(shape) do
    with {:ok, s} <- OCEx.solids(shape),
         {:ok, f} <- OCEx.faces(shape),
         {:ok, e} <- OCEx.edges(shape) do
      cond do
        s != [] -> {:ok, {:volume, :mm3}}
        f != [] -> {:ok, {:area, :mm2}}
        e != [] -> {:ok, {:length, :mm}}
        true -> {:error, :empty_shape}
      end
    end
  end

  defp tolerance(opts, extra \\ []) do
    if Geometry.options(opts, [:tolerance | extra]) and is_number(opts[:tolerance]) and
         opts[:tolerance] >= 0, do: {:ok, opts[:tolerance]}, else: {:error, :invalid_options}
  end

  defp outcome(kind, names, measured, expected, tolerance, passed, extra),
    do:
      Map.merge(
        %{
          kind: kind,
          models: Enum.map(names, &to_string/1),
          measured: measured,
          expected: expected,
          tolerance: tolerance,
          status: if(passed, do: :passed, else: :failed)
        },
        extra
      )

  defp check({:topology, name, kind, opts}, sources)
       when kind in [:solids, :faces, :edges, :vertices] do
    with true <-
           Geometry.options(opts, [:expected]) and is_integer(opts[:expected]) and
             opts[:expected] >= 0,
         {:ok, result} <- fetch(sources, name),
         {:ok, items} <- apply(OCEx, kind, [result.shape]) do
      {:ok,
       outcome(
         :topology,
         [name],
         length(items),
         opts[:expected],
         0,
         length(items) == opts[:expected],
         %{unit: :count, topology: kind}
       ), nil}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  defp check({:contained, a, b, opts}, sources) do
    with {:ok, tol} <- tolerance(opts),
         {:ok, a_result} <- fetch(sources, a),
         {:ok, b_result} <- fetch(sources, b),
         :ok <- solids(b_result.shape),
         {:ok, {kind, unit}} <- dimension(a_result.shape),
         {:ok, outside} <- OCEx.cut(a_result.shape, b_result.shape),
         {:ok, excess} <- amount(outside, kind),
         {:ok, diagnostic} <- Geometry.snapshot(outside) do
      value =
        outcome(:contained, [a, b], excess, 0, tol, excess <= tol, %{
          unit: unit,
          bounds: bounds(outside)
        })

      {:ok, value, if(excess > tol, do: diagnostic)}
    end
  end

  defp check({:clearance, a, b, opts}, sources) do
    with {:ok, tol} <- tolerance(opts, [:minimum, :volume_tolerance]),
         minimum = opts[:minimum],
         vt = Keyword.get(opts, :volume_tolerance, 1.0e-7),
         true <- is_number(minimum) and minimum >= 0 and is_number(vt) and vt >= 0,
         {:ok, a_result} <- fetch(sources, a),
         {:ok, b_result} <- fetch(sources, b),
         :ok <- solids(a_result.shape),
         :ok <- solids(b_result.shape),
         {:ok, distance} <- OCEx.closest_points(a_result.shape, b_result.shape),
         {:ok, common} <- OCEx.common(a_result.shape, b_result.shape),
         {:ok, volume} <- OCEx.volume(common) do
      extra =
        Map.merge(distance, %{unit: :mm, interference_mm3: volume, volume_tolerance: vt})
        |> Map.delete(:distance)

      {:ok,
       outcome(
         :clearance,
         [a, b],
         distance.distance,
         minimum,
         tol,
         distance.distance + tol >= minimum and volume <= vt,
         extra
       ), nil}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  defp check({:bounds, name, {low, high}, opts}, sources) do
    with {:ok, tol} <- tolerance(opts),
         true <-
           Geometry.point?(low) and Geometry.point?(high) and
             Enum.all?(0..2, &(elem(low, &1) <= elem(high, &1))),
         {:ok, result} <- fetch(sources, name),
         {:ok, {a, b}} <- OCEx.bounds(result.shape) do
      excess =
        Enum.flat_map(0..2, fn i -> [elem(low, i) - elem(a, i), elem(b, i) - elem(high, i), 0] end)
        |> Enum.max()

      {:ok,
       outcome(:bounds, [name], {a, b}, {low, high}, tol, excess <= tol, %{
         unit: :mm,
         excess_mm: excess
       }), nil}
    else
      false -> {:error, :invalid_bounds}
      error -> error
    end
  end

  defp check({:measurement, name, %Measure{} = m, opts}, sources) do
    with {:ok, tol} <- tolerance(opts, [:expected]),
         :ok <- if(is_number(opts[:expected]), do: :ok, else: {:error, :invalid_options}),
         {:ok, result} <- fetch(sources, name),
         true <- result.revision == m.source_revision do
      {:ok,
       outcome(
         :measurement,
         [name],
         m.value,
         opts[:expected],
         tol,
         abs(m.value - opts[:expected]) <= tol,
         %{unit: m.unit, measurement: m}
       ), nil}
    else
      false -> {:error, :revision_mismatch}
      error -> error
    end
  end

  defp check(_, _), do: {:error, :invalid_check}
end
