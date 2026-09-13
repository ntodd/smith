defmodule Smith.JointTest do
  use ExUnit.Case, async: true
  alias Smith.{Assembly, Plane}
  @moduletag :tmp_dir

  defp mechanism(kind, opts \\ []) do
    Assembly.new(:mechanism)
    |> Assembly.part(:base, Smith.box(2, 2, 2), position: {-10, 0, 0})
    |> Assembly.part(:arm, Smith.box(20, 2, 3, at: {0, -1, 0}), position: {100, 100, 100})
    |> Assembly.joint(:pivot, on: :base, at: Plane.xy(origin: {20, 0, 5}))
    |> Assembly.joint(:pin, on: :arm)
    |> Assembly.connect(:pin, [to: :pivot, kind: kind] ++ opts)
  end

  defp bounds(result, name, low, high) do
    assert {:ok, member} = Assembly.fetch(result, name)
    assert {:ok, {a, b}} = OCEx.bounds(member.shape)

    for {actual, expected} <- Enum.zip(Tuple.to_list(a) ++ Tuple.to_list(b), low ++ high),
        do: assert_in_delta(actual, expected, 1.0e-7)
  end

  test "rigid alignment overrides initial moving placement and preserves input recipes" do
    recipe = mechanism(:rigid)
    assert {:ok, result} = Smith.evaluate(recipe)
    bounds(result, :arm, [10, -1, 5], [30, 1, 8])
    bounds(result, :base, [-10, 0, 0], [-8, 2, 2])
    assert {:ok, pin} = Assembly.fetch_joint(result, :pin)
    assert {:ok, pivot} = Assembly.fetch_joint(result, :pivot)
    assert pin.member == ["arm"]
    assert pin.frame == pivot.frame
    assert {:ok, original} = Smith.evaluate(%{recipe | connections: []})
    bounds(original, :arm, [100, 99, 100], [120, 101, 103])
  end

  test "revolute motion rotates about target local Z, retaining pivot and material" do
    for angle <- [-90, 0, 90] do
      assert {:ok, result} =
               mechanism(:revolute, angle: angle, limits: [angle: {-90, 90}]) |> Smith.evaluate()

      assert {:ok, arm} = Assembly.fetch(result, :arm)
      assert {:ok, volume} = OCEx.volume(arm.shape)
      assert_in_delta volume, 120, 1.0e-7
      assert {:ok, pin} = Assembly.fetch_joint(result, :pin)
      assert pin.frame.origin == {10.0, 0.0, 5.0}
      {x, y, z} = pin.frame.u
      assert_in_delta x, :math.cos(angle * :math.pi() / 180), 1.0e-9
      assert_in_delta y, :math.sin(angle * :math.pi() / 180), 1.0e-9
      assert_in_delta z, 0, 1.0e-9
      if angle == 90, do: bounds(result, :arm, [9, 0, 5], [11, 20, 8])
    end
  end

  test "linear and cylindrical motion use signed target-local displacement" do
    assert {:ok, linear} =
             mechanism(:linear, offset: -3, limits: [offset: {-3, 8}]) |> Smith.evaluate()

    bounds(linear, :arm, [10, -1, 2], [30, 1, 5])
    assert {:ok, cylinder} = mechanism(:cylindrical, angle: 90, offset: 7) |> Smith.evaluate()
    bounds(cylinder, :arm, [9, 0, 12], [11, 20, 15])
  end

  test "ball motion applies rotations around fixed local X then Y then Z axes" do
    recipe =
      Assembly.new(:ball)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.part(:tip, Smith.box(2, 3, 4))
      |> Assembly.joint(:socket, on: :base)
      |> Assembly.joint(:ball, on: :tip)
      |> Assembly.connect(:ball,
        to: :socket,
        kind: :ball,
        angles: {90, 0, 90},
        limits: [x: {0, 90}, z: {-90, 90}]
      )

    assert {:ok, result} = Smith.evaluate(recipe)
    bounds(result, :tip, [0, 0, 0], [4, 2, 3])
  end

  test "arbitrary and opposing attachment frames align axes and origins" do
    for normal <- [{0, 0, -1}, {1, 2, 3}, {0, 1, 0}] do
      recipe =
        Assembly.new(:alignment)
        |> Assembly.part(:base, Smith.box(1, 1, 1),
          rotation: {{1, 1, 0}, 137},
          position: {7, 11, 13}
        )
        |> Assembly.part(:moving, Smith.box(2, 3, 4), rotation: {{1, 2, 3}, 211})
        |> Assembly.joint(:target, on: :base, at: Plane.new(origin: {2, 3, 5}, normal: normal))
        |> Assembly.joint(:source,
          on: :moving,
          at: Plane.new(origin: {-1, 2, 4}, normal: {2, 0, 1})
        )
        |> Assembly.connect(:source, to: :target)

      assert {:ok, result} = Smith.evaluate(recipe)
      assert {:ok, source} = Assembly.fetch_joint(result, :source)
      assert {:ok, target} = Assembly.fetch_joint(result, :target)

      for key <- [:origin, :u, :v, :n],
          {a, b} <- Enum.zip(Tuple.to_list(source.frame[key]), Tuple.to_list(target.frame[key])),
          do: assert_in_delta(a, b, 1.0e-8)

      assert :ok = Assembly.validate_result(result)
    end
  end

  test "connections resolve dependencies independently of declaration order" do
    base =
      Assembly.new(:chain)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.part(:first, Smith.box(4, 1, 1))
      |> Assembly.part(:second, Smith.box(4, 1, 1))
      |> Assembly.joint(:fixed, on: :base, at: Plane.xy(z: 2))
      |> Assembly.joint(:first_in, on: :first)
      |> Assembly.joint(:first_out, on: :first, at: Plane.xy(origin: {4, 0, 0}))
      |> Assembly.joint(:second_in, on: :second)

    connections = [
      [:second_in, [to: :first_out]],
      [:first_in, [to: :fixed, kind: :revolute, angle: 90]]
    ]

    for order <- [connections, Enum.reverse(connections)] do
      recipe =
        Enum.reduce(order, base, fn [source, opts], acc -> Assembly.connect(acc, source, opts) end)

      assert {:ok, result} = Smith.evaluate(recipe)
      bounds(result, :first, [-1, 0, 2], [0, 4, 3])
      bounds(result, :second, [-1, 4, 2], [0, 8, 3])
    end
  end

  test "nested endpoint moves its whole top-level instance, including references and extras" do
    child =
      Assembly.new(:module)
      |> Assembly.part(:body, Smith.box(2, 3, 4), position: {5, 0, 0})
      |> Assembly.part(:coupon, Smith.box(1, 1, 1), installed: false)
      |> Assembly.reference(:board, Smith.box(1, 1, 1), position: {0, 0, 10})
      |> Assembly.joint(:pin, on: :body, at: Plane.xy(z: 4))

    root =
      Assembly.new(:root)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.subassembly(:module, child, position: {100, 0, 0})
      |> Assembly.joint(:socket, on: :base, at: Plane.xy(origin: {20, 0, 30}))
      |> Assembly.connect([:module, :pin], to: :socket)

    assert {:ok, result} = Smith.evaluate(root)
    bounds(result, [:module, :body], [20, 0, 26], [22, 3, 30])
    bounds(result, [:module, :coupon], [15, 0, 26], [16, 1, 27])
    bounds(result, [:module, :board], [15, 0, 36], [16, 1, 37])
    assert {:ok, joint} = Assembly.fetch_joint(result, "module/pin")
    assert joint.member == ["module", "body"]
    assert {:ok, branch} = Assembly.fetch(result, :module)
    assert {:ok, local} = Assembly.fetch_joint(branch, :pin)
    assert local.frame == joint.frame
    assert :ok = Assembly.validate_result(result)
  end

  test "unknown endpoints, self-links, multiple parents, and cycles fail explicitly" do
    base =
      Assembly.new(:bad)
      |> Assembly.part(:a, Smith.box(1, 1, 1))
      |> Assembly.part(:b, Smith.box(1, 1, 1))
      |> Assembly.joint(:a_in, on: :a)
      |> Assembly.joint(:a_out, on: :a)
      |> Assembly.joint(:b_in, on: :b)

    for {recipe, reason} <- [
          {Assembly.connect(base, :missing, to: :a_in), :unknown_joint},
          {Assembly.connect(base, :a_in, to: :a_out), :self_connection},
          {base |> Assembly.connect(:a_in, to: :b_in) |> Assembly.connect(:a_out, to: :b_in),
           :multiple_connections},
          {base |> Assembly.connect(:a_in, to: :b_in) |> Assembly.connect(:b_in, to: :a_in),
           :connection_cycle}
        ] do
      assert {:error, %Smith.Error{operation: :connect, reason: ^reason}} = Smith.evaluate(recipe)
    end
  end

  test "joint definitions and motion limits validate even when geometry is otherwise valid" do
    base = Assembly.new(:bad) |> Assembly.part(:body, Smith.box(1, 1, 1))

    for {opts, reason} <- [
          {[on: :missing], :unknown_joint_member},
          {[on: :body, at: Plane.new(normal: {0, 0, 0})], :invalid_plane},
          {[on: :body, typo: 3], :invalid_options}
        ] do
      assert {:error, %Smith.Error{operation: :joint, reason: ^reason}} =
               base |> Assembly.joint(:pin, opts) |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{reason: :duplicate_joint}} =
             base
             |> Assembly.joint(:a_b, on: :body)
             |> Assembly.joint("a-b", on: :body)
             |> Smith.evaluate()

    for {kind, opts, reason} <- [
          {:rigid, [angle: 10], :invalid_options},
          {:linear, [angle: 10], :invalid_options},
          {:ball, [angles: {1, 2}], :invalid_options},
          {:revolute, [angle: 91, limits: [angle: {-90, 90}]], :joint_limit},
          {:linear, [offset: 3, limits: [offset: {4, 2}]], :invalid_options},
          {:ball, [angles: {0, 20, 0}, limits: [y: {-10, 10}]], :joint_limit},
          {:unknown, [], :invalid_options}
        ] do
      assert {:error, %Smith.Error{operation: :connect, reason: ^reason}} =
               mechanism(kind, opts) |> Smith.evaluate()
    end
  end

  test "joint poses export valid parts and describe the evaluated connection", %{tmp_dir: root} do
    assert {:ok, result} =
             mechanism(:revolute, angle: 30, limits: [angle: {-90, 90}]) |> Smith.evaluate()

    assert {:ok, report} = Smith.export(result, root, name: "hinge")

    assert [%{from: "pin", to: "pivot", kind: :revolute, values: %{angle: 30}}] =
             report.connections

    assert Enum.map(report.joints, & &1.name) == ["pivot", "pin"]
    assert Enum.all?(report.parts, & &1.verification.mesh.watertight)
    assert {:ok, shape} = OCEx.read_step(report.assembly_step)
    assert {:ok, solids} = OCEx.solids(shape)
    assert length(solids) == 2
    assert {:ok, archive} = :zip.extract(File.read!(report.print_pack), [:memory])
    assert length(archive) == 4
  end

  test "local slide direction follows a tilted target frame" do
    recipe =
      Assembly.new(:slide)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.part(:runner, Smith.box(2, 3, 4))
      |> Assembly.joint(:rail, on: :base, at: Plane.yz(x: 10))
      |> Assembly.joint(:shoe, on: :runner)
      |> Assembly.connect(:shoe, to: :rail, kind: :linear, offset: 5)

    assert {:ok, result} = Smith.evaluate(recipe)
    bounds(result, :runner, [15, 0, 0], [19, 2, 3])
  end

  test "internal joints survive instancing and a parent connection", %{tmp_dir: root} do
    child =
      Assembly.new(:child)
      |> Assembly.part(:base, Smith.box(1, 1, 1))
      |> Assembly.part(:arm, Smith.box(4, 1, 1))
      |> Assembly.joint(:pivot, on: :base, at: Plane.xy(z: 2))
      |> Assembly.joint(:pin, on: :arm)
      |> Assembly.connect(:pin, to: :pivot, kind: :revolute, angle: 90)

    parent =
      Assembly.new(:parent)
      |> Assembly.part(:fixed, Smith.box(1, 1, 1))
      |> Assembly.subassembly(:child, child, position: {100, 0, 0})
      |> Assembly.joint(:socket, on: :fixed, at: Plane.xy(origin: {10, 20, 30}))
      |> Assembly.connect([:child, :pivot], to: :socket, kind: :revolute, angle: 90)

    assert {:ok, result} = Smith.evaluate(parent)
    bounds(result, [:child, :arm], [6, 19, 30], [10, 20, 31])
    assert {:ok, joint} = Assembly.fetch_joint(result, [:child, :pin])
    assert {:ok, target} = Assembly.fetch_joint(result, [:child, :pivot])

    for {a, b} <- Enum.zip(Tuple.to_list(joint.frame.origin), Tuple.to_list(target.frame.origin)),
        do: assert_in_delta(a, b, 1.0e-8)

    assert_in_delta elem(joint.frame.u, 0), -1, 1.0e-8
    assert {:ok, report} = Smith.export(result, root, name: "nested-joint", formats: [:three_mf])
    child_report = Enum.find(report.tree, &(&1.name == "child"))
    assert [%{kind: :revolute, values: %{angle: 90}}] = child_report.connections
    assert Enum.map(child_report.joints, & &1.name) == ["pivot", "pin"]
    assert child_report.pose.origin != {100, 0, 0}
  end

  test "half turns and tiny nonzero rotations retain alignment" do
    for angle <- [0.00001, 179.99999, 180, 180.00001, 359.99999] do
      recipe =
        Assembly.new(:rotated)
        |> Assembly.part(:fixed, Smith.box(1, 1, 1), rotation: {{1, 2, 3}, angle})
        |> Assembly.part(:moving, Smith.box(2, 3, 4))
        |> Assembly.joint(:target, on: :fixed)
        |> Assembly.joint(:source, on: :moving)
        |> Assembly.connect(:source, to: :target)

      assert {:ok, result} = Smith.evaluate(recipe)
      assert {:ok, source} = Assembly.fetch_joint(result, :source)
      assert {:ok, target} = Assembly.fetch_joint(result, :target)

      for key <- [:u, :v, :n],
          {a, b} <- Enum.zip(Tuple.to_list(source.frame[key]), Tuple.to_list(target.frame[key])),
          do: assert_in_delta(a, b, 1.0e-9)

      assert {:ok, moving} = Assembly.fetch(result, :moving)
      assert {:ok, volume} = OCEx.volume(moving.shape)
      assert_in_delta volume, 24, 1.0e-7
    end
  end
end
