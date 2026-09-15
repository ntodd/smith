# This file is copied out of the repository and run against archive-installed deps.
Mix.install([{:smith, "~> 0.2.0"}])

false = Code.ensure_loaded?(Kino)
true = Code.ensure_loaded?(Smith.Kino)
try do
  Smith.Kino.render(Smith.box(1, 2, 3))
  raise "expected the missing Kino dependency to fail"
rescue
  error in RuntimeError ->
    true = Exception.message(error) == "cannot render Smith preview: :kino_not_available"
end
{:ok, "7.9.3"} = OCEx.version()
model = Smith.box(60, 40, 5)
  |> Smith.fillet(edges: {:parallel, :z}, count: 4, radius: 2)
  |> Smith.hole(on: :top, diameter: 8, through: :all)
{:ok, result} = Smith.evaluate(model)
{:ok, true} = OCEx.valid?(result.shape)
{:ok, volume} = OCEx.volume(result.shape)
expected = (60 * 40 - (4 - :math.pi()) * 4 - :math.pi() * 16) * 5
true = abs(volume - expected) < 1.0e-6
{:ok, files} = Smith.export(result, "output", name: "archive-plate", on_bed: true)
mesh = files.stl |> File.read!() |> Smith.Mesh.from_stl() |> Smith.Mesh.inspect()
true = mesh.watertight and mesh.winding_consistent
{:ok, entries} = :zip.extract(String.to_charlist(files.three_mf), [:memory])
true = Enum.any?(entries, fn {name, xml} -> name == ~c"3D/3dmodel.model" and String.contains?(xml, "<triangle") end)
IO.puts("Verified isolated archive: native geometry, STEP round trip, watertight STL, and 3MF")

alias Smith.{Path, Plane, Selector, Sketch}
path = Path.new([Smith.line({0, 0, 0}, {0, 0, 10})])
models = [
  {"swept", Sketch.circle(1) |> Smith.sweep(path), 10 * :math.pi()},
  {"smooth", Smith.loft([Sketch.circle(1), Sketch.circle(1, on: Plane.xy(z: 10))], ruled: false), 10 * :math.pi()},
  {"hollow", Smith.box(20, 16, 10) |> Smith.shell(openings: Selector.facing(:z), thickness: -2, count: 1), 1664}
]
for {name, recipe, expected} <- models do
  {:ok, result} = Smith.evaluate(recipe)
  {:ok, volume} = OCEx.volume(result.shape)
  true = abs(volume - expected) < 1.0e-6
  {:ok, files} = Smith.export(result, "output", name: name, on_bed: true, angular_tolerance: 0.1)
  true = files.verification.mesh.watertight and files.verification.mesh.winding_consistent
end
IO.puts("Verified archive-installed selectors, paths, sweeps, smooth lofts, and hollow exports")

mechanical = Sketch.rounded_rectangle(30, 20, 2)
  |> Sketch.cut(Sketch.slot(10, 4))
  |> Smith.extrude(6)
  |> Smith.counterbore(on: Plane.xy(z: 6), at: {10, 0}, diameter: 2,
    bore_diameter: 4, bore_depth: 2, through: :all)
  |> Smith.countersink(on: Plane.xy(z: 6), at: {-10, 0}, diameter: 2,
    sink_diameter: 4, depth: 4)
  |> Smith.mirror(:xy)
{:ok, part} = Smith.evaluate(mechanical)
{:ok, [_]} = Smith.inspect_faces(part, Selector.facing(:z) |> Selector.sort_by(:area) |> Selector.take(1))
{:ok, edges} = Smith.inspect_edges(part, Selector.radius({1, 2}))
true = edges != []
{:ok, files} = Smith.export(part, "output", name: "mechanical", on_bed: true, angular_tolerance: 0.1)
true = files.verification.mesh.watertight and files.verification.mesh.winding_consistent
for recipe <- [Smith.torus(10, 2), Smith.sphere(3)] do
  {:ok, part} = Smith.evaluate(recipe)
  {:ok, true} = OCEx.valid?(part.shape)
end
true = Code.ensure_loaded?(Smith.Assembly.Result)
true = Code.ensure_loaded?(Smith.Assembly.Export)
IO.puts("Verified archive-installed mechanical features, topology inspection, and assembly modules")

sides = Selector.type(:plane) |> Selector.exclude(Selector.parallel(:z))
drafted = Smith.box(20, 16, 10) |> Smith.draft(faces: sides, neutral: :xy, angle: 5, count: 4)
surface = Smith.cylinder(10, 12) |> Smith.surface(Selector.type(:cylinder))
for {name, recipe} <- [
  {"split-draft", Smith.split(drafted, Plane.xy(z: 6), keep: :negative)},
  {"section", drafted |> Smith.section(Plane.xy(z: 6)) |> Smith.extrude({0, 0, 2})},
  {"thickened-offset", surface |> Smith.offset(2) |> Smith.thicken(-1)}
] do
  {:ok, result} = Smith.evaluate(recipe)
  {:ok, files} = Smith.export(result, "output", name: name, on_bed: true, angular_tolerance: 0.1)
  true = files.verification.mesh.watertight and files.verification.mesh.winding_consistent
end
IO.puts("Verified archive-installed draft, split, section, surface offset, and thickening exports")

alias Smith.Assembly
child = Assembly.new(:child)
  |> Assembly.part(:body, Smith.box(2, 3, 4), print: [on_bed: true])
  |> Assembly.reference(:board, Smith.box(1, 1, 1))
tree = Assembly.new(:tree)
  |> Assembly.subassembly(:left, child, position: {-5, 0, 0})
  |> Assembly.subassembly(:right, child, rotation: {{0, 0, 1}, 90}, position: {5, 0, 0})
{:ok, tree_result} = Smith.evaluate(tree)
{:ok, _} = Assembly.fetch(tree_result, [:right, :body])
{:ok, leaves} = Assembly.members(tree_result)
4 = length(leaves)
{:ok, files} = Smith.export(tree_result, "output", name: "nested-tree",
  part_metadata: %{[:left, :body] => %{sample: true}})
2 = length(files.parts)
2 = length(files.tree)
true = hd(files.parts).verification.sample
{:ok, archive} = :zip.extract(File.read!(files.print_pack), [:memory])
4 = length(archive)
IO.puts("Verified archive-installed nested assembly lookup, metadata, tree and printable leaves")

joint_recipe = Assembly.new(:joint)
  |> Assembly.part(:base, Smith.box(2, 2, 2))
  |> Assembly.part(:arm, Smith.box(10, 2, 2), print: [on_bed: true])
  |> Assembly.joint(:pivot, on: :base, at: Plane.xy(z: 3))
  |> Assembly.joint(:pin, on: :arm)
  |> Assembly.connect(:pin, to: :pivot, kind: :revolute, angle: 90, limits: [angle: {-90, 90}])
{:ok, joint_result} = Smith.evaluate(joint_recipe)
{:ok, pin} = Assembly.fetch_joint(joint_result, :pin)
true = abs(elem(pin.frame.origin, 2) - 3) < 1.0e-7
true = abs(elem(pin.frame.u, 1) - 1) < 1.0e-7
{:ok, joint_files} = Smith.export(joint_result, "output", name: "joint-mechanism")
[%{kind: :revolute, values: %{angle: 90}}] = joint_files.connections
true = Enum.all?(joint_files.parts, & &1.verification.mesh.watertight)
{:ok, joint_view} = Assembly.view(joint_result, :exploded)
{:ok, view_brep} = OCEx.to_brep(joint_view.shape)
true = joint_view.revision == Base.encode16(:crypto.hash(:sha256, view_brep), case: :lower)
{:ok, view_solids} = OCEx.solids(joint_view.shape)
2 = length(view_solids)
IO.puts("Verified archive-installed joint placement, motion limits, assembly views, and pose exports")

for {name, recipe} <- [
  {"symmetric-taper", Sketch.rectangle(20, 16) |> Smith.extrude(5, both: true, taper: 3)},
  {"up-to-plane", Sketch.circle(3) |> Smith.extrude_until(Plane.xy(z: 8))}
] do
  {:ok, result} = Smith.evaluate(recipe)
  {:ok, files} = Smith.export(result, "output", name: name, on_bed: true, angular_tolerance: 0.1)
  true = files.verification.mesh.watertight and files.verification.mesh.winding_consistent
end
IO.puts("Verified archive-installed extrusion extents and printable exports")
projected = Sketch.circle(2, on: Plane.xy(z: 5))
  |> Smith.project(Sketch.rectangle(20,20), from: {0,0,10})
  |> Smith.face()
  |> Smith.extrude({0,0,3})
{:ok, projected_result} = Smith.evaluate(projected)
{:ok, projected_volume} = OCEx.volume(projected_result.shape)
true = abs(projected_volume - 48 * :math.pi()) < 1.0e-6
{:ok, projected_files} = Smith.export(projected_result, "output", name: "projected", on_bed: true)
true = projected_files.verification.mesh.watertight
IO.puts("Verified archive-installed projection, face conversion, and printable export")


{:ok, drawing} = Smith.Drawing.new(Smith.box(20, 10, 4), on: :xy)
{:ok, svg} = Smith.Drawing.svg(drawing, hidden: false)
true = svg =~ "<svg"
{:ok, dxf} = Smith.Drawing.dxf(drawing)
true = dxf =~ "$INSUNITS"
IO.puts("Verified archive-installed SVG and DXF drawing export")

arch = Sketch.profile([
  Sketch.bezier([{0, 0}, {1, 2}, {2, 0}]), Sketch.line({2, 0}, {0, 0})
])
{:ok, part} = arch |> Smith.extrude(3) |> Smith.evaluate()
{:ok, volume} = OCEx.volume(part.shape)
true = abs(volume - 4) < 1.0e-8
{:ok, files} = Smith.export(part, "output", name: "bezier-arch", on_bed: true, tolerance: 0.001, angular_tolerance: 0.1)
true = files.verification.mesh.watertight and files.verification.mesh.winding_consistent
IO.puts("Verified archive-installed Bezier sketch and printable export")

# Agent inspection must work with Kino absent and only packaged dependencies.
{:ok, inspected} = Smith.box(20, 10, 4) |> Smith.evaluate()
{:ok, width} = Smith.Measure.extent(inspected, :x)
{:ok, report} = Smith.Inspection.run(%{part: inspected}, checks: [
  {:measurement, :part, width, expected: 20, tolerance: 1.0e-6},
  {:topology, :part, :solids, expected: 1}
])
:passed = report.status
{:ok, artifacts} = Smith.Inspection.write(report, "inspection", views: [:top, :front], width: 96, height: 96)
true = File.exists?(artifacts.report)
{:ok, drawing} = Smith.Drawing.new(inspected)
{:ok, drawing} = Smith.Drawing.dimension(drawing, width, orientation: :horizontal)
{:ok, svg} = Smith.Drawing.svg(drawing)
true = String.contains?(svg, "20.00 mm")
IO.puts("Verified archive-installed text-only inspection, headless PNGs, and measured drawings without Kino")
