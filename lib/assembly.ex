defmodule Smith.Assembly do
  @moduledoc """
  Named solid parts and reference geometry with explicit placement.

  An assembly is a deferred value. Add members with `part/4` and
  `reference/4`, then call `Smith.evaluate/1`. Equal member recipes are
  evaluated once per assembly evaluation; each member gets its own placement.
  Use `subassembly/4` to place another assembly and retain its members.
  Equal leaf recipes share one evaluation across the entire tree. There is
  no global cache. Named attachment frames and directed connections provide
  rigid, revolute, linear, cylindrical, and ball poses; closed linkages are not solved.

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
  alias Smith.Assembly.{Frame, Joint, Result}
  defstruct [:name, entries: [], joints: [], connections: []]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          entries: [map()],
          joints: [map()],
          connections: [map()]
        }

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

    * `:position` — translation in the parent frame `{x, y, z}` in mm, default zero.
    * `:rotation` — `{axis_vector, degrees}` about the parent-frame origin,
      applied before `:position`. Default: no rotation.
    * `:installed` — default `true`. Set `false` for a printable extra
      excluded from the installed compound and assembly preview.
    * `:print` — keyword list controlling print placement, described below.
    * `:display_offset` — world offset for the exported preview mesh,
      default zero. Applied by `view/2` in display and exploded modes.
    * `:exploded_offset` — world offset stored in export metadata, default
      zero. Added to display placement by `view/2` in exploded mode.
      Rendering the assembly directly still shows installed geometry.

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

  @doc """
  Adds a named instance of another assembly.

  Child positions and rotations are relative to this instance. Each child
  rotates before translating; the parent transform applies afterwards.
  The same subassembly can be reused under different names and placements.
  Names must be unique among siblings, including parts and references.

  Options are `:position`, `:rotation`, `:installed`,
  `:display_offset`, and `:exploded_offset`, with the defaults from
  `part/4`. Setting `installed: false` excludes the whole branch
  from the parent's installed shape; manufactured leaves still get print
  files. References remain references at every depth.

  Print options belong to leaf parts and operate on their final world shapes.
  Display and exploded offsets are world vectors: offsets at ancestor and
  leaf levels add without rotation. They affect export metadata, not geometry.
  Retrieve an instance or leaf with `fetch/2`; enumerate leaves with
  `members/1`. A subassembly must contain an installed manufactured part
  when evaluated on its own. Invalid recipes return `:invalid_subassembly`.
  """
  @spec subassembly(t(), atom() | String.t(), t(), keyword()) :: t()
  def subassembly(assembly, name, recipe, opts \\ []),
    do: add(assembly, :assembly, name, recipe, opts)

  @doc """
  Defines a named attachment frame on an immediate assembly member.

  Required `on:` names a part, reference, or subassembly at this level.
  `at:` is a `Smith.Plane` or `:xy`, `:xz`, or `:yz`;
  it defaults to `:xy`. The frame is in that member's original recipe
  coordinates, before its placement. Its normal is local Z and its X direction
  fixes rotational alignment. Names are unique in the assembly's joint namespace.

  Frames follow their members through placement and connections. Refer to a
  child assembly's joint with a path such as `[:module, :pin]`. Joint
  definitions and connections are validated when the assembly is evaluated.
  """
  @spec joint(t(), atom() | String.t(), keyword()) :: t()
  def joint(%__MODULE__{} = assembly, name, opts),
    do: %{assembly | joints: assembly.joints ++ [%{name: name, options: opts}]}

  @doc """
  Connects a moving attachment frame to a target frame.

  `source` and required `to:` are joint names or paths to joints in
  nested instances. The source's top-level member moves as a rigid unit,
  including all descendants, references, and extras. The target stays attached
  to its member. Matching frames align both normals and X directions; there
  is no implicit face-to-face reversal. Use opposing local planes when needed.
  The connection overrides the source member's initial placement.

  ## Motion options

  | `kind:` | Coordinates | Meaning |
  | --- | --- | --- |
  | `:rigid` (default) | none | Coincident frames |
  | `:revolute` | `angle:` | Rotation around target local Z, degrees |
  | `:linear` | `offset:` | Translation along target local Z, mm |
  | `:cylindrical` | `angle:`, `offset:` | Both motions |
  | `:ball` | `angles: {x, y, z}` | Rotations about fixed target X, then Y, then Z, degrees |

  All coordinates default to zero. Optional `limits:` supplies inclusive
  `{min, max}` pairs keyed by `:angle`/`:offset`, or by
  `:x`/`:y`/`:z` for a ball. Unspecified limits are unbounded.
  Out-of-range values return `:joint_limit`; they are not clamped.

  Each moving member may have one connection. Dependencies are resolved in
  target-first order, independent of declaration order. Self-connections,
  multiple connections for one member, and cycles fail explicitly. Connections
  inside a subassembly resolve before parent-level connections move that instance.
  This calculates a pose, not a physical simulation or general constraint solver;
  collisions, clearances, loads, and closed linkages are not solved.
  """
  @spec connect(t(), member_path(), keyword()) :: t()
  def connect(%__MODULE__{} = assembly, source, opts),
    do: %{assembly | connections: assembly.connections ++ [%{from: source, options: opts}]}

  @doc """
  Returns a named joint's evaluated world frame and owning member path.

  Accepts a name, slash path, or list as in `fetch/2`. Nested lookup
  prefixes the owner path but leaves the world frame unchanged. Unknown joints
  return `{:error, :unknown_joint}`. The returned `Smith.Assembly.Joint`
  is a snapshot; reevaluate the recipe to change its pose.
  """
  @spec fetch_joint(Result.t(), member_path()) :: {:ok, Joint.t()} | {:error, :unknown_joint}
  def fetch_joint(%Result{} = result, name), do: Joint.fetch(result, name)

  defp add(%__MODULE__{} = assembly, kind, name, recipe, opts),
    do: %{
      assembly
      | entries: assembly.entries ++ [%{name: name, kind: kind, recipe: recipe, options: opts}]
    }

  @doc """
  Returns a member in final world coordinates.

  Works for manufactured parts, uninstalled printable extras, and references.
  Atom and string names match after underscores become hyphens. Unknown
  names return `{:error, :unknown_part}`. Print and display transforms
  do not affect the fetched geometry.

  A subassembly returns a `Smith.Assembly.Result`; a leaf returns a
  `Smith.Result`. Use a list such as `[:left, :foot]` or a slash path
  such as `"left/foot"` to address descendants. Fetching from a returned
  subassembly uses paths relative to it, but its geometry remains in world
  coordinates. Empty paths and descent through a leaf return `:unknown_part`.

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
  @type member_path :: atom() | String.t() | [atom() | String.t()]
  @spec fetch(Result.t(), member_path()) ::
          {:ok, Smith.Result.t() | Result.t()} | {:error, :unknown_part}
  def fetch(%Result{} = result, name), do: fetch_path(result, path(name))

  defp fetch_path(%Result{} = result, [name | rest]) do
    case Enum.find(result.entries, &(&1.key == name)) do
      nil -> {:error, :unknown_part}
      entry when rest == [] -> {:ok, entry.result}
      entry -> fetch_path(entry.result, rest)
    end
  end

  defp fetch_path(_, _), do: {:error, :unknown_part}

  @doc """
  Lists all leaf members in depth-first insertion order.

  Returns `{:ok, members}`. Each map contains normalized `:path`
  segments, a slash-separated `:key`, the original leaf `:name`,
  `:kind` (`:part` or `:reference`), its world-space `:result`,
  `:options`, and effective `:installed`. A manufactured leaf is
  installed only if it and all its ancestor instances are installed;
  references are never installed manufactured geometry.

  Options include accumulated world display/exploded offsets and effective
  installed status. Print options are unchanged. This is the same leaf view
  used by assembly export. Neither enumeration nor lookup evaluates recipes.
  """
  @spec members(Result.t()) :: {:ok, [map()]}
  def members(%Result{} = result), do: {:ok, leaves(result, [], true, {0, 0, 0}, {0, 0, 0})}

  @doc """
  Builds a geometry snapshot of an evaluated assembly for inspection.

  Returns `{:ok, %Smith.Result{}}`, suitable for `Smith.Kino.render/2`.
  The mode selects which manufactured parts and offsets to show:

    * `:installed` (default) reuses the installed shape and its revision.
    * `:display` includes all manufactured leaves, including uninstalled
      extras, and applies their accumulated `:display_offset`.
    * `:exploded` adds accumulated `:exploded_offset` to the display offset.

  Nested placement and joint connections have already been resolved. Offsets
  are world vectors; parent and leaf offsets add without rotation. References
  are excluded in all modes. Fetch a reference with `fetch/2` to inspect it.

  This does not reevaluate recipes or apply print transforms. It preserves the
  assembly and returns an unfused snapshot with a matching BREP revision. Export
  the original assembly to retain part names, separate files, and print placement;
  the view is only a combined shape, without assembly metadata.

  Revision and native geometry failures return tagged errors. An unsupported
  mode returns `:invalid_options`; an unevaluated input returns
  `:invalid_argument`.
  """
  @spec view(Result.t(), :installed | :display | :exploded) ::
          {:ok, Smith.Result.t()} | {:error, term()}
  def view(result, mode \\ :installed)

  def view(%Result{} = result, mode) when mode in [:installed, :display, :exploded] do
    with :ok <- validate_result(result), do: view_shape(result, mode)
  end

  def view(%Result{}, _), do: {:error, :invalid_options}
  def view(_, _), do: {:error, :invalid_argument}

  defp view_shape(result, :installed),
    do: {:ok, %Smith.Result{shape: result.shape, revision: result.revision}}

  defp view_shape(result, mode) do
    {:ok, members} = members(result)

    members
    |> Enum.filter(&(&1.kind == :part))
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, shapes} ->
      display = Keyword.fetch!(member.options, :display_offset)
      exploded = Keyword.fetch!(member.options, :exploded_offset)
      offset = if mode == :exploded, do: Smith.Plane.add(display, exploded), else: display

      case OCEx.translate(member.result.shape, offset) do
        {:ok, shape} -> {:cont, {:ok, [shape | shapes]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, shapes} ->
        with {:ok, shape} <- OCEx.compound(Enum.reverse(shapes)),
             {:ok, brep} <- OCEx.to_brep(shape),
             do: {:ok, %Smith.Result{shape: shape, revision: hash(brep)}}

      error ->
        error
    end
  end

  defp leaves(result, prefix, installed, display, exploded) do
    Enum.flat_map(result.entries, fn entry ->
      path = prefix ++ [entry.key]
      installed = installed and Keyword.get(entry.options, :installed, true)
      display = Smith.Plane.add(display, Keyword.get(entry.options, :display_offset, {0, 0, 0}))

      exploded =
        Smith.Plane.add(exploded, Keyword.get(entry.options, :exploded_offset, {0, 0, 0}))

      if entry.kind == :assembly do
        leaves(entry.result, path, installed, display, exploded)
      else
        installed = installed and entry.kind == :part

        opts =
          entry.options
          |> Keyword.put(:installed, installed)
          |> Keyword.put(:display_offset, display)
          |> Keyword.put(:exploded_offset, exploded)

        [
          Map.merge(entry, %{
            path: path,
            key: Enum.join(path, "/"),
            installed: installed,
            options: opts
          })
        ]
      end
    end)
  end

  @doc false
  def evaluate(%__MODULE__{} = assembly) do
    case evaluate_cached(assembly, %{}) do
      {:ok, result, _cache} -> {:ok, result}
      error -> error
    end
  end

  defp build(%__MODULE__{} = assembly, cache) do
    with true <- valid_name?(assembly.name),
         :ok <- validate_entries(assembly.entries),
         {:ok, entries, cache} <- evaluate_entries(assembly.entries, cache),
         {:ok, entries, joints, connections} <-
           Joint.resolve(entries, assembly.joints, assembly.connections, &move_entry/2),
         {:ok, result} <- collect(assembly.name, entries) do
      {:ok, %{result | joints: joints, connections: connections}, cache}
    else
      false -> {:error, :invalid_assembly_name}
      error -> error
    end
  end

  defp build(%Model{} = recipe, cache) do
    with {:ok, result} <- Smith.evaluate(recipe), do: {:ok, result, cache}
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
      case check_result(entry.result) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_result(%Result{} = result), do: validate_result(result)

  defp check_result(%Smith.Result{} = result) do
    with {:ok, brep} <- OCEx.to_brep(result.shape),
         true <- hash(brep) == result.revision do
      :ok
    else
      false -> {:error, :revision_mismatch}
      error -> error
    end
  end

  defp validate_entries(entries) do
    Enum.reduce_while(entries, {:ok, MapSet.new()}, fn entry, {:ok, names} ->
      reason =
        cond do
          not valid_name?(entry.name) ->
            :invalid_part_name

          MapSet.member?(names, key(entry.name)) ->
            :duplicate_part

          entry.kind == :assembly and not match?(%__MODULE__{}, entry.recipe) ->
            :invalid_subassembly

          entry.kind != :assembly and not match?(%Model{}, entry.recipe) ->
            :invalid_part_model

          not valid_options?(entry.kind, entry.options) ->
            :invalid_options

          true ->
            nil
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

  defp evaluate_entries(entries, cache) do
    Enum.reduce_while(entries, {:ok, [], cache}, fn entry, {:ok, results, cache} ->
      with {:ok, base, cache} <- evaluate_cached(entry.recipe, cache),
           {:ok, result} <- place(base, entry.options),
           {:ok, solids} when solids != [] <- OCEx.solids(result.shape) do
        evaluated =
          entry
          |> Map.delete(:recipe)
          |> Map.merge(%{
            key: key(entry.name),
            result: result,
            pose: Frame.placement(entry.options)
          })

        {:cont, {:ok, [evaluated | results], cache}}
      else
        {:error, %Error{} = error} ->
          part =
            if error.part, do: key(entry.name) <> "/" <> key(error.part), else: entry.name

          {:halt, {:error, %{error | part: part}}}

        {:error, reason} ->
          {:halt, failure(entry.name, reason)}

        {:ok, []} ->
          {:halt, failure(entry.name, :no_solids)}
      end
    end)
    |> case do
      {:ok, entries, cache} -> {:ok, Enum.reverse(entries), cache}
      error -> error
    end
  end

  defp evaluate_cached(recipe, cache) do
    case Map.fetch(cache, recipe) do
      {:ok, result} ->
        {:ok, result, cache}

      :error ->
        with {:ok, result, cache} <- build(recipe, cache),
             do: {:ok, result, Map.put(cache, recipe, result)}
    end
  end

  defp move_entry(entry, frame) do
    with {:ok, result} <- place(entry.result, Frame.options(frame)),
         do: {:ok, %{entry | result: result, pose: Frame.compose(frame, entry.pose)}}
  end

  defp place(%Result{} = result, opts) do
    frame = Frame.placement(opts)

    Enum.reduce_while(result.entries, {:ok, []}, fn entry, {:ok, entries} ->
      case place(entry.result, opts) do
        {:ok, child} ->
          {:cont,
           {:ok, [%{entry | result: child, pose: Frame.compose(frame, entry.pose)} | entries]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} ->
        with {:ok, placed} <- collect(result.name, Enum.reverse(entries)),
             do:
               {:ok,
                %{
                  placed
                  | joints: Joint.placed(result.joints, frame),
                    connections: result.connections
                }}

      error ->
        error
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
          entry.kind in [:part, :assembly],
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
        case kind do
          :part -> [:print, :installed, :display_offset, :exploded_offset]
          :assembly -> [:installed, :display_offset, :exploded_offset]
          :reference -> []
        end

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
  def path_key(name) do
    case path(name) do
      [] -> nil
      parts -> Enum.join(parts, "/")
    end
  end

  defp path(name) when is_binary(name), do: path(String.split(name, "/"))
  defp path(name) when is_atom(name), do: path([name])

  defp path(parts) when is_list(parts) do
    if parts != [] and Enum.all?(parts, &valid_name?/1), do: Enum.map(parts, &key/1), else: []
  end

  defp path(_), do: []

  @doc false
  def key(name) when is_atom(name) or is_binary(name),
    do: name |> to_string() |> String.replace("_", "-")

  def key(_), do: nil
  @doc false
  def valid_name?(name),
    do: is_binary(key(name)) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, key(name))
end
