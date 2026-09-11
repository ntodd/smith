defmodule Smith.Assembly.Result do
  @moduledoc """
  An evaluated assembly and its placed members.

    * `:name` — the original assembly recipe name.
    * `:shape` — an unfused compound of installed manufactured parts.
    * `:revision` — SHA-256 of that compound's serialized BREP.
    * `:entries` — all members in insertion order, including references
      and uninstalled extras.

  Each entry contains `:name`, normalized `:key`, `:kind` (`:part` or
  `:reference`), `:options`, and its placed `:result`. Prefer
  `Smith.Assembly.fetch/2` for name lookup. Treat these fields as read-only.

  The assembly revision excludes references, printable extras, and export
  settings. It does not identify the entire design configuration. Export
  checks every member revision and assigns a separate unique export ID.
  """
  defstruct [:name, :shape, :revision, entries: []]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          shape: OCEx.Shape.t(),
          revision: String.t(),
          entries: [map()]
        }
end

defmodule Smith.Assembly do
  @moduledoc """
  Named solid parts and reference geometry with explicit placement.

  An assembly is a deferred value. Add members with `part/4` and
  `reference/4`, then call `Smith.evaluate/1`. Equal member recipes are
  evaluated once per assembly evaluation; each member gets its own placement.
  There is no global cache, mating solver, or nested assembly support.

      iex> foot = Smith.box(10, 10, 4)
      iex> recipe =
      ...>   Smith.Assembly.new(:pair)
      ...>   |> Smith.Assembly.part(:left, foot)
      ...>   |> Smith.Assembly.part(:right, foot, position: {20, 0, 0})
      iex> {:ok, assembly} = Smith.evaluate(recipe)
      iex> {:ok, solids} = OCEx.solids(assembly.shape)
      iex> length(solids)
      2

  The evaluated compound contains installed manufactured parts, without
  fusing them. References and `installed: false` extras are available
  through `fetch/2` but excluded from that compound. All members must
  contain at least one solid.

  See [assemblies](assemblies.html) for print placement, separate part
  exports, metadata, and assembly reports.
  """
  alias Smith.{Error, Model}
  alias Smith.Assembly.Result
  defstruct [:name, entries: []]
  @type t :: %__MODULE__{name: atom() | String.t(), entries: [map()]}

  @doc """
  Creates an empty named assembly recipe.

  Names are atoms or strings beginning with an ASCII letter or digit,
  followed by letters, digits, underscores, or hyphens. Validation occurs
  at evaluation. Add at least one installed part before evaluating;
  otherwise the result is `{:error, :no_installed_parts}`.
  """
  @spec new(atom() | String.t()) :: t()
  def new(name), do: %__MODULE__{name: name}

  @doc """
  Adds a named manufactured part to an assembly recipe.

  `recipe` must be a `Smith.Model` that evaluates to geometry containing
  at least one solid. Multiple solids are allowed. Names follow `new/1`
  and must be unique across parts and references, after replacing underscores
  with hyphens. Names remain case-sensitive.

  ## Options

    * `:position` — world translation `{x, y, z}` in mm, default zero.
    * `:rotation` — `{axis_vector, degrees}` about the world origin,
      applied before `:position`. Default: no rotation.
    * `:installed` — default `true`. Set `false` for a printable extra
      excluded from the installed compound and assembly preview.
    * `:print` — keyword list controlling print placement, described below.
    * `:display_offset` — world offset for the exported preview mesh,
      default zero. Does not affect `Smith.Kino` previews.
    * `:exploded_offset` — world offset stored in export metadata, default
      zero. No geometry is moved automatically by this option.

  Print placement starts from the **installed shape**. Within `:print`,
  `:rotation` uses `{axis_vector, degrees}` about world zero, followed by
  `:offset` (a world translation). Alternatively, `on_bed: true` centers
  the rotated bounds in XY and places minimum Z at zero. It cannot be
  combined with `:offset`. Defaults apply no print transform.

  Options are checked during evaluation; unknown or duplicate keys fail
  with a `Smith.Error` identifying this part. Print placement is applied
  only at export, so geometrically invalid print transforms can fail there.
  """
  @spec part(t(), atom() | String.t(), Model.t(), keyword()) :: t()
  def part(assembly, name, recipe, opts \\ []), do: add(assembly, :part, name, recipe, opts)

  @doc """
  Adds named reference geometry that is excluded from print output.

  Accepts the same names and solid-containing model recipes as `part/4`,
  but only its `:position` and `:rotation` options. References are
  evaluated and can fail an assembly build. Retrieve one with `fetch/2`.

  References are absent from the installed compound and its Kino preview.
  When STEP is requested, export writes them into a separate
  `references-DO-NOT-PRINT.step`. They never enter the print pack.
  """
  @spec reference(t(), atom() | String.t(), Model.t(), keyword()) :: t()
  def reference(assembly, name, recipe, opts \\ []),
    do: add(assembly, :reference, name, recipe, opts)

  defp add(%__MODULE__{} = assembly, kind, name, recipe, opts),
    do: %{
      assembly
      | entries: assembly.entries ++ [%{name: name, kind: kind, recipe: recipe, options: opts}]
    }

  @doc """
  Returns a named member's evaluated `Smith.Result` in installed coordinates.

  Works for manufactured parts, uninstalled printable extras, and references.
  Atom and string names match after underscores become hyphens. Unknown
  names return `{:error, :unknown_part}`. Print and display transforms
  do not affect the fetched geometry.

      iex> recipe =
      ...>   Smith.Assembly.new(:mount)
      ...>   |> Smith.Assembly.part(:left_foot, Smith.box(2, 3, 4),
      ...>     position: {10, 0, 0}
      ...>   )
      iex> {:ok, assembly} = Smith.evaluate(recipe)
      iex> {:ok, foot} = Smith.Assembly.fetch(assembly, "left-foot")
      iex> OCEx.bounds(foot.shape)
      {:ok, {{10.0, 0.0, 0.0}, {12.0, 3.0, 4.0}}}
      iex> Smith.Assembly.fetch(assembly, :missing)
      {:error, :unknown_part}
  """
  @spec fetch(Result.t(), atom() | String.t()) :: {:ok, Smith.Result.t()} | {:error, atom()}
  def fetch(%Result{} = result, name) do
    case Enum.find(result.entries, &(&1.key == key(name))) do
      nil -> {:error, :unknown_part}
      entry -> {:ok, entry.result}
    end
  end

  @doc false
  def evaluate(%__MODULE__{} = assembly) do
    with true <- valid_name?(assembly.name),
         :ok <- validate_entries(assembly.entries),
         {:ok, entries} <- evaluate_entries(assembly.entries),
         {:ok, result} <- collect(assembly.name, entries) do
      {:ok, result}
    else
      false -> {:error, :invalid_assembly_name}
      error -> error
    end
  end

  @doc false
  def validate_result(%Result{} = result) do
    with :ok <- check_revisions(result.entries),
         {:ok, rebuilt} <- collect(result.name, result.entries),
         {:ok, brep} <- OCEx.to_brep(result.shape),
         true <- rebuilt.revision == result.revision and hash(brep) == result.revision do
      :ok
    else
      false -> {:error, :revision_mismatch}
      error -> error
    end
  end

  defp check_revisions(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case OCEx.to_brep(entry.result.shape) do
        {:ok, brep} ->
          if hash(brep) == entry.result.revision,
            do: {:cont, :ok},
            else: {:halt, {:error, :revision_mismatch}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp validate_entries(entries) do
    Enum.reduce_while(entries, {:ok, MapSet.new()}, fn entry, {:ok, names} ->
      reason =
        cond do
          not valid_name?(entry.name) -> :invalid_part_name
          MapSet.member?(names, key(entry.name)) -> :duplicate_part
          not match?(%Model{}, entry.recipe) -> :invalid_part_model
          not valid_options?(entry.kind, entry.options) -> :invalid_options
          true -> nil
        end

      if reason,
        do: {:halt, failure(entry.name, reason)},
        else: {:cont, {:ok, MapSet.put(names, key(entry.name))}}
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp evaluate_entries(entries) do
    Enum.reduce_while(entries, {:ok, [], %{}}, fn entry, {:ok, results, cache} ->
      with {:ok, base} <- cached(entry.recipe, cache),
           {:ok, result} <- place(base, entry.options),
           {:ok, solids} when solids != [] <- OCEx.solids(result.shape) do
        evaluated =
          entry |> Map.delete(:recipe) |> Map.merge(%{key: key(entry.name), result: result})

        {:cont, {:ok, [evaluated | results], Map.put(cache, entry.recipe, base)}}
      else
        {:error, %Error{} = error} -> {:halt, {:error, %{error | part: entry.name}}}
        {:error, reason} -> {:halt, failure(entry.name, reason)}
        {:ok, []} -> {:halt, failure(entry.name, :no_solids)}
      end
    end)
    |> case do
      {:ok, entries, _} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp cached(recipe, cache) do
    case Map.fetch(cache, recipe) do
      {:ok, result} -> {:ok, result}
      :error -> Smith.evaluate(recipe)
    end
  end

  defp place(result, opts) do
    if Keyword.has_key?(opts, :rotation) or Keyword.has_key?(opts, :position) do
      with {:ok, shape} <- rotate(result.shape, opts[:rotation]),
           {:ok, shape} <- OCEx.translate(shape, Keyword.get(opts, :position, {0, 0, 0})),
           {:ok, brep} <- OCEx.to_brep(shape),
           do: {:ok, %Smith.Result{shape: shape, revision: hash(brep)}}
    else
      {:ok, result}
    end
  end

  defp collect(name, entries) do
    shapes =
      for entry <- entries,
          entry.kind == :part,
          Keyword.get(entry.options, :installed, true),
          do: entry.result.shape

    if shapes == [] do
      {:error, :no_installed_parts}
    else
      with {:ok, shape} <- OCEx.compound(shapes),
           {:ok, true} <- OCEx.valid?(shape),
           {:ok, brep} <- OCEx.to_brep(shape),
           do: {:ok, %Result{name: name, entries: entries, shape: shape, revision: hash(brep)}}
    end
  end

  defp valid_options?(kind, opts) do
    allowed =
      [:position, :rotation] ++
        if(kind == :part, do: [:print, :installed, :display_offset, :exploded_offset], else: [])

    keyword?(opts, allowed) and
      vector?(Keyword.get(opts, :position, {0, 0, 0})) and
      rotation?(opts[:rotation]) and
      vector?(Keyword.get(opts, :display_offset, {0, 0, 0})) and
      vector?(Keyword.get(opts, :exploded_offset, {0, 0, 0})) and
      Keyword.get(opts, :installed, true) in [true, false] and
      print_options?(Keyword.get(opts, :print, []))
  end

  defp print_options?(opts) do
    keyword?(opts, [:rotation, :offset, :on_bed]) and rotation?(opts[:rotation]) and
      vector?(Keyword.get(opts, :offset, {0, 0, 0})) and
      Keyword.get(opts, :on_bed, false) in [true, false] and
      not (opts[:on_bed] == true and Keyword.has_key?(opts, :offset))
  end

  defp keyword?(opts, allowed),
    do:
      is_list(opts) and Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Enum.all?(Keyword.keys(opts), &(&1 in allowed))

  defp vector?({x, y, z}), do: is_number(x) and is_number(y) and is_number(z)
  defp vector?(_), do: false
  defp rotation?(nil), do: true

  defp rotation?({{x, y, z} = axis, degrees}),
    do: vector?(axis) and is_number(degrees) and x * x + y * y + z * z > 0

  defp rotation?(_), do: false
  defp rotate(shape, nil), do: {:ok, shape}
  defp rotate(shape, {axis, degrees}), do: OCEx.rotate(shape, {0, 0, 0}, axis, degrees)

  defp failure(part, reason),
    do: {:error, %Error{part: part, operation: :assembly, reason: reason}}

  defp hash(brep), do: :crypto.hash(:sha256, brep) |> Base.encode16(case: :lower)

  @doc false
  def key(name) when is_atom(name) or is_binary(name),
    do: name |> to_string() |> String.replace("_", "-")

  def key(_), do: nil
  @doc false
  def valid_name?(name),
    do: is_binary(key(name)) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, key(name))
end
