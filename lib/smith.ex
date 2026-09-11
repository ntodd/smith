defmodule Smith.Model do
  @moduledoc """
  A deferred sequence of modeling operations.

  Build recipes with `Smith` functions and pass them to `Smith.evaluate/1`.
  Each operation returns a new recipe; earlier values remain reusable.
  Construction does not allocate native geometry.

  The `:operations` field is an internal representation stored in reverse
  construction order. Do not build or edit it directly. Retain your Elixir
  source as the editable design.
  """
  defstruct operations: []
  @type t :: %__MODULE__{operations: list()}
end

defmodule Smith.Result do
  @moduledoc """
  An evaluated shape and its BREP content hash.

  `:shape` is an `OCEx.Shape` for native queries, and `:revision` is the
  lowercase SHA-256 hash of its serialized BREP. A result may hold an edge,
  face, solid, or compound; it does not necessarily describe a printable part.

  Pass the result to `Smith.export/3` or `Smith.Kino.render/2`. Treat the
  fields as read-only. Export checks the shape against its revision.

  The revision identifies serialized geometry, not design intent or feature
  history. Equal-looking geometry can have different hashes, and hashes are
  not promised stable across OCCT versions or platforms.
  """
  defstruct [:shape, :revision]
  @type t :: %__MODULE__{shape: OCEx.Shape.t(), revision: String.t()}
end

defmodule Smith.Error do
  @moduledoc """
  A failed modeling step, optionally associated with an assembly part.

    * `:step` — one-based operation index in construction order, or `nil`
      for an assembly member validation failure.
    * `:operation` — the failed recipe operation, or `:assembly`.
    * `:reason` — an error atom or a nested `Smith.Error` from a tool recipe.
    * `:part` — the original assembly member name, or `nil` outside an assembly.

  This is a result value, not an exception. Match on it in
  `{:error, %Smith.Error{}}`. Some top-level failures return bare atoms;
  callback exceptions propagate instead of becoming this struct.
  """
  defstruct [:part, :step, :operation, :reason]

  @type t :: %__MODULE__{
          part: atom() | String.t() | nil,
          step: pos_integer() | nil,
          operation: atom(),
          reason: atom() | t()
        }
end

defmodule Smith do
  @moduledoc """
  CAD recipes built with Elixir functions and pipelines.

  Constructors and modeling operations return immutable `Smith.Model`
  values. `evaluate/1` executes the recipe through OCEx and returns native
  geometry. Use ordinary functions for features and comprehensions for
  patterns; no process or mutable modeling context is required.

      iex> model =
      ...>   Smith.box(60, 40, 5)
      ...>   |> Smith.fillet(edges: {:parallel, :z}, radius: 2, count: 4)
      ...>   |> Smith.hole(on: :top, diameter: 8, through: :all)
      iex> {:ok, part} = Smith.evaluate(model)
      iex> {:ok, [solid]} = OCEx.solids(part.shape)
      iex> OCEx.valid?(solid)
      {:ok, true}

  ## Units and coordinates

  Dimensions are millimeters and modeling angles are degrees. Transforms
  use world coordinates; sketches use a `Smith.Plane` with local 2D
  coordinates. Mesh angular tolerance is in radians.

  Boxes begin at the origin by default. Cylinders and cones are centered
  on world Z with their bottoms at Z=0. All three support explicit placement
  with `:at` and per-axis `:align`.

  ## Where to start

    * [Getting started](getting-started.html) — a complete script and first export.
    * `Smith.Sketch` — 2D outlines, cutouts, and planes.
    * `Smith.Assembly` — named parts, references, and print placement.
    * `Smith.Export` — files, mesh checks, and export records.
    * `Smith.Kino` — interactive Livebook previews.

  Recipe validation runs during evaluation. Use valid structs and documented
  argument types; arbitrary malformed Elixir terms and callback exceptions
  are not converted into modeling errors. See [errors and limits](errors-and-limits.html).
  """
  @moduledoc groups: ["Primitives", "Profiles", "Modeling", "Evaluation and export"]
  alias Smith.{Model, Result, Error}

  @type alignment :: {:min | :center | :max, :min | :center | :max, :min | :center | :max}
  @type primitive_option :: {:at, OCEx.point3()} | {:align, alignment()}

  @doc """
  Describes a box with X, Y, and Z dimensions in millimeters.

  Returns a recipe. Geometry is built by `evaluate/1`; each dimension must
  exceed the native linear tolerance of 1.0e-7 mm.

  ## Placement options

    * `:at` — world anchor `{x, y, z}`; defaults to `{0, 0, 0}`.
    * `:align` — one of `:min`, `:center`, or `:max` for each axis;
      defaults to `{:min, :min, :min}`.

  Alignment chooses the point of the unrotated bounding box that lands at
  `:at`. For example, `{:center, :center, :min}` centers the footprint
  and places its bottom at the anchor's Z coordinate. Later transformations
  act on this placed geometry.

  Unknown or duplicate options, malformed points, and invalid alignments
  produce a `Smith.Error` with reason `:invalid_options` at evaluation.
  Invalid native dimensions or numbers produce `:invalid_argument`.

  ## Examples

      iex> model = Smith.box(20, 10, 4, at: {0, 0, 6}, align: {:center, :center, :min})
      iex> {:ok, part} = Smith.evaluate(model)
      iex> OCEx.bounds(part.shape)
      {:ok, {{-10.0, -5.0, 6.0}, {10.0, 5.0, 10.0}}}
  """
  @doc group: "Primitives"
  @spec box(number(), number(), number(), [primitive_option()]) :: Model.t()
  def box(x, y, z, opts \\ []), do: primitive(:box, [x, y, z], opts)

  @doc """
  Describes a cylinder along world +Z, using radius and height in mm.

  Both dimensions must exceed 1.0e-7 mm at evaluation. Supports the
  `:at` and `:align` options of `box/4`, with default alignment
  `{:center, :center, :min}`: the axis passes through the anchor's XY
  coordinates and the bottom starts at its Z coordinate.

      iex> {:ok, pin} = Smith.cylinder(2, 8, at: {10, 0, 3}) |> Smith.evaluate()
      iex> OCEx.bounds(pin.shape)
      {:ok, {{8.0, -2.0, 3.0}, {12.0, 2.0, 11.0}}}
  """
  @doc group: "Primitives"
  @spec cylinder(number(), number(), [primitive_option()]) :: Model.t()
  def cylinder(radius, height, opts \\ []), do: primitive(:cylinder, [radius, height], opts)

  @doc """
  Describes a cone or frustum along world +Z.

  `bottom_radius` is at the bottom and `top_radius` is at the top.
  Radii must be nonnegative and differ by more than 1.0e-7 mm; one may be
  zero. Height must exceed 1.0e-7 mm. Use `cylinder/3` for equal radii.

  Supports the `:at` and `:align` options of `box/4`, defaulting to
  `{:center, :center, :min}`. Bounds include the larger radius. Center
  alignment uses the bounds midpoint, so centered Z is halfway up the
  height regardless of the cone's center of mass.
  """
  @doc group: "Primitives"
  @spec cone(number(), number(), number(), [primitive_option()]) :: Model.t()
  def cone(bottom_radius, top_radius, height, opts \\ []),
    do: primitive(:cone, [bottom_radius, top_radius, height], opts)

  defp primitive(op, args, []), do: new(op, args)
  defp primitive(op, args, opts), do: new(op, args ++ [opts])

  @doc """
  Groups model recipes without fusing their geometry.

  Members can be edges, faces, or solids. Separate boundaries are retained,
  including where members overlap. An empty list evaluates to an empty
  compound. Use `fuse/2` to unite material, or `Smith.Assembly` to name
  parts and export them separately.
  """
  @doc group: "Modeling"
  @spec compound([Model.t()]) :: Model.t()
  def compound(models), do: new(:compound, [models])

  @doc """
  Describes a directed straight edge between two world points.

  The points must be more than 1.0e-7 mm apart. Use ordered edge recipes
  with `profile/1` to make a face. For plane-local 2D edges use
  `Smith.Sketch.line/2`.
  """
  @doc group: "Profiles"
  @spec line(OCEx.point3(), OCEx.point3()) :: Model.t()
  def line(from, to), do: new(:edge, [from, to])

  @doc """
  Describes a circular arc in a world-coordinate plane.

  `center` is the circle center. `normal` and `x_direction` must be
  nonzero and nonparallel; the latter is projected into the plane to set
  zero degrees. Radius must exceed 1.0e-7 mm.

  `start` and signed `sweep` use degrees. Positive sweep follows the
  right-hand rule around the normal. The absolute sweep must be greater
  than 1.0e-9 and at most 360. The recipe evaluates to an edge. For local
  2D coordinates see `Smith.Sketch.arc/4`.
  """
  @doc group: "Profiles"
  @spec arc(OCEx.point3(), OCEx.point3(), OCEx.point3(), number(), number(), number()) ::
          Model.t()
  def arc(center, normal, x_direction, radius, start, sweep),
    do: new(:arc, [center, normal, x_direction, radius, start, sweep])

  @doc """
  Describes an interpolated, nonperiodic B-spline edge in world coordinates.

  Supply 2 to 100,000 points, with consecutive points more than 1.0e-6 mm
  apart. `tangents` is `nil` or `{start_vector, end_vector}`; vectors
  must be nonzero, and OCCT scales their magnitudes. The interpolation
  tolerance is 1.0e-6 mm. These are points on the curve, not control points.
  See `OCEx.spline/2` for the native contract.
  """
  @doc group: "Profiles"
  @spec spline([OCEx.point3()], {OCEx.point3(), OCEx.point3()} | nil) :: Model.t()
  def spline(points, tangents \\ nil), do: new(:spline, [points, tangents])

  @doc """
  Describes a planar face bounded by an ordered list of edge recipes.

  The list must be nonempty, connected, and closed. Open wires fail with
  `:open_wire`; disconnected edges fail with `:disconnected_wire`.
  Nonplanar or invalid boundaries fail in the native kernel. Inner loops
  are not accepted here; use `Smith.Sketch.cut/2` for sketch holes.

      iex> outline = [
      ...>   Smith.line({0, 0, 0}, {4, 0, 0}),
      ...>   Smith.line({4, 0, 0}, {0, 3, 0}),
      ...>   Smith.line({0, 3, 0}, {0, 0, 0})
      ...> ]
      iex> {:ok, face} = Smith.profile(outline) |> Smith.evaluate()
      iex> OCEx.area(face.shape)
      {:ok, 6.0}
  """
  @doc group: "Profiles"
  @spec profile([Model.t()]) :: Model.t()
  def profile(edges), do: new(:profile, [edges])

  @doc """
  Describes a planar polygon face from world-coordinate points.

  Supply at least three points in boundary order. Closure is implicit;
  do not repeat the first point. The outline must form a valid closed
  planar face. For 2D points and workplane placement use
  `Smith.Sketch.polygon/2`.
  """
  @doc group: "Profiles"
  @spec polygon([OCEx.point3()]) :: Model.t()
  def polygon(points), do: new(:polygon, [points])

  @doc """
  Describes an extrusion of a sketch or a face recipe.

  With a `Smith.Sketch`, supply a signed distance in millimeters. Positive
  distance follows its plane normal; negative distance extends behind the
  plane. Zero fails with `:invalid_extrusion`. Sketch holes pass through
  the solid.

  With a `Smith.Model` that evaluates to a planar face, supply a world
  vector `{x, y, z}`. It must have a nonzero normal component; extrusion
  within the face plane fails with `:degenerate_extrusion`. Native length
  tolerances also apply. A scalar distance is only supported for sketches.

      iex> model = Smith.Sketch.rectangle(4, 6) |> Smith.extrude(-2)
      iex> {:ok, part} = Smith.evaluate(model)
      iex> OCEx.bounds(part.shape)
      {:ok, {{-2.0, -3.0, -2.0}, {2.0, 3.0, 0.0}}}
  """
  @doc group: "Profiles"
  @spec extrude(Smith.Sketch.t(), number()) :: Model.t()
  @spec extrude(Model.t(), {number(), number(), number()}) :: Model.t()
  def extrude(%{__struct__: Smith.Sketch} = sketch, distance),
    do: new(:sketch_extrude, [sketch, distance])

  def extrude(model, vector), do: append(model, :extrude, [vector])

  @doc """
  Describes a solid formed by revolving a sketch or face about a world axis.

  `axis` is a nonzero direction vector and `origin` is a point on that
  axis (default `{0, 0, 0}`). `degrees` defaults to 360 and must be
  greater than 1.0e-7 and at most 360. Reverse the axis for the opposite
  turn. Partial revolutions include end faces.

  Place the profile so that its sweep forms valid geometry. Smith checks
  for one solid and volume greater than 1.0e-9 mm³; otherwise evaluation
  returns `:invalid_solid` or a native construction error.

      iex> profile =
      ...>   Smith.Sketch.rectangle(2, 10,
      ...>     align: {:min, :min},
      ...>     at: {4, 0},
      ...>     on: Smith.Plane.xz()
      ...>   )
      iex> {:ok, sleeve} = Smith.revolve(profile, {0, 0, 1}) |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(sleeve.shape)
      iex> abs(volume - :math.pi() * (6 * 6 - 4 * 4) * 10) < 1.0e-6
      true
  """
  @doc group: "Profiles"
  @spec revolve(Smith.Sketch.t() | Model.t(), OCEx.point3(), number(), OCEx.point3()) :: Model.t()
  def revolve(profile, axis, degrees \\ 360, origin \\ {0, 0, 0})

  def revolve(%{__struct__: Smith.Sketch} = sketch, axis, degrees, origin),
    do: new(:sketch, [sketch]) |> revolve(axis, degrees, origin)

  def revolve(model, axis, degrees, origin), do: append(model, :revolve, [origin, axis, degrees])

  @doc """
  Describes a capped, ruled solid through two or more ordered sketches.

  Each sketch uses its own plane and must have exactly one boundary wire.
  Sections with holes fail with `:loft_profile_has_holes`. A cut touching
  the outer edge is allowed if it leaves one boundary. OCCT chooses edge
  correspondence; there are no guide rails, seam controls, or smooth-loft
  options. Smith requires one solid with volume greater than 1.0e-9 mm³.

      iex> sections = [
      ...>   Smith.Sketch.rectangle(20, 10),
      ...>   Smith.Sketch.rectangle(10, 5, on: Smith.Plane.xy(z: 12))
      ...> ]
      iex> {:ok, transition} = Smith.loft(sections) |> Smith.evaluate()
      iex> {:ok, solids} = OCEx.solids(transition.shape)
      iex> length(solids)
      1
  """
  @doc group: "Profiles"
  @spec loft([Smith.Sketch.t()]) :: Model.t()
  def loft(sketches), do: new(:loft, [sketches])

  @doc """
  Appends a world-coordinate translation in millimeters.

  The source recipe remains unchanged. Transformation order matters:
  translating before rotating also rotates the translated position.
  The vector may be zero.
  """
  @doc group: "Modeling"
  @spec translate(Model.t(), OCEx.point3()) :: Model.t()
  def translate(model, vector), do: append(model, :translate, [vector])

  @doc """
  Appends a right-handed rotation in degrees about a world axis.

  `axis` is a nonzero vector. `origin` is a point on the axis and defaults
  to `{0, 0, 0}`; it is not automatically the body's center. Negative and
  zero angles are allowed. Rotation applies to the already placed geometry.
  """
  @doc group: "Modeling"
  @spec rotate(Model.t(), OCEx.point3(), number(), OCEx.point3()) :: Model.t()
  def rotate(model, axis, degrees, origin \\ {0, 0, 0}),
    do: append(model, :rotate, [origin, axis, degrees])

  @doc """
  Appends same-domain face and edge simplification.

  Adjacent faces or edges on compatible underlying geometry may be merged.
  This can change topology and edge counts. Later selectors run against the
  new body. Smith already cleans the results of `fuse/2`, `cut/2`,
  `common/2`, `fillet/2`, and `chamfer/2`.
  """
  @doc group: "Modeling"
  @spec clean(Model.t()) :: Model.t()
  def clean(model), do: append(model, :clean, [])

  @doc """
  Unites a model with one tool recipe or an ordered list of recipes.

  Each tool is evaluated, united with the current body, and followed by
  same-domain cleanup. An empty list returns the original recipe. Disjoint
  inputs can leave multiple solids; this does not fail evaluation.

      iex> base = Smith.box(10, 10, 2)
      iex> boss = Smith.cylinder(2, 4, at: {5, 5, 2})
      iex> {:ok, part} = Smith.fuse(base, boss) |> Smith.evaluate()
      iex> {:ok, solids} = OCEx.solids(part.shape)
      iex> length(solids)
      1
  """
  @doc group: "Modeling"
  @spec fuse(Model.t(), Model.t() | [Model.t()]) :: Model.t()
  def fuse(%Model{} = model, tools) when is_list(tools),
    do: Enum.reduce(tools, model, &fuse(&2, &1))

  def fuse(model, tool), do: append(model, :fuse, [tool])

  @doc """
  Subtracts one tool recipe or an ordered list from the current body.

  Each subtraction is followed by same-domain cleanup. An empty list returns
  the original recipe. A missed tool can leave the geometry unchanged, and
  removing all material can produce an empty compound. Use `hole/2` when
  a missed circular through-cut should fail explicitly.

  Tool evaluation errors appear as a nested `Smith.Error` in the cut
  step's `:reason`. Neither recipe is mutated.
  """
  @doc group: "Modeling"
  @spec cut(Model.t(), Model.t() | [Model.t()]) :: Model.t()
  def cut(%Model{} = model, tools) when is_list(tools),
    do: Enum.reduce(tools, model, &cut(&2, &1))

  def cut(model, tool), do: append(model, :cut, [tool])

  @doc """
  Retains the intersection with a tool recipe, then cleans its topology.

  A disjoint intersection can evaluate successfully to an empty compound.
  Query `OCEx.solids/1` and `OCEx.volume/1` on the result when the design
  requires a solid. Both source recipes remain reusable.
  """
  @doc group: "Modeling"
  @spec common(Model.t(), Model.t()) :: Model.t()
  def common(model, tool), do: append(model, :common, [tool])

  @doc """
  Appends an equal-distance bevel on selected edges.

  Requires `edges:` and `distance:`, with optional positive integer
  `count:`. Selectors and their failure behavior match `fillet/2`.
  Distance is in millimeters and must exceed 1.0e-7. The native kernel can
  reject a distance that does not fit the surrounding geometry.

      iex> recipe =
      ...>   Smith.box(20, 10, 4)
      ...>   |> Smith.chamfer(edges: {:parallel, :z}, distance: 1, count: 4)
      iex> {:ok, part} = Smith.evaluate(recipe)
      iex> {:ok, volume} = OCEx.volume(part.shape)
      iex> abs(volume - 792.0) < 1.0e-6
      true
  """
  @doc group: "Modeling"
  @spec chamfer(Model.t(), keyword()) :: Model.t()
  def chamfer(model, opts), do: append(model, :chamfer, opts)
  defp new(op, args), do: %Model{operations: [{op, args}]}

  defp append(%Model{} = model, op, args),
    do: %{model | operations: [{op, args} | model.operations]}

  @doc """
  Appends constant-radius rounding on selected edges.

  Requires `edges:` and `radius:`. Radius is in millimeters and must
  exceed 1.0e-7. The kernel may reject a radius that does not fit.

  ## Selectors

    * `:all` selects every edge.
    * `{:parallel, :x | :y | :z}` selects straight edges parallel to a world
      axis, in either direction. Curved edges do not match.
    * A one-argument function receives the map from `OCEx.edge_info/1`
      plus `:bounds` and `:midpoint`. It must return `true` or `false`.

  `:bounds` is `{minimum, maximum}` in world coordinates. `:midpoint`
  is the point halfway through the edge's parameter interval; it need not
  be halfway along its length. Selection runs against the current body at
  this step, including earlier transforms and cuts.

  Optional `count:` asserts a positive number of matches. A mismatch gives
  `:selection_count_mismatch`. An empty selection without `count:`
  fails with `:invalid_argument`. Invalid or duplicate options produce
  `:invalid_options`; nonboolean predicate results produce
  `:invalid_selector_result`. Exceptions in your predicate propagate.

      iex> model =
      ...>   Smith.box(20, 10, 4)
      ...>   |> Smith.fillet(edges: {:parallel, :z}, radius: 1, count: 3)
      iex> Smith.evaluate(model)
      {:error, %Smith.Error{step: 2, operation: :fillet, reason: :selection_count_mismatch}}
  """
  @doc group: "Modeling"
  @spec fillet(Model.t(), keyword()) :: Model.t()
  def fillet(%Model{} = model, opts),
    do: %{model | operations: [{:fillet, opts} | model.operations]}

  @doc """
  Appends a circular through-hole along world Z or a plane normal.

  Requires `on:`, `diameter:`, and `through: :all`. Diameter is positive
  and in millimeters; its half-radius must also satisfy OCEx's native
  tolerance. Optional `at: {u, v}` defaults to `{0, 0}`.

    * `on: :top` selects the unique highest planar face with an outward
      +Z normal. `:at` is an XY offset from that face's **area centroid**.
      Earlier cuts can move this centroid.
    * `on: plane` uses plane-local `:at` coordinates and drills along its
      normal. The plane is independent of the body and may lie outside it.

  The cutter extends through the body's full projected bounds, including
  disconnected solids. A cut removing no more than 1.0e-9 mm³ fails with
  `:hole_misses_body`. Top selection can fail with `:no_top_face` or
  `:ambiguous_top_face`. Blind holes are not supported; use `cut/2`
  with a finite cylinder for a chosen depth.

      iex> model =
      ...>   Smith.box(20, 10, 4)
      ...>   |> Smith.hole(
      ...>     on: Smith.Plane.xy(),
      ...>     at: {5, 5},
      ...>     diameter: 2,
      ...>     through: :all
      ...>   )
      iex> {:ok, part} = Smith.evaluate(model)
      iex> OCEx.distance_to_point(part.shape, {5, 5, 2})
      {:ok, 1.0}
  """
  @doc group: "Modeling"
  @spec hole(Model.t(), keyword()) :: Model.t()
  def hole(%Model{} = model, opts), do: %{model | operations: [{:hole, opts} | model.operations]}

  @spec evaluate(Model.t() | Smith.Assembly.t() | Smith.Sketch.t()) ::
          {:ok, Result.t() | Smith.Assembly.Result.t()} | {:error, Error.t() | atom()}
  @doc """
  Builds native geometry from a model, sketch, or assembly recipe.

  Returns `{:ok, %Smith.Result{}}` for models and sketches, or
  `{:ok, %Smith.Assembly.Result{}}` for assemblies. A bare sketch becomes
  a face; edge recipes and empty compounds can also evaluate successfully.
  Successful evaluation alone does not establish printability.

  Model operations execute in construction order. Failures return
  `{:error, %Smith.Error{step: index, operation: name, reason: reason}}`;
  the index starts at 1. Assemblies also identify the failed part where
  available. Final shape checks and top-level validation can return a bare
  error atom. Empty models return `:empty_model`; unsupported top-level
  terms return `:invalid_recipe`.

  Evaluation is synchronous. It rebuilds a recipe on each call, except that
  equal member recipes within one assembly evaluation share their base
  evaluation. User callback exceptions are not caught. See the
  [error guide](errors-and-limits.html) for details.

      iex> Smith.box(0, 10, 4) |> Smith.evaluate()
      {:error, %Smith.Error{step: 1, operation: :box, reason: :invalid_argument}}
      iex> Smith.evaluate(nil)
      {:error, :invalid_recipe}
  """
  @doc group: "Evaluation and export"
  def evaluate(%{__struct__: Smith.Assembly} = assembly), do: Smith.Assembly.evaluate(assembly)

  def evaluate(%{__struct__: Smith.Sketch} = sketch), do: evaluate(new(:sketch, [sketch]))

  def evaluate(%Model{operations: []}), do: {:error, :empty_model}

  def evaluate(%Model{operations: operations}) do
    operations
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, nil}, fn {{operation, args}, index}, {:ok, body} ->
      case apply_operation(operation, body, args) do
        {:ok, next} ->
          {:cont, {:ok, next}}

        {:error, reason} ->
          {:halt, {:error, %Error{step: index, operation: operation, reason: reason}}}
      end
    end)
    |> finish()
  end

  def evaluate(_), do: {:error, :invalid_recipe}

  @doc """
  Writes one geometry file, choosing its format from the path extension.

  Accepts an evaluated `Smith.Result`. Extensions are case-insensitive:
  `.step` and `.stp` write STEP; `.stl` writes binary STL. Other extensions,
  including `.3mf`, return `{:error, :unsupported_format}`.

  Returns `{:ok, :ok}` on success. Existing files are overwritten and the
  parent directory must already exist. STL uses OCEx defaults of 0.1 mm
  linear and 0.5 rad angular deflection. This function does not perform the
  bundle's mesh/STEP checks or update a manifest.

  For 3MF, configurable mesh settings, and print placement, use `export/3`.
  """
  @doc group: "Evaluation and export"
  @spec export(Result.t(), String.t()) :: {:ok, :ok} | {:error, atom()}
  def export(%Result{shape: shape}, path) do
    case String.downcase(Path.extname(path)) do
      ".step" -> OCEx.write_step(shape, path)
      ".stp" -> OCEx.write_step(shape, path)
      ".stl" -> OCEx.write_stl(shape, path)
      _ -> {:error, :unsupported_format}
    end
  end

  @doc """
  Writes a part or assembly bundle and updates the output manifest after checks pass.

  The second argument is an output directory; it is created as needed. Requires
  a string `name:`. Default formats are `[:step, :stl, :three_mf]`; BREP
  snapshots and reports are always included. All bundles require printable
  solids and run mesh checks, even when only STEP is requested.

  For an individual result, options and returned record fields are documented
  in `Smith.Export.write/3`. For an assembly, see the
  [assembly export options](assemblies.html#evaluation-and-export). Assembly
  print placement belongs on its members, not in this option list.

  Returns `{:ok, record}` for a part or `{:ok, report}` for an assembly.
  A failure leaves the previous manifest in place but can leave unpublished
  files in the new export directory. Run writers to one root sequentially.

      {:ok, part} = Smith.box(20, 10, 4) |> Smith.evaluate()
      {:ok, files} = Smith.export(part, "output", name: "block", on_bed: true)
      IO.puts(files.three_mf)
  """
  @doc group: "Evaluation and export"
  @spec export(Result.t() | Smith.Assembly.Result.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def export(%{__struct__: Smith.Assembly.Result} = result, root, opts),
    do: Smith.Assembly.Export.write(result, root, opts)

  def export(result, root, opts), do: Smith.Export.write(result, root, opts)

  defp finish({:ok, shape}) do
    with {:ok, true} <- OCEx.valid?(shape),
         {:ok, brep} <- OCEx.to_brep(shape) do
      revision = :crypto.hash(:sha256, brep) |> Base.encode16(case: :lower)
      {:ok, %Result{shape: shape, revision: revision}}
    else
      {:ok, false} -> {:error, :invalid_shape}
      error -> error
    end
  end

  defp finish(error), do: error

  defp apply_operation(:sketch, nil, [sketch]), do: Smith.Sketch.evaluate(sketch)

  defp apply_operation(:sketch_extrude, nil, [sketch, height]),
    do: Smith.Sketch.extrude(sketch, height)

  defp apply_operation(:loft, nil, [sketches]) when is_list(sketches) and length(sketches) >= 2 do
    with {:ok, wires} <- loft_wires(sketches),
         {:ok, shape} <- OCEx.loft(wires),
         do: single_solid(shape)
  end

  defp apply_operation(:revolve, body, [origin, axis, degrees]) do
    with {:ok, shape} <- OCEx.revolve(body, origin, axis, degrees), do: single_solid(shape)
  end

  defp apply_operation(:box, nil, [x, y, z, opts]),
    do: placed_primitive(:box, [x, y, z], opts, {:min, :min, :min})

  defp apply_operation(:cylinder, nil, [radius, height, opts]),
    do: placed_primitive(:cylinder, [radius, height], opts, {:center, :center, :min})

  defp apply_operation(:cone, nil, [bottom, top, height, opts]),
    do: placed_primitive(:cone, [bottom, top, height], opts, {:center, :center, :min})

  defp apply_operation(:box, nil, [x, y, z]), do: OCEx.box(x, y, z)

  defp apply_operation(op, nil, args) when op in [:cylinder, :cone, :edge, :arc, :spline],
    do: apply(OCEx, op, args)

  defp apply_operation(:polygon, nil, [points]) when is_list(points) and length(points) >= 3 do
    edges =
      (points ++ [hd(points)])
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> line(a, b) end)

    apply_operation(:profile, nil, [edges])
  end

  defp apply_operation(:compound, nil, [models]) when is_list(models) do
    with {:ok, shapes} <- evaluate_edges(models), do: OCEx.compound(shapes)
  end

  defp apply_operation(:profile, nil, [edges]) when is_list(edges) do
    with {:ok, shapes} <- evaluate_edges(edges),
         {:ok, wire} <- OCEx.wire(shapes),
         do: OCEx.face(wire)
  end

  defp apply_operation(op, body, args) when op in [:translate, :rotate, :extrude, :clean],
    do: apply(OCEx, op, [body | args])

  defp apply_operation(op, body, [%Model{} = tool]) when op in [:fuse, :cut, :common] do
    with {:ok, result} <- evaluate(tool),
         {:ok, shape} <- apply(OCEx, op, [body, result.shape]),
         do: OCEx.clean(shape)
  end

  defp apply_operation(op, body, opts) when op in [:fillet, :chamfer] do
    size = if op == :fillet, do: :radius, else: :distance

    with :ok <- options(opts, [:edges, size, :count], [:edges, size]),
         {:ok, selected} <- selected_edges(body, opts[:edges]),
         :ok <- selection_count(selected, Keyword.get(opts, :count)),
         {:ok, shape} <- apply(OCEx, op, [body, selected, opts[size]]),
         do: OCEx.clean(shape)
  end

  defp apply_operation(:hole, body, opts) do
    with :ok <- options(opts, [:on, :diameter, :through, :at], [:on, :diameter, :through]),
         :ok <- hole_options(opts),
         {:ok, placed} <- hole_tool(body, opts),
         {:ok, result} <- OCEx.cut(body, placed),
         {:ok, before_volume} <- OCEx.volume(body),
         {:ok, after_volume} <- OCEx.volume(result) do
      if before_volume - after_volume > 1.0e-9,
        do: {:ok, result},
        else: {:error, :hole_misses_body}
    end
  end

  defp apply_operation(_, _, _), do: {:error, :invalid_operation}

  defp placed_primitive(op, args, opts, default_alignment) do
    with :ok <- options(opts, [:at, :align], []),
         at = Keyword.get(opts, :at, {0, 0, 0}),
         alignment = Keyword.get(opts, :align, default_alignment),
         true <- point3?(at) and alignment?(alignment),
         {:ok, shape} <- apply(OCEx, op, args),
         {:ok, {low, high}} <- OCEx.bounds(shape),
         offset =
           0..2
           |> Enum.map(&(-anchor(elem(low, &1), elem(high, &1), elem(alignment, &1))))
           |> List.to_tuple(),
         {:ok, aligned} <- shift(shape, offset) do
      shift(aligned, at)
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  defp point3?({x, y, z}), do: is_number(x) and is_number(y) and is_number(z)
  defp point3?(_), do: false

  defp alignment?({x, y, z}),
    do: x in [:min, :center, :max] and y in [:min, :center, :max] and z in [:min, :center, :max]

  defp alignment?(_), do: false
  defp anchor(low, _, :min), do: low
  defp anchor(_, high, :max), do: high
  defp anchor(low, high, :center), do: (low + high) / 2

  defp shift(shape, {x, y, z}) when x == 0 and y == 0 and z == 0, do: {:ok, shape}
  defp shift(shape, offset), do: OCEx.translate(shape, offset)

  defp loft_wires(sketches) do
    Enum.reduce_while(sketches, {:ok, []}, fn sketch, {:ok, wires} ->
      with {:ok, face} <- Smith.Sketch.evaluate(sketch),
           {:ok, [wire]} <- OCEx.wires(face) do
        {:cont, {:ok, wires ++ [wire]}}
      else
        {:ok, _} -> {:halt, {:error, :loft_profile_has_holes}}
        error -> {:halt, error}
      end
    end)
  end

  defp single_solid(shape) do
    with {:ok, [_]} <- OCEx.solids(shape),
         {:ok, volume} when volume > 1.0e-9 <- OCEx.volume(shape) do
      {:ok, shape}
    else
      {:ok, _} -> {:error, :invalid_solid}
      error -> error
    end
  end

  defp evaluate_edges(edges) do
    Enum.reduce_while(edges, {:ok, []}, fn edge, {:ok, acc} ->
      case evaluate(edge) do
        {:ok, result} -> {:cont, {:ok, acc ++ [result.shape]}}
        error -> {:halt, error}
      end
    end)
  end

  defp selection_count(_, nil), do: :ok

  defp selection_count(edges, n) when is_integer(n) and n > 0 do
    if length(edges) == n, do: :ok, else: {:error, :selection_count_mismatch}
  end

  defp selection_count(_, _), do: {:error, :invalid_options}

  defp selected_edges(body, :all), do: OCEx.edges(body)

  defp selected_edges(body, predicate) when is_function(predicate, 1) do
    with {:ok, edges} <- OCEx.edges(body) do
      Enum.reduce_while(edges, {:ok, []}, fn edge, {:ok, selected} ->
        with {:ok, info} <- OCEx.edge_info(edge),
             {:ok, bounds} <- OCEx.bounds(edge),
             {:ok, sample} <- OCEx.edge_sample(edge, 0.5) do
          case predicate.(Map.merge(info, %{bounds: bounds, midpoint: sample.point})) do
            true -> {:cont, {:ok, selected ++ [edge]}}
            false -> {:cont, {:ok, selected}}
            _ -> {:halt, {:error, :invalid_selector_result}}
          end
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  defp selected_edges(body, selector) do
    with {:ok, axis} <- axis_index(selector),
         {:ok, edges} <- OCEx.edges(body),
         do: select_edges(edges, axis)
  end

  defp options(opts, allowed, required) do
    if is_list(opts) and Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
         Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
         Enum.all?(required, &Keyword.has_key?(opts, &1)),
       do: :ok,
       else: {:error, :invalid_options}
  end

  defp axis_index({:parallel, :x}), do: {:ok, 0}
  defp axis_index({:parallel, :y}), do: {:ok, 1}
  defp axis_index({:parallel, :z}), do: {:ok, 2}
  defp axis_index(_), do: {:error, :invalid_options}

  defp select_edges(edges, axis) do
    Enum.reduce_while(edges, {:ok, []}, fn edge, {:ok, selected} ->
      case OCEx.edge_info(edge) do
        {:ok, %{type: :line, direction: direction}} ->
          if abs(elem(direction, axis)) > 1 - 1.0e-9,
            do: {:cont, {:ok, [edge | selected]}},
            else: {:cont, {:ok, selected}}

        {:ok, _} ->
          {:cont, {:ok, selected}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp hole_options(opts) do
    with true <-
           (opts[:on] == :top or match?(%{__struct__: Smith.Plane}, opts[:on])) and
             opts[:through] == :all,
         diameter when is_number(diameter) and diameter > 0 <- opts[:diameter],
         {x, y} when is_number(x) and is_number(y) <- Keyword.get(opts, :at, {0, 0}) do
      :ok
    else
      _ -> {:error, :invalid_options}
    end
  end

  defp hole_tool(body, opts) do
    if opts[:on] == :top do
      with {:ok, face} <- top_face(body),
           {:ok, {{_, _, bottom}, {_, _, top}}} <- OCEx.bounds(body),
           {:ok, tool} <- OCEx.cylinder(opts[:diameter] / 2, top - bottom + 2),
           {cx, cy, _} = face.center,
           {dx, dy} = Keyword.get(opts, :at, {0, 0}),
           do: OCEx.translate(tool, {cx + dx, cy + dy, bottom - 1})
    else
      alias Smith.Plane

      with {:ok, frame} <- Plane.frame(opts[:on]),
           {:ok, {low, high}} <- OCEx.bounds(body) do
        center = Plane.point(frame, Keyword.get(opts, :at, {0, 0}))

        distances =
          for x <- [elem(low, 0), elem(high, 0)],
              y <- [elem(low, 1), elem(high, 1)],
              z <- [elem(low, 2), elem(high, 2)],
              do: Plane.dot(Plane.sub({x, y, z}, center), frame.n)

        bottom = Enum.min(distances) - 1
        height = Enum.max(distances) + 1 - bottom

        with {:ok, tool} <- OCEx.cylinder(opts[:diameter] / 2, height),
             do:
               Plane.place(tool, %{
                 frame
                 | origin: Plane.add(center, Plane.scale(frame.n, bottom))
               })
      end
    end
  end

  defp top_face(body) do
    with {:ok, faces} <- OCEx.faces(body) do
      infos =
        Enum.reduce_while(faces, {:ok, []}, fn face, {:ok, acc} ->
          case OCEx.face_info(face) do
            {:ok, %{type: :plane, normal: {_, _, z}} = info} when z > 1 - 1.0e-9 ->
              {:cont, {:ok, [info | acc]}}

            {:ok, _} ->
              {:cont, {:ok, acc}}

            error ->
              {:halt, error}
          end
        end)

      case infos do
        {:ok, []} ->
          {:error, :no_top_face}

        {:ok, candidates} ->
          highest = candidates |> Enum.map(&elem(&1.center, 2)) |> Enum.max()

          case Enum.filter(candidates, &(abs(elem(&1.center, 2) - highest) < 1.0e-7)) do
            [face] -> {:ok, face}
            _ -> {:error, :ambiguous_top_face}
          end

        error ->
          error
      end
    end
  end
end
