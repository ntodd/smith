defmodule Smith.Model do
  @moduledoc """
  A deferred sequence of modeling operations.

  Build recipes with `Smith` functions and pass them to `Smith.evaluate/1`.
  Each operation returns a new recipe; earlier values remain reusable.
  Construction does not allocate native geometry. Recipes created with
  `Smith.from_result/1` retain an existing native geometry snapshot.

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
  wire, face, solid, or compound; it does not necessarily describe a printable part.

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
    * `:operation` — the failed recipe operation, `:assembly`, `:joint`, or `:connect`.
    * `:reason` — an error atom or a nested `Smith.Error` from a tool recipe.
    * `:part` — the original top-level member name, a normalized slash path
      for a nested failure, the joint/connection endpoint for joint errors, or
      `nil` outside an assembly.

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

  <div class="smith-doc-preview" data-preview="api-smith-0" data-model="part" data-label="Filleted plate">
  <p>Interactive preview available in HexDocs.</p>
  </div>

  ## Units and coordinates

  Dimensions are millimeters and modeling angles are degrees. Transforms
  use world coordinates; sketches use a `Smith.Plane` with local 2D
  coordinates. Mesh angular tolerance is in radians.

  Boxes begin at the origin by default. Cylinders and cones are centered
  on world Z with their bottoms at Z=0. Spheres and tori are centered at
  the origin. All solid primitives support explicit placement
  with `:at` and per-axis `:align`.

  ## Where to start

    * [Getting started](getting-started.html) — a complete script and first export.
    * `Smith.Sketch` — 2D outlines, cutouts, and planes.
    * `Smith.Path` — open paths for placed sweep profiles.
    * `Smith.Selector` — composable edge and face queries.
    * `Smith.Assembly` — named parts, references, and print placement.
    * `Smith.Export` — files, mesh checks, and export records.
    * `Smith.Kino` — interactive Livebook previews.

  Recipe validation runs during evaluation. Use valid structs and documented
  argument types; arbitrary malformed Elixir terms and callback exceptions
  are not converted into modeling errors. See [errors and limits](errors-and-limits.html).
  """
  @moduledoc groups: ["Primitives", "Profiles", "Modeling", "Topology", "Evaluation and export"]
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

  <div class="smith-doc-preview" data-preview="api-smith-1" data-model="part" data-label="Positioned box">
  <p>Interactive preview available in HexDocs.</p>
  </div>
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

  <div class="smith-doc-preview" data-preview="api-smith-2" data-model="pin" data-label="Positioned cylinder">
  <p>Interactive preview available in HexDocs.</p>
  </div>
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

  @doc """
  Describes a sphere by radius in mm, centered at the origin by default.

  Radius must exceed 1.0e-7 mm. Supports the `:at` and `:align` options
  of `box/4`, defaulting to `{:center, :center, :center}`.
  """
  @doc group: "Primitives"
  @spec sphere(number(), [primitive_option()]) :: Model.t()
  def sphere(radius, opts \\ []), do: primitive(:sphere, [radius], opts)

  @doc """
  Describes a complete ring torus around world Z, centered at the origin.

  `major_radius` measures from the axis to the tube center; `minor_radius`
  is the tube radius, both in mm. Both radii and their difference must exceed
  1.0e-7 mm. Supports `:at` and `:align` as in `box/4`, defaulting to
  `{:center, :center, :center}`. Rotate the recipe for another axis.
  Horn and spindle tori fail with `:invalid_argument` at evaluation.
  """
  @doc group: "Primitives"
  @spec torus(number(), number(), [primitive_option()]) :: Model.t()
  def torus(major_radius, minor_radius, opts \\ []),
    do: primitive(:torus, [major_radius, minor_radius], opts)

  @doc """
  Reflects a recipe across a world plane.

  Accepts `:xy`, `:xz`, `:yz` through the origin, or a `Smith.Plane`
  for a positioned or oblique mirror. Returns only the reflected geometry;
  use `compound/1` or `fuse/2` to retain both copies. Supports face and
  edge recipes as well as solids. Invalid planes produce `:invalid_plane`
  at this recipe step. The source recipe remains reusable.

      iex> {:ok, part} = Smith.box(2, 3, 4) |> Smith.mirror(Smith.Plane.yz(x: 5)) |> Smith.evaluate()
      iex> {:ok, bounds} = OCEx.bounds(part.shape)
      iex> bounds == {{8.0, 0.0, 0.0}, {10.0, 3.0, 4.0}}
      true

  <div class="smith-doc-preview" data-preview="api-smith-3" data-model="part" data-label="Mirrored box">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec mirror(Model.t(), :xy | :xz | :yz | Smith.Plane.t()) :: Model.t()
  def mirror(model, plane), do: append(model, :mirror, [plane])

  @doc """
  Divides solid geometry with an infinite world plane.

  Accepts `:xy`, `:xz`, `:yz`, or a positioned `Smith.Plane`.
  The only option is `keep:`: `:both` (default), `:positive`, or
  `:negative`. Positive follows the plane normal, so the positive side
  of an XZ plane is world -Y. Both retains separate solids at the cut.

  Accepts a solid or a collection containing only solids. A plane outside
  the body retains the material on its side; the opposite side evaluates
  to an empty compound. One remaining piece is a solid, multiple pieces
  form a compound. Query `OCEx.solids/1` on the result to inspect pieces,
  or use separate recipes with `keep:` to name and export each side.

  Invalid planes fail with `:invalid_plane`; invalid options with
  `:invalid_options`; unsupported topology with `:wrong_shape_type`.
  Errors identify this recipe step. The source recipe remains reusable.
  """
  @doc group: "Modeling"
  @spec split(Model.t(), :xy | :xz | :yz | Smith.Plane.t(), keyword()) :: Model.t()
  def split(model, plane, opts \\ []), do: append(model, :split, [plane, opts])

  @doc """
  Takes a filled cross section of solid material on a world plane.

  Accepts `:xy`, `:xz`, `:yz`, or a positioned `Smith.Plane`.
  Returns a deferred model whose result contains planar faces, retaining
  inner holes and disconnected regions. One region is a face; zero or
  several regions form a compound. An outside or point/edge-tangent plane
  gives no faces. A coincident boundary face remains in the section.

  Coordinates stay in world space and face normals follow the plane's
  normal. Inspect with `faces/2`, `inspect_faces/2`, or `OCEx.area/1`.
  Extrude with a world vector to turn the section into solids. Bare section
  faces cannot be exported as printable bundles. This is an intersection,
  not a projection, and its input must contain only solid geometry.

      iex> section = Smith.box(4, 6, 8) |> Smith.section(Smith.Plane.xy(z: 3))
      iex> {:ok, part} = section |> Smith.extrude({0, 0, 2}) |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(part.shape)
      iex> abs(volume - 48) < 1.0e-6
      true

  <div class="smith-doc-preview" data-preview="api-smith-4" data-model="part" data-label="Extruded section">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Profiles"
  @spec section(Model.t(), :xy | :xz | :yz | Smith.Plane.t()) :: Model.t()
  def section(model, plane), do: append(model, :section, [plane])

  @doc """
  Projects a sketch, path, or edge/face recipe onto target surfaces.

  The target is a model or sketch recipe. Supply exactly one option:
  `direction: {x, y, z}` for parallel projection or
  `from: {x, y, z}` for projection through a world point. Parallel
  directions are normalized. Coordinates remain in world space.

  Sketches contribute their boundary wires, including holes. Results are
  wires, which may be open when clipped by the target. They are not filled
  faces or printable solids. Multiple target hits are retained, and
  parallel projection is bidirectional. Use `surface/2` to select target
  faces before projecting when only one side of a body is wanted. Conical
  projection follows half-rays from the point through the source, excluding
  the opposite side of that point.

  Source collections fail if a boundary misses or projection fails. The
  result can be inspected with `edges/2` or native wire/curve queries.
  Use `face/1` to fill a single closed planar outline before extrusion.
  Solid source recipes are not accepted: explicitly select their surfaces
  first. See `OCEx.project/3` for topology and failure details.
  Inputs stay reusable; target failures retain their nested recipe context.
  """
  @doc group: "Profiles"
  @spec project(
          Model.t() | Smith.Sketch.t() | Smith.Path.t(),
          Model.t() | Smith.Sketch.t(),
          keyword()
        ) :: Model.t()
  def project(%{__struct__: Smith.Sketch} = sketch, target, opts),
    do: new(:sketch, [sketch]) |> project(target, opts)

  def project(%{__struct__: Smith.Path} = path, target, opts),
    do: new(:path, [path]) |> project(target, opts)

  def project(model, target, opts), do: append(model, :project, [target, opts])

  @doc """
  Tapers selected faces around a neutral plane.

  Requires `faces:`, `neutral:`, and `angle:`. Faces use the usual
  `Smith.Selector` inputs. The neutral plane accepts `:xy`, `:xz`,
  `:yz`, or a positioned `Smith.Plane`; the surface intersections with
  that plane stay fixed. Angles are degrees, strictly between -90 and 90.

  Optional `direction:` is the pull vector and defaults to the neutral
  plane normal. It must be nonzero and not lie in that plane. Positive
  angles remove material on the pull side; negative angles add material.
  Zero retains the geometry. Optional positive `count:` guards the
  number of explicitly selected faces, before tangent propagation.

  Requires one solid, including a solid wrapped by an earlier Boolean
  operation. Selected faces must be planar, cylindrical, or conical.
  OCCT also tapers tangent-connected faces. The requested taper must not
  collapse edges or otherwise require a topology change. Those cases may
  return `:draft_failed` or a native geometry error. Empty selections,
  incorrect counts, invalid planes and options retain their usual tagged
  errors at this step. The source recipe remains reusable.
  """
  @doc group: "Modeling"
  @spec draft(Model.t(), keyword()) :: Model.t()
  def draft(model, opts), do: append(model, :draft, opts)

  @doc """
  Extracts selected faces and sews their shared edges into a surface recipe.

  The selector defaults to `:all` and resolves against the geometry at
  this step. Connected faces form shells; a single face remains a face;
  disconnected surfaces form a compound. A closed shell remains a surface,
  not a filled solid. Coordinates and source face orientations are retained.

  Use this to extract a curved wall for `offset/3` or `thicken/3`.
  Empty selections return `:empty_selection`. Sewing uses 1.0e-7 mm
  tolerance and rejects non-manifold joins. The original model is unchanged.
  Bare surfaces are not printable bundles; thicken them first.
  """
  @doc group: "Profiles"
  @spec surface(Model.t(), Smith.Selector.input()) :: Model.t()
  def surface(model, selector \\ :all), do: append(model, :surface, [selector])

  @doc """
  Offsets a solid or surface by a signed normal distance in mm.

  Positive distances expand oriented solids or follow surface normals;
  negative distances contract solids or oppose the normals. Magnitude must
  exceed 1.0e-7 mm. Faces, shells, solids, and their compounds are supported.
  Sketch inputs become face recipes before offsetting.

  This is a **3D surface offset**: offsetting a planar sketch moves its
  plane and does not grow its outline. `join: :arc` (default) rounds
  convex gaps; `:intersection` extends adjacent surfaces until they meet.
  Compound members are offset independently. Use `surface/2` to sew
  selected connected faces before offsetting them as a shell.

  Solid results must expand/contract with directional containment, checked
  at the volume tolerance documented in `OCEx.offset/3`. Complete collapse
  or inversion is an error. Curved surfaces require sufficiently smooth
  geometry and a small enough offset to avoid self-intersection. Global
  self-intersection repair is not provided. Native and option failures
  retain this recipe step's context.
  """
  @doc group: "Modeling"
  @spec offset(Model.t() | Smith.Sketch.t(), number(), keyword()) :: Model.t()
  def offset(model, distance, opts \\ [])

  def offset(%{__struct__: Smith.Sketch} = sketch, distance, opts),
    do: new(:sketch, [sketch]) |> offset(distance, opts)

  def offset(model, distance, opts), do: append(model, :offset, [distance, opts])

  @doc """
  Builds solid material between an open surface and its signed offset.

  Accepts a sketch or a model containing faces/open shells. Magnitude must
  exceed 1.0e-7 mm. Positive thickness follows oriented normals; negative
  thickness goes against them. The original surface forms one boundary,
  free edges receive connecting walls, and holes remain open.

  `join: :intersection` (default) extends adjacent surfaces; `:arc`
  uses rounded transitions where applicable. Use `surface/2` to extract
  and sew faces from a solid. Disconnected surfaces produce separate
  solids without fusing. A solid input fails with `:wrong_shape_type`;
  a closed shell fails with `:closed_shell`. Use `shell/2` to hollow
  an existing solid instead.

  Results pass native shape and positive-volume checks. Smoothness,
  inversion, and self-intersection limits follow `OCEx.thicken/3`.
  Excessive thickness is a modeling failure, not an instruction to repair
  or delete intersecting features. Thickness is uniform along the normals.

      iex> wall = Smith.cylinder(10, 12) |> Smith.surface(Smith.Selector.type(:cylinder))
      iex> {:ok, tube} = wall |> Smith.thicken(-2) |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(tube.shape)
      iex> abs(volume - 432 * :math.pi()) < 1.0e-5
      true

  <div class="smith-doc-preview" data-preview="api-smith-5" data-model="tube" data-label="Thickened cylinder wall">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec thicken(Model.t() | Smith.Sketch.t(), number(), keyword()) :: Model.t()
  def thicken(model, thickness, opts \\ [])

  def thicken(%{__struct__: Smith.Sketch} = sketch, thickness, opts),
    do: new(:sketch, [sketch]) |> thicken(thickness, opts)

  def thicken(model, thickness, opts), do: append(model, :thicken, [thickness, opts])

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
  Describes font-backed planar text. Equivalent to `Smith.Text.new/2`.

  Required options are `font: font_snapshot` and `size: em_mm`. See `Smith.Text`
  for alignment, placement, measured layout reports and fit validation. Extrude
  the returned text and fuse it into a body for raised lettering, or cut the
  extrusion from a body for engraving.
  """
  @doc group: "Profiles"
  @spec text(String.t(), keyword()) :: Smith.Text.t()
  def text(string, opts), do: Smith.Text.new(string, opts)

  @doc """
  Describes imported SVG artwork. Equivalent to `Smith.SVG.new/2`.
  Load an immutable asset with `Smith.SVG.load/1` or `Smith.SVG.from_binary/1`,
  then choose fills/strokes, millimeter sizing, selection and plane placement.
  Scalar extrusion follows the artwork plane normal.
  """
  @doc group: "Profiles"
  @spec svg(Smith.SVG.Asset.t(), keyword()) :: Smith.SVG.t()
  def svg(asset, opts \\ []), do: Smith.SVG.new(asset, opts)

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
  Describes a polynomial Bézier edge using world-space control points.

  Supply 2–26 `{x, y, z}` points. The first and last are endpoints;
  interior points are control handles, not interpolation targets. Four
  points define a cubic. The curve lies inside the control points' convex
  hull. Use `Smith.Sketch.bezier/1` for local 2D profile segments.

  Validation is deferred to evaluation. Point/count errors return a
  `Smith.Error` for `:bezier` with reason `:invalid_argument`; native
  construction failures retain their reason. See `OCEx.bezier/1` for
  repeated-point and degree limits. An edge alone is not printable.
  """
  @doc group: "Profiles"
  @spec bezier([OCEx.point3()]) :: Model.t()
  def bezier(points), do: new(:bezier, [points])

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
      iex> {:ok, area} = OCEx.area(face.shape)
      iex> Float.round(area, 6)
      6.0

  <div class="smith-doc-preview" data-preview="api-smith-6" data-model="face" data-label="Triangular profile">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Profiles"
  @spec profile([Model.t()]) :: Model.t()
  def profile(edges), do: new(:profile, [edges])

  @doc """
  Fills one closed planar wire as a face recipe.

  Use after `project/3` when its result is a single closed outline.
  The face retains the wire's world placement. It can then be extruded,
  revolved, or used in face Boolean operations. Input recipes remain reusable.

  This does not infer holes or choose a wire from multiple projection hits.
  A compound of wires returns `:wrong_shape_type`, an open wire returns
  `:open_wire`, and nonplanar or invalid boundaries fail in OCEx. Select
  a single target surface before projection when only one outline is wanted.
  To construct a face from edge recipes directly, use `profile/1`.
  """
  @doc group: "Profiles"
  @spec face(Model.t()) :: Model.t()
  def face(model), do: append(model, :face, [])

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
  Describes an extrusion of a sketch, face recipe, or compound of planar faces.

  With a `Smith.Sketch`, supply a signed distance in millimeters. Positive
  distance follows its plane normal; negative distance extends behind the
  plane. Zero fails with `:invalid_extrusion`. Sketch holes pass through
  the solid.

  With a `Smith.Model` that evaluates to planar faces, supply a world
  vector `{x, y, z}`. It must have a nonzero normal component; extrusion
  within the face plane fails with `:degenerate_extrusion`. Native length
  tolerances also apply. Each face produces its own solid; results are not
  fused. This supports disconnected regions from `section/2`. A scalar
  distance follows the local plane normal for sketches, text and SVG artwork.

      iex> model = Smith.Sketch.rectangle(4, 6) |> Smith.extrude(-2)
      iex> {:ok, part} = Smith.evaluate(model)
      iex> OCEx.bounds(part.shape)
      {:ok, {{-2.0, -3.0, -2.0}, {2.0, 3.0, 0.0}}}

  <div class="smith-doc-preview" data-preview="api-smith-7" data-model="part" data-label="Negative extrusion">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Profiles"
  @spec extrude(Smith.Sketch.t(), number()) :: Model.t()
  @spec extrude(Smith.Text.t(), number()) :: Model.t()
  @spec extrude(Smith.SVG.t(), number()) :: Model.t()
  @spec extrude(Model.t(), {number(), number(), number()}) :: Model.t()
  def extrude(%{__struct__: Smith.Sketch} = sketch, distance),
    do: new(:sketch_extrude, [sketch, distance])

  def extrude(%{__struct__: Smith.Text} = text, distance),
    do: new(:text_extrude, [text, distance])

  def extrude(%{__struct__: Smith.SVG} = svg, distance),
    do: new(:svg_extrude, [svg, distance])

  def extrude(model, vector), do: append(model, :extrude, [vector])

  @doc """
  Extrudes with symmetric extent or tapered walls.

  Accepts the same profile and distance/vector forms as `extrude/2`.
  Options default to `both: false` and `taper: 0`. With `both: true`,
  the supplied distance applies on each side of the profile, so a distance
  of 5 makes a total depth of 10. The sign selects the first direction;
  both halves have equal extent.

  `taper:` is in degrees, strictly between −90 and 90. Positive values
  narrow outer walls and widen holes away from the starting profile;
  negative values widen outer walls and narrow holes. Each symmetric half
  tapers away from the shared starting plane. The profile is the neutral
  section, not a scaled copy of the end section.

  Nonzero taper requires travel normal to the profile and straight or
  circular boundary edges. Collapsing walls, unsupported side surfaces,
  and topology changes fail through OCEx with this recipe step's context.
  See `OCEx.extrude/3` for native limits and error reasons. Options are
  validated at evaluation. Earlier recipes remain reusable.
  """
  @doc group: "Profiles"
  @spec extrude(Smith.Sketch.t(), number(), keyword()) :: Model.t()
  @spec extrude(Model.t(), {number(), number(), number()}, keyword()) :: Model.t()
  def extrude(%{__struct__: Smith.Sketch} = sketch, distance, opts),
    do: new(:sketch_extrude, [sketch, distance, opts])

  def extrude(model, vector, opts), do: append(model, :extrude, [vector, opts])

  @doc """
  Extrudes a profile until it meets an infinite target plane.

  The target is a `Smith.Plane` or `:xy`, `:xz`, or `:yz`.
  Sketches travel along their plane normal by default. Supply
  `direction: {x, y, z}` for an oblique or reversed world direction;
  the vector is normalized. Face recipes require this option explicitly.

  The entire profile must lie behind the target in the travel direction.
  A target crossing or touching the starting profile returns
  `:target_not_ahead`. The target may be tilted relative to the profile;
  its normal's sign does not affect the result. Holes and disconnected
  face regions remain intact, with a separate solid for each face.

  Walls are straight and untapered. `:direction` is the only option;
  `:both` and `:taper` are not accepted here. This stops at a plane,
  not the nearest face of another body. See `OCEx.extrude_until/4` for
  native tolerances and failure reasons. Geometry errors retain recipe
  step context, and input recipes remain unchanged.
  """
  @doc group: "Profiles"
  @spec extrude_until(Model.t() | Smith.Sketch.t(), Smith.Plane.t() | :xy | :xz | :yz, keyword()) ::
          Model.t()
  def extrude_until(profile, plane, opts \\ [])

  def extrude_until(%{__struct__: Smith.Sketch} = sketch, plane, opts),
    do: new(:sketch_extrude_until, [sketch, plane, opts])

  def extrude_until(model, plane, opts), do: append(model, :extrude_until, [plane, opts])

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

  <div class="smith-doc-preview" data-preview="api-smith-8" data-model="sleeve" data-label="Revolved sleeve">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Profiles"
  @spec revolve(Smith.Sketch.t() | Model.t(), OCEx.point3(), number(), OCEx.point3()) :: Model.t()
  def revolve(profile, axis, degrees \\ 360, origin \\ {0, 0, 0})

  def revolve(%{__struct__: Smith.Sketch} = sketch, axis, degrees, origin),
    do: new(:sketch, [sketch]) |> revolve(axis, degrees, origin)

  def revolve(model, axis, degrees, origin), do: append(model, :revolve, [origin, axis, degrees])

  @doc """
  Describes a capped solid through two or more ordered sketches.

  Each sketch uses its own plane and must have exactly one boundary wire.
  Sections with holes fail with `:loft_profile_has_holes`. A cut touching
  the outer edge is allowed if it leaves one boundary. OCCT chooses edge
  correspondence; there are no guide rails or seam controls.

  `ruled: true` (default) joins adjacent sections with straight generators.
  Use `ruled: false` for a smooth interpolating loft. Smooth interpolation
  can overshoot between sections; inspect the result for your dimensions.
  Smith requires one solid with volume greater than 1.0e-9 mm³.

      iex> sections = [
      ...>   Smith.Sketch.rectangle(20, 10),
      ...>   Smith.Sketch.rectangle(10, 5, on: Smith.Plane.xy(z: 12))
      ...> ]
      iex> {:ok, transition} = Smith.loft(sections) |> Smith.evaluate()
      iex> {:ok, solids} = OCEx.solids(transition.shape)
      iex> length(solids)
      1

  <div class="smith-doc-preview" data-preview="api-smith-9" data-model="transition" data-label="Ruled loft">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Profiles"
  @spec loft([Smith.Sketch.t()], keyword()) :: Model.t()
  def loft(sketches, opts \\ []), do: new(:loft, [sketches, opts])

  @doc """
  Sweeps a placed sketch along an open `Smith.Path`.

  The sketch must have one closed boundary and lie in the plane through
  the start of the path, perpendicular to its starting tangent. Its local
  offset is retained. Smith does not move or rotate it onto the path.
  Profiles with holes return `:sweep_profile_has_holes`.

  Options match `OCEx.sweep/3`: `frame: :corrected` (default) or
  `:frenet`, and `transition: :transformed` (default), `:right`, or
  `:round`. Tangent-continuous paths avoid sharp-corner transition ambiguity.
  Construction and validation are deferred until `evaluate/1`.

      iex> path = Smith.Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])
      iex> {:ok, rod} = Smith.Sketch.circle(2) |> Smith.sweep(path) |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(rod.shape)
      iex> abs(volume - 40 * :math.pi()) < 1.0e-6
      true

  <div class="smith-doc-preview" data-preview="api-smith-10" data-model="rod" data-label="Swept rod">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec sweep(Smith.Sketch.t(), Smith.Path.t(), keyword()) :: Model.t()
  def sweep(sketch, path, opts \\ []), do: new(:sweep, [sketch, path, opts])

  @doc """
  Hollows the current solid by removing selected faces and offsetting its walls.

  Required options are `:openings` (a `Smith.Selector` or face predicate)
  and signed `:thickness` in millimeters. Negative thickness builds inward;
  positive builds outward. `:join` is `:arc` (default) or `:intersection`.
  Optional `:count` requires exactly that many opening faces.

  Selectors run against the body at this recipe step. An empty selection
  returns `:empty_selection`; an unexpected count returns
  `:selection_count_mismatch`. Thickness must have magnitude greater than
  1.0e-7 mm. OCCT can reject thicknesses that cannot fit the source geometry.
  This operation requires a single solid and at least one opening; it does
  not create a sealed cavity or thicken an open surface.

      iex> {:ok, tray} = Smith.box(20, 16, 10)
      ...>   |> Smith.shell(openings: Smith.Selector.facing(:z), thickness: -2, count: 1)
      ...>   |> Smith.evaluate()
      iex> {:ok, volume} = OCEx.volume(tray.shape)
      iex> abs(volume - 1664) < 1.0e-6
      true

  <div class="smith-doc-preview" data-preview="api-smith-11" data-model="tray" data-label="Shelled tray">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec shell(Model.t(), keyword()) :: Model.t()
  def shell(model, opts), do: append(model, :shell, opts)

  @doc """
  Selects edges from an evaluated result using `Smith.Selector`.

  Accepts `:all` (default), `{:parallel, axis}`, a metadata predicate,
  or a composed selector. Returns `{:ok, [OCEx.Shape.t()]}`, including an
  empty list when nothing matches. Handles belong to this result revision.
  Unsupported selectors return `:invalid_options`. Predicates must return
  booleans; their exceptions propagate.
  """
  @doc group: "Topology"
  @spec edges(Result.t(), Smith.Selector.input()) :: OCEx.result([OCEx.Shape.t()])
  def edges(%Result{shape: shape}, selector \\ :all),
    do: Smith.Selector.select(shape, :edges, selector)

  @doc """
  Selects faces from an evaluated result using `Smith.Selector`.

  Returns native handles with the same result and error rules as `edges/2`.
  Face predicates receive `OCEx.face_info/1` metadata plus world `:bounds`.
  Empty and tied selections are retained; this query does not silently pick
  a single face. Use a feature's `:count` option to enforce its expectation.
  """
  @doc group: "Topology"
  @spec faces(Result.t(), Smith.Selector.input()) :: OCEx.result([OCEx.Shape.t()])
  def faces(%Result{shape: shape}, selector \\ :all),
    do: Smith.Selector.select(shape, :faces, selector)

  @doc """
  Returns selected edges with their geometry metadata and native `:shape` handles.

  Each map contains `OCEx.edge_info/1` fields plus world `:bounds` and
  `:midpoint`, using `Smith.Selector.where/2` conventions. Query order is
  preserved. Handles belong to this result's revision. Returns a tagged list;
  selection and native query failures propagate as tagged errors.
  """
  @doc group: "Topology"
  @spec inspect_edges(Result.t(), Smith.Selector.input()) :: {:ok, [map()]} | {:error, atom()}
  def inspect_edges(%Result{shape: shape}, selector \\ :all),
    do: Smith.Selector.inspect(shape, :edges, selector)

  @doc """
  Returns selected faces with their geometry metadata and native `:shape` handles.

  Each map contains `OCEx.face_info/1` fields plus world `:bounds`.
  Uses the ordering, revision, and tagged-result rules of `inspect_edges/2`.
  """
  @doc group: "Topology"
  @spec inspect_faces(Result.t(), Smith.Selector.input()) :: {:ok, [map()]} | {:error, atom()}
  def inspect_faces(%Result{shape: shape}, selector \\ :all),
    do: Smith.Selector.inspect(shape, :faces, selector)

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

  Tools are evaluated in order and united with the body with same-domain
  cleanup. Compatible consecutive operations are automatically grouped.
  An empty list returns the original recipe. Disjoint
  inputs can leave multiple solids; this does not fail evaluation.

      iex> base = Smith.box(10, 10, 2)
      iex> boss = Smith.cylinder(2, 4, at: {5, 5, 2})
      iex> {:ok, part} = Smith.fuse(base, boss) |> Smith.evaluate()
      iex> {:ok, solids} = OCEx.solids(part.shape)
      iex> length(solids)
      1

  <div class="smith-doc-preview" data-preview="api-smith-12" data-model="part" data-label="Fused boss">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec fuse(Model.t(), Model.t() | [Model.t()]) :: Model.t()
  def fuse(%Model{} = model, tools) when is_list(tools),
    do: Enum.reduce(tools, model, &fuse(&2, &1))

  def fuse(model, tool), do: append(model, :fuse, [tool])

  @doc """
  Subtracts one tool recipe or an ordered list from the current body.

  Subtractions include same-domain cleanup; compatible consecutive operations
  are automatically grouped. An empty list returns
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
  Subtracts a list of tool recipes in one native Boolean operation.

  This explicitly requests a single batch; ordinary `cut/2` recipes are
  already optimized automatically when compatible. Tools
  are evaluated in list order; overlapping tools are subtracted once. Cleanup
  runs once on the final result. Empty lists leave the recipe unchanged.
  Intermediate topology and failure step numbers can differ from sequential
  operations. Requires an OCEx version providing `OCEx.cut_many/2`; otherwise
  evaluation returns an error with reason `:unsupported_operation`.
  """
  @spec cut_many(Model.t(), [Model.t()]) :: Model.t()
  def cut_many(%Model{} = model, []), do: model
  def cut_many(model, tools), do: append(model, :cut_many, [tools])

  @doc """
  Unites a body and tool recipes in one native Boolean operation.

  Tools are evaluated in list order and may overlap each other. Cleanup runs
  once, and disconnected solids remain separate. Empty lists leave the recipe
  unchanged. Ordinary `fuse/2` recipes are optimized automatically and retain
  original recipe-step errors. Requires an OCEx version providing `OCEx.fuse_many/2`;
  otherwise evaluation returns reason `:unsupported_operation`.
  """
  @spec fuse_many(Model.t(), [Model.t()]) :: Model.t()
  def fuse_many(%Model{} = model, []), do: model
  def fuse_many(model, tools), do: append(model, :fuse_many, [tools])

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

  <div class="smith-doc-preview" data-preview="api-smith-13" data-model="part" data-label="Chamfered block">
  <p>Interactive preview available in HexDocs.</p>
  </div>
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
    * A composed `Smith.Selector` filters by type, direction, extrema, or predicates.
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
  Appends a circular through-all or flat-bottomed blind hole.

  Requires `on:`, `diameter:`, and exactly one of `through: :all` or
  positive `depth:` in mm. Diameter is positive
  and in millimeters; its half-radius must also satisfy OCEx's native
  tolerance. Optional `at: {u, v}` defaults to `{0, 0}`.

    * `on: :top` selects the unique highest planar face with an outward
      +Z normal. `:at` is an XY offset from that face's **area centroid**.
      Earlier cuts can move this centroid.
    * `on: plane` uses plane-local `:at` coordinates and drills along its
      normal. The plane is independent of the body and may lie outside it.

  Through-all extends through the body's full projected bounds, including
  disconnected solids. Blind depth starts at the entry plane and runs along
  its **negative normal**, leaving a flat floor when contained in the body.
  It is not measured from the first intersected surface; an outside plane
  consumes part of that distance before reaching material. A cut removing no more than 1.0e-9 mm³ fails with
  `:hole_misses_body`. Top selection can fail with `:no_top_face` or
  `:ambiguous_top_face`. Conflicting extent options fail with `:invalid_options`.
  Use `counterbore/2` or `countersink/2` for a recessed entry.

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

  <div class="smith-doc-preview" data-preview="api-smith-15" data-model="part" data-label="Through hole">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Modeling"
  @spec hole(Model.t(), keyword()) :: Model.t()
  def hole(%Model{} = model, opts), do: %{model | operations: [{:hole, opts} | model.operations]}

  @doc """
  Drills a hole with a cylindrical recess for a fastener head.

  Uses `hole/2` options for `:on`, `:at`, `:diameter`, and exactly one
  of `:depth` or `through: :all`. Also requires `:bore_diameter`, larger
  than the hole diameter, and positive `:bore_depth`, both in mm.

  The recess runs from the entry plane into its negative normal. Total
  blind depth includes the recess and must be at least bore depth. Both
  cutters use the original entry location even if the first cut moves the
  face centroid. A recess removing no additional material fails with
  `:recess_misses_body`; malformed options fail with `:invalid_options`.
  Dimensions must also satisfy native modeling tolerance.
  """
  @doc group: "Modeling"
  @spec counterbore(Model.t(), keyword()) :: Model.t()
  def counterbore(model, opts), do: append(model, :counterbore, opts)

  @doc """
  Drills a hole with a conical recess for a countersunk fastener.

  Uses `hole/2` placement and extent options. Requires `:sink_diameter`,
  larger than `:diameter`. Optional `:angle` is the included cone angle
  in degrees, default 90, strictly between 0 and 180.

  The recess narrows from sink diameter at the entry plane to hole diameter
  at depth `(sink_diameter - diameter) / (2 * tan(angle / 2))`.
  It runs into the negative plane normal. Total blind depth includes this
  recess and must reach its bottom. Uses the same entry-location and error
  rules as `counterbore/2`. The remaining blind hole has a flat floor.
  """
  @doc group: "Modeling"
  @spec countersink(Model.t(), keyword()) :: Model.t()
  def countersink(model, opts), do: append(model, :countersink, opts)

  @doc """
  Starts a recipe from an already evaluated geometry snapshot.

  Use this when branching from an expensive model in a notebook. Subsequent
  operations reuse the result's native shape instead of rebuilding its source
  recipe. The returned recipe is immutable; editing either branch does not
  change the result or the other branch.

  This retains a native resource in the current BEAM runtime. It is not a
  portable or automatically updated recipe: rerun the source evaluation and
  this call after changing upstream dimensions. Keep the original modeling
  code as the editable design.

  Accepts a `Smith.Result`, including face and curve results. It does not
  accept an assembly result. During evaluation, a changed revision returns
  `%Smith.Error{operation: :from_result, reason: :revision_mismatch}`.

      iex> {:ok, blank} = Smith.box(20, 10, 4) |> Smith.evaluate()
      iex> half = Smith.from_result(blank) |> Smith.split(Smith.Plane.xy(z: 2), keep: :positive)
      iex> {:ok, result} = Smith.evaluate(half)
      iex> {:ok, volume} = OCEx.volume(result.shape)
      iex> abs(volume - 400.0) < 1.0e-6
      true

  <div class="smith-doc-preview" data-preview="api-from-result" data-model="result" data-label="Half of an evaluated block">
  <p>Interactive preview available in HexDocs.</p>
  </div>
  """
  @doc group: "Evaluation and export"
  @spec from_result(Result.t()) :: Model.t()
  def from_result(%Result{} = result), do: new(:from_result, [result])

  @spec evaluate(
          Model.t()
          | Smith.Assembly.t()
          | Smith.Sketch.t()
          | Smith.Path.t()
          | Smith.Text.t()
          | Smith.SVG.t()
        ) ::
          {:ok, Result.t() | Smith.Assembly.Result.t()} | {:error, Error.t() | atom()}
  @doc """
  Builds native geometry from a model, sketch, or assembly recipe.

  Returns `{:ok, %Smith.Result{}}` for models and sketches, or
  `{:ok, %Smith.Assembly.Result{}}` for assemblies. A bare sketch becomes
  a face; paths evaluate to wires. Edge recipes and empty compounds can also
  evaluate successfully.
  Successful evaluation alone does not establish printability.

  Model operations execute in construction order. Failures return
  `{:error, %Smith.Error{step: index, operation: name, reason: reason}}`;
  the index starts at 1. Assemblies also identify the failed part where
  available. Final shape checks and top-level validation can return a bare
  error atom. Empty models return `:empty_model`; unsupported top-level
  terms return `:invalid_recipe`.

  Evaluation is synchronous. Compatible Boolean runs are grouped automatically;
  repeated self-contained geometry is reused within the call, including copies
  with different placements. Callback-containing recipes are not memoized.
  Native shape reuse ends with the evaluation. A bounded, expiring cache of
  serialized pure prefixes can also avoid rebuilding unchanged work across edits.
  Adjacent rigid transforms are composed before transforming the geometry.
  `from_result/1` explicitly retains an evaluated stage across calls.
  User callback exceptions are not caught. See the
  [error guide](errors-and-limits.html) for details.

      iex> Smith.box(0, 10, 4) |> Smith.evaluate()
      {:error, %Smith.Error{step: 1, operation: :box, reason: :invalid_argument}}
      iex> Smith.evaluate(nil)
      {:error, :invalid_recipe}
  """
  @doc group: "Evaluation and export"
  def evaluate(%{__struct__: Smith.Assembly} = assembly), do: Smith.Assembly.evaluate(assembly)

  def evaluate(%{__struct__: Smith.Sketch} = sketch), do: evaluate(new(:sketch, [sketch]))

  def evaluate(%{__struct__: Smith.Path} = path), do: evaluate(new(:path, [path]))

  def evaluate(%{__struct__: Smith.Text} = text), do: evaluate(new(:text, [text]))

  def evaluate(%{__struct__: Smith.SVG} = svg), do: evaluate(new(:svg, [svg]))

  def evaluate(%Model{operations: []}), do: {:error, :empty_model}

  def evaluate(%Model{} = model) do
    Smith.EvaluationCache.with_scope(model, fn -> model |> evaluate_shape() |> finish() end)
  end

  def evaluate(_), do: {:error, :invalid_recipe}

  # Tool results are consumed as shapes, so do not serialize and hash a public
  # Result that the parent immediately discards. Native operations still
  # validate their outputs, and the public evaluation boundary calls finish/1.
  defp evaluate_shape(%Model{operations: []}), do: {:error, :empty_model}

  defp evaluate_shape(%Model{} = model) do
    {base, placements} = Smith.EvaluationPlan.placement_base(model)

    if Smith.EvaluationCache.candidate?(base) do
      with {:ok, shape} <-
             Smith.EvaluationCache.fetch(base, fn -> evaluate_operations(base.operations) end) do
        placements
        |> Enum.reverse()
        |> Enum.with_index(length(base.operations) + 1)
        |> Smith.EvaluationPlan.group()
        |> Enum.reduce_while({:ok, shape, nil}, fn group, context ->
          case evaluate_group(group, context) do
            {:ok, _, _} = next -> {:cont, next}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, placed, _} -> {:ok, placed}
          error -> error
        end
      end
    else
      evaluate_operations(model.operations)
    end
  end

  defp evaluate_shape(recipe) do
    with {:ok, result} <- evaluate(recipe), do: {:ok, result.shape}
  end

  defp evaluate_operations(operations) do
    groups = Smith.EvaluationPlan.compile(operations)

    checkpoints =
      if Process.whereis(Smith.IncrementalCache),
        do: Smith.EvaluationPlan.checkpoints(groups),
        else: Enum.map(groups, &{&1, nil})

    {remaining, context} = resume_checkpoint(checkpoints)

    remaining
    |> Enum.reduce_while(context, fn {group, key}, context ->
      started = System.monotonic_time(:microsecond)

      case evaluate_group(group, context) do
        {:ok, shape, _} = next ->
          # Avoid serializing cheap primitives merely to memoize them. Cache
          # only successful, pure checkpoints with material kernel work.
          if key && System.monotonic_time(:microsecond) - started >= 2_000 do
            with {:ok, brep} <- OCEx.to_brep(shape), do: Smith.IncrementalCache.put(key, brep)
          end

          {:cont, next}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, shape, _envelope} -> {:ok, shape}
      error -> error
    end
  end

  defp resume_checkpoint(checkpoints) do
    keys =
      checkpoints
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&is_nil/1)
      |> Enum.reverse()
      |> Enum.take(32)

    with true <- keys != [],
         {key, brep} <- Smith.IncrementalCache.fetch(keys),
         {:ok, shape} <- OCEx.from_brep(brep) do
      remaining =
        checkpoints |> Enum.drop_while(fn {_, candidate} -> candidate != key end) |> tl()

      {remaining, {:ok, shape, nil}}
    else
      _ -> {checkpoints, {:ok, nil, nil}}
    end
  end

  defp evaluate_group([node], context), do: evaluate_node(node, context)

  defp evaluate_group([{{op, _}, _} | _] = nodes, {:ok, body, _} = context)
       when op in [:translate, :rotate, :mirror] do
    result =
      speculative(fn ->
        if Code.ensure_loaded?(OCEx.Internal) and
             function_exported?(OCEx.Internal, :transform_chain, 2) do
          with {:ok, steps} <- transform_steps(nodes),
               {:ok, shape} <- apply(OCEx.Internal, :transform_chain, [body, steps]),
               do: {:ok, shape, nil}
        else
          :sequential
        end
      end)

    recover_group(result, nodes, context)
  end

  defp evaluate_group([{{op, _}, _} | _] = nodes, {:ok, body, envelope} = context)
       when op in [:hole, :counterbore, :countersink] do
    features = Enum.map(nodes, fn {feature, _} -> feature end)
    result = speculative(fn -> Smith.Features.Hole.evaluate_batch(body, features, envelope) end)
    recover_group(result, nodes, context)
  end

  defp evaluate_group([{{operation, _}, _} | _] = nodes, {:ok, body, _} = context) do
    native = if operation == :cut, do: :cut_many, else: :fuse_many
    tools = Enum.map(nodes, fn {{_, [tool]}, _} -> tool end)

    result =
      speculative(fn ->
        if Code.ensure_loaded?(OCEx) and function_exported?(OCEx, native, 2) do
          with {:ok, shapes} <- evaluate_edges(tools),
               {:ok, result} <- apply(OCEx, native, [body, shapes]),
               {:ok, result} <- OCEx.clean(result),
               do: {:ok, result, nil}
        else
          :sequential
        end
      end)

    recover_group(result, nodes, context)
  end

  defp transform_steps(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn
      {{:mirror, [plane]}, _}, {:ok, steps} ->
        case modeling_frame(plane) do
          {:ok, frame} -> {:cont, {:ok, [{:mirror, [frame.origin, frame.n]} | steps]}}
          error -> {:halt, error}
        end

      {{op, args}, _}, {:ok, steps} ->
        {:cont, {:ok, [{op, args} | steps]}}
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      error -> error
    end
  end

  defp speculative(fun) do
    fun.()
  rescue
    # Only callback-free optimization attempts run here. Replay outside this
    # rescue so the original first failure (including an exception) survives.
    _ -> :sequential
  end

  defp recover_group(result, nodes, context) do
    case result do
      {:ok, _, _} ->
        result

      _ ->
        # Preparation and batch failure are not public recipe steps. Replay
        # the pure nodes to retain the original first error and nested context.
        Enum.reduce_while(nodes, context, fn node, acc ->
          case evaluate_node(node, acc) do
            {:ok, _, _} = next -> {:cont, next}
            error -> {:halt, error}
          end
        end)
    end
  end

  defp evaluate_node({{operation, args}, index}, {:ok, body, envelope}) do
    result =
      if operation in [:hole, :counterbore, :countersink] do
        Smith.Features.Hole.evaluate(body, operation, args, envelope)
      else
        # Other operations can enlarge, move or replace the body. Never
        # carry a previous hole run's bounds across such an AST node.
        with {:ok, next} <- apply_operation(operation, body, args), do: {:ok, next, nil}
      end

    case result do
      {:ok, _, _} -> result
      {:error, reason} -> {:error, %Error{step: index, operation: operation, reason: reason}}
    end
  end

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

  defp apply_operation(:from_result, nil, [%Result{shape: shape, revision: revision}]) do
    with {:ok, brep} <- OCEx.to_brep(shape),
         true <- Base.encode16(:crypto.hash(:sha256, brep), case: :lower) == revision do
      {:ok, shape}
    else
      false -> {:error, :revision_mismatch}
      error -> error
    end
  end

  defp apply_operation(:sketch, nil, [sketch]), do: Smith.Sketch.evaluate(sketch)

  defp apply_operation(:text, nil, [text]), do: Smith.Text.evaluate(text)

  defp apply_operation(:svg, nil, [svg]), do: Smith.SVG.evaluate(svg)

  defp apply_operation(:svg_extrude, nil, [svg, distance]),
    do: Smith.SVG.extrude(svg, distance)

  defp apply_operation(:text_extrude, nil, [text, distance]),
    do: Smith.Text.extrude(text, distance)

  defp apply_operation(:sketch_extrude, nil, [sketch, height]),
    do: Smith.Sketch.extrude(sketch, height)

  defp apply_operation(:sketch_extrude, nil, [sketch, height, opts]),
    do: Smith.Sketch.extrude(sketch, height, opts)

  defp apply_operation(:sketch_extrude_until, nil, [sketch, plane, opts]) do
    with :ok <- options(opts, [:direction], []),
         {:ok, target} <- modeling_frame(plane),
         do: Smith.Sketch.extrude_until(sketch, target, opts)
  end

  defp apply_operation(:extrude_until, body, [plane, opts]) do
    with :ok <- options(opts, [:direction], [:direction]),
         {:ok, target} <- modeling_frame(plane),
         do: OCEx.extrude_until(body, opts[:direction], target.origin, target.n)
  end

  defp apply_operation(:loft, nil, [sketches, opts])
       when is_list(sketches) and length(sketches) >= 2 do
    with {:ok, wires} <- loft_wires(sketches),
         {:ok, shape} <- OCEx.loft(wires, opts),
         do: single_solid(shape)
  end

  defp apply_operation(:path, nil, [path]), do: Smith.Path.evaluate(path)

  defp apply_operation(:sweep, nil, [sketch, path, opts]) do
    with {:ok, face} <- Smith.Sketch.evaluate(sketch),
         {:ok, wires} <- OCEx.wires(face),
         {:ok, wire} <- sweep_wire(wires),
         {:ok, spine} <- Smith.Path.evaluate(path),
         {:ok, shape} <- OCEx.sweep(wire, spine, opts),
         do: single_solid(shape)
  end

  defp apply_operation(:face, body, []), do: OCEx.face(body)

  defp apply_operation(:project, body, [target, opts]) do
    with {:ok, target_shape} <- evaluate_shape(target),
         do: OCEx.project(body, target_shape, opts)
  end

  defp apply_operation(:surface, body, [selector]) do
    with {:ok, faces} <- Smith.Selector.select(body, :faces, selector),
         :ok <- nonempty(faces),
         do: OCEx.sew(faces)
  end

  defp apply_operation(op, body, [distance, opts]) when op in [:offset, :thicken],
    do: apply(OCEx, op, [body, distance, opts])

  defp apply_operation(:draft, body, opts) do
    with :ok <-
           options(opts, [:faces, :neutral, :angle, :direction, :count], [
             :faces,
             :neutral,
             :angle
           ]),
         {:ok, frame} <- modeling_frame(opts[:neutral]),
         {:ok, selected} <- Smith.Selector.select(body, :faces, opts[:faces]),
         :ok <- nonempty(selected),
         :ok <- selection_count(selected, opts[:count]),
         do:
           OCEx.draft(
             body,
             selected,
             Keyword.get(opts, :direction, frame.n),
             opts[:angle],
             frame.origin,
             frame.n
           )
  end

  defp apply_operation(:shell, body, opts) do
    with :ok <- options(opts, [:openings, :thickness, :join, :count], [:openings, :thickness]),
         {:ok, selected} <- Smith.Selector.select(body, :faces, opts[:openings]),
         :ok <- nonempty(selected),
         :ok <- selection_count(selected, opts[:count]),
         native_opts = Keyword.take(opts, [:join]),
         {:ok, shape} <- OCEx.shell(body, selected, opts[:thickness], native_opts),
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

  defp apply_operation(:sphere, nil, [radius, opts]),
    do: placed_primitive(:sphere, [radius], opts, {:center, :center, :center})

  defp apply_operation(:torus, nil, [major, minor, opts]),
    do: placed_primitive(:torus, [major, minor], opts, {:center, :center, :center})

  defp apply_operation(op, body, [plane]) when op in [:mirror, :section] do
    with {:ok, frame} <- modeling_frame(plane),
         do: apply(OCEx, op, [body, frame.origin, frame.n])
  end

  defp apply_operation(:split, body, [plane, opts]) do
    with {:ok, frame} <- modeling_frame(plane),
         do: OCEx.split(body, frame.origin, frame.n, opts)
  end

  defp apply_operation(:box, nil, [x, y, z]), do: OCEx.box(x, y, z)

  defp apply_operation(op, nil, args)
       when op in [:cylinder, :cone, :sphere, :torus, :edge, :arc, :spline, :bezier],
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
    with {:ok, tool_shape} <- evaluate_shape(tool),
         {:ok, shape} <- apply(OCEx, op, [body, tool_shape]),
         do: OCEx.clean(shape)
  end

  defp apply_operation(op, body, [tools]) when op in [:cut_many, :fuse_many] and is_list(tools) do
    if Code.ensure_loaded?(OCEx) and function_exported?(OCEx, op, 2) do
      with {:ok, shapes} <- evaluate_edges(tools),
           {:ok, shape} <- apply(OCEx, op, [body, shapes]),
           do: OCEx.clean(shape)
    else
      {:error, :unsupported_operation}
    end
  end

  defp apply_operation(op, body, opts) when op in [:fillet, :chamfer] do
    size = if op == :fillet, do: :radius, else: :distance

    with :ok <- options(opts, [:edges, size, :count], [:edges, size]),
         {:ok, selected} <- selected_edges(body, opts[:edges]),
         :ok <- selection_count(selected, Keyword.get(opts, :count)),
         {:ok, shape} <- apply(OCEx, op, [body, selected, opts[size]]),
         do: OCEx.clean(shape)
  end

  defp apply_operation(kind, body, opts) when kind in [:hole, :counterbore, :countersink],
    do: Smith.Features.Hole.evaluate(body, kind, opts)

  defp apply_operation(_, _, _), do: {:error, :invalid_operation}

  defp modeling_frame(plane) do
    plane =
      case plane do
        :xy -> Smith.Plane.xy()
        :xz -> Smith.Plane.xz()
        :yz -> Smith.Plane.yz()
        other -> other
      end

    Smith.Plane.frame(plane)
  end

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
           |> List.to_tuple() do
      shift(shape, Smith.Plane.add(offset, at))
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  rescue
    ArithmeticError -> {:error, :invalid_argument}
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
      case evaluate_shape(edge) do
        {:ok, shape} -> {:cont, {:ok, acc ++ [shape]}}
        error -> {:halt, error}
      end
    end)
  end

  defp selection_count(_, nil), do: :ok

  defp selection_count(edges, n) when is_integer(n) and n > 0 do
    if length(edges) == n, do: :ok, else: {:error, :selection_count_mismatch}
  end

  defp selection_count(_, _), do: {:error, :invalid_options}

  defp selected_edges(body, selector), do: Smith.Selector.select(body, :edges, selector)

  defp options(opts, allowed, required) do
    if is_list(opts) and Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
         Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
         Enum.all?(required, &Keyword.has_key?(opts, &1)),
       do: :ok,
       else: {:error, :invalid_options}
  end

  defp nonempty([]), do: {:error, :empty_selection}
  defp nonempty(_), do: :ok
  defp sweep_wire([wire]), do: {:ok, wire}
  defp sweep_wire(_), do: {:error, :sweep_profile_has_holes}
end
