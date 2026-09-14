# Joints and assembly poses

An attachment frame defines where a member connects. A connection moves one
member to another frame and applies explicit motion coordinates. These are
ordinary deferred recipe operations; geometry changes at `Smith.evaluate/1`.

## Attach a rotating arm

```elixir
alias Smith.{Assembly, Plane}

fixture = Assembly.new(:hinge)
  |> Assembly.part(:base, Smith.box(20, 20, 4), print: [on_bed: true])
  |> Assembly.part(:arm, Smith.box(30, 6, 3), print: [on_bed: true])
  |> Assembly.joint(:pivot, on: :base, at: Plane.xy(origin: {10, 10, 4.4}))
  |> Assembly.joint(:pin, on: :arm, at: Plane.xy(origin: {3, 3, 0}))

posed = Assembly.connect(fixture, :pin,
  to: :pivot, kind: :revolute, angle: 45, limits: [angle: {-90, 90}])
{:ok, result} = Smith.evaluate(posed)
{:ok, pin} = Assembly.fetch_joint(result, :pin)
{:ok, arm} = Assembly.fetch(result, :arm)
```

<div class="smith-doc-preview" data-preview="joints-0-result" data-model="result" data-label="Revolute joint at 45 degrees">
<p>Interactive preview available in HexDocs.</p>
</div>

The source (`:pin`) moves; the target (`:pivot`) belongs to the member it follows.
`on:` names an immediate part, reference, or subassembly. `at:` is a `Smith.Plane`
in the member's original recipe coordinates, before placement. It defaults to
`:xy`; the other named planes `:xz` and `:yz` are also accepted. Normals are the
local Z axes, and local X fixes rotational alignment. Joint names occupy a
separate namespace from member names and follow the same normalization rules.

Alignment matches both frame normals and X axes. There is no automatic normal
reversal for mating faces. Define opposing local frames if that is what the
design requires. A connection overrides the moving member's initial position
and rotation; geometry within that member stays rigid.

## Choose the allowed motion

| Kind | Coordinates | Motion |
| --- | --- | --- |
| `:rigid` (default) | none | Coincident frames |
| `:revolute` | `angle:` | Rotation about target-local Z |
| `:linear` | `offset:` | Translation along target-local Z |
| `:cylindrical` | `angle:`, `offset:` | Rotation and translation along that axis |
| `:ball` | `angles: {x, y, z}` | Rotations about fixed target X, then Y, then Z |

Angles use degrees and offsets use millimeters. Coordinates default to zero.
Positive rotation follows the right-hand rule. Ball angles are fixed-axis Euler
coordinates: their combined rotation is Z × Y × X, applied to the source frame.
They are pose parameters, not a unique description of orientation.

`limits:` is an optional keyword list of inclusive `{minimum, maximum}` pairs.
Use `:angle` and/or `:offset` for axis joints, and `:x`, `:y`, `:z` for ball
angles. An omitted limit is unbounded. Incorrect keys or reversed intervals
return `:invalid_options`; a coordinate outside its interval returns `:joint_limit`.
Values are checked as supplied, without clamping or wrapping angles.

```elixir
raised = Assembly.connect(fixture, :pin,
  to: :pivot, kind: :cylindrical, angle: 30, offset: 8,
  limits: [angle: {-90, 90}, offset: {0, 10}])

tilted = Assembly.connect(fixture, :pin,
  to: :pivot, kind: :ball, angles: {20, 0, 30}, limits: [x: {-30, 30}])
```

<div class="smith-doc-preview" data-preview="joints-1-raised" data-model="raised" data-label="Raised cylindrical joint">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="joints-1-tilted" data-model="tilted" data-label="Tilted ball joint">
<p>Interactive preview available in HexDocs.</p>
</div>

Start each variant from the unconnected fixture, or write a function whose
parameters define its connection. A second connection on the same moving member
fails with `:multiple_connections`; it does not replace the first.

## Chains and nested instances

A target can itself be on a connected member. Evaluation resolves target
dependencies before moving their dependents, regardless of declaration order.
There must be at most one controlling connection per moving member. Cycles
return `:connection_cycle`; connecting two frames on the same member returns
`:self_connection`.

Inside a subassembly, connections resolve before it is placed by the parent.
At the parent level, a path such as `[:module, :pin]` addresses a joint defined
inside that instance. Connecting it moves the **whole top-level instance**, not
just the leaf bearing the frame. Its internal poses, references, and printable
extras move together. Define a connection inside the child recipe to move only
one of that child's members.

Joint lookup uses lists or slash paths, as with member lookup. The returned
`Smith.Assembly.Joint` holds a normalized name, the member path relative to the
lookup result, and the final world frame (`origin`, `u`, `v`, `n`). Unknown paths
return `:unknown_joint`. These values are snapshots, not mutable constraints.

## Export and validation

```elixir
{:ok, files} = Smith.export(result, "output", name: "posed-hinge")
[%{kind: :revolute, values: %{angle: 45}}] = files.connections
```

<div class="smith-doc-preview" data-preview="joints-2-result" data-model="result" data-label="Exported hinge pose">
<p>Interactive preview available in HexDocs.</p>
</div>

STEP captures the evaluated pose. Printed leaves use their existing print options
on the final world shapes. JSON reports retain joint frames, connection parameters,
and each tree node's resolved world `pose` alongside its original placement options.
Subassembly nodes include their own joints and connections; their joint member
paths are relative to that node, while frame coordinates remain world-space.

Connections calculate directed rigid placement. They do not solve closed linkages,
infer mating faces, detect collisions, model loads, or check travel clearance.
Use geometric measurements and intersections appropriate to the design. Printable
mesh and STEP checks still run at export, but they do not prove mechanical fit.

The [joint Livebook](https://github.com/ntodd/smith/blob/main/examples/joints.livemd)
shows several hinge poses, all five motion types, attachment-frame inspection,
a vertical-gap check, and verified printable exports.
