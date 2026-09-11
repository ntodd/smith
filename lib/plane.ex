defmodule Smith.Plane do
  @moduledoc """
  A local, right-handed coordinate frame for sketches and holes.

  A plane consists of an origin, two in-plane unit axes, and a unit normal.
  Sketch coordinates `{u, v}` are measured along those local axes.
  Positive sketch extrusion follows the normal.

  | Constructor | Local X | Local Y | Normal |
  | --- | --- | --- | --- |
  | `xy/1` | +X | +Y | +Z |
  | `yz/1` | +Y | +Z | +X |
  | `xz/1` | +X | +Z | −Y |

  Constructors return deferred values. `to_world/2`, `normal/1`, or
  model evaluation validates the definition. A plane does not select or
  attach to a model face: moving a body does not move its plane.
  See [sketches and planes](sketches.html) for placement examples.
  """
  defstruct kind: :xy, options: []
  @type t :: %__MODULE__{kind: atom(), options: keyword()}
  @doc """
  Defines an XY plane with local X=world +X, local Y=world +Y, and normal +Z.

  Accepts `z:` (default 0) or `origin: {x, y, z}`, but not both.
  The `:z` option sets the world Z coordinate, with X=Y=0.

      iex> Smith.Plane.xy(z: 5) |> Smith.Plane.to_world({2, 3})
      {:ok, {2.0, 3.0, 5.0}}
  """
  @spec xy(keyword()) :: t()
  def xy(opts \\ []), do: %__MODULE__{kind: :xy, options: opts}

  @doc """
  Defines a YZ plane with local X=world +Y, local Y=world +Z, and normal +X.

  Accepts `x:` (default 0) or `origin: {x, y, z}`, but not both.
  The `:x` option sets the world X coordinate, with Y=Z=0.

      iex> Smith.Plane.yz(x: 10) |> Smith.Plane.to_world({2, 3})
      {:ok, {10.0, 2.0, 3.0}}
  """
  @spec yz(keyword()) :: t()
  def yz(opts \\ []), do: %__MODULE__{kind: :yz, options: opts}

  @doc """
  Defines an XZ plane with local X=world +X, local Y=world +Z, and normal −Y.

  Accepts `y:` (default 0) or `origin: {x, y, z}`, but not both.
  `:y` sets the world Y coordinate, not a signed offset along the normal.
  A positive sketch extrusion therefore moves toward decreasing world Y.

      iex> Smith.Plane.xz(y: 10) |> Smith.Plane.to_world({2, 3})
      {:ok, {2.0, 10.0, 3.0}}
      iex> Smith.Plane.xz() |> Smith.Plane.normal()
      {:ok, {0.0, -1.0, 0.0}}
  """
  @spec xz(keyword()) :: t()
  def xz(opts \\ []), do: %__MODULE__{kind: :xz, options: opts}

  @doc """
  Defines a plane from a world origin and two direction vectors.

  Options default to `origin: {0, 0, 0}`, `normal: {0, 0, 1}`, and
  `x_direction: {1, 0, 0}`. At evaluation, the normal is normalized and
  `:x_direction` is projected into the plane, then normalized. Local Y is
  the cross product of the normal and local X.

  Both the normal and projected X must have magnitude greater than 1.0e-12.
  A zero normal or parallel X direction returns `:invalid_plane` when
  queried or evaluated. Supply another X direction when the default is
  parallel to your chosen normal. Unknown or duplicate options also fail.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: %__MODULE__{kind: :custom, options: opts}

  @spec to_world(t(), {number(), number()}) ::
          {:ok, {float(), float(), float()}} | {:error, atom()}
  @doc """
  Converts a local `{u, v}` point into world coordinates.

  Returns `{:ok, {x, y, z}}` after validating the frame. Invalid local point
  arguments return `:invalid_point`; invalid plane definitions return
  `:invalid_plane`. This query performs Elixir arithmetic, without a native
  geometry call.
  """
  def to_world(plane, {x, y}) when is_number(x) and is_number(y) do
    with {:ok, frame} <- frame(plane), do: {:ok, point(frame, {x, y})}
  end

  def to_world(_, _), do: {:error, :invalid_point}

  @doc """
  Returns the plane's normalized world normal as a tagged result.

  Validates the whole frame, including its X direction. Invalid frames
  return `{:error, :invalid_plane}`. This is an Elixir calculation and
  does not allocate a native shape.
  """
  @spec normal(t()) :: {:ok, {float(), float(), float()}} | {:error, atom()}
  def normal(plane) do
    with {:ok, frame} <- frame(plane), do: {:ok, frame.n}
  end

  @doc false
  def frame(%__MODULE__{kind: kind, options: opts}) do
    {axis, n, u} =
      case kind do
        :xy -> {:z, {0, 0, 1}, {1, 0, 0}}
        :yz -> {:x, {1, 0, 0}, {0, 1, 0}}
        :xz -> {:y, {0, -1, 0}, {1, 0, 0}}
        :custom -> {nil, {0, 0, 1}, {1, 0, 0}}
        _ -> {nil, nil, nil}
      end

    allowed = if kind == :custom, do: [:origin, :normal, :x_direction], else: [:origin, axis]

    if n != nil and keywords?(opts, allowed) and
         not (Keyword.has_key?(opts, :origin) and Keyword.has_key?(opts, axis)) do
      offset = Keyword.get(opts, axis, 0)

      origin =
        Keyword.get(
          opts,
          :origin,
          case axis do
            :x -> {offset, 0, 0}
            :y -> {0, offset, 0}
            _ -> {0, 0, offset}
          end
        )

      normal = Keyword.get(opts, :normal, n)
      x = Keyword.get(opts, :x_direction, u)

      with true <- vector?(origin) and vector?(normal) and vector?(x),
           {:ok, n} <- unit(normal),
           {:ok, u} <- unit(sub(x, scale(n, dot(x, n)))) do
        {:ok, %{origin: add(origin, {0.0, 0.0, 0.0}), u: u, v: cross(n, u), n: n}}
      else
        _ -> {:error, :invalid_plane}
      end
    else
      {:error, :invalid_plane}
    end
  end

  def frame(_), do: {:error, :invalid_plane}

  @doc false
  def place(shape, frame) do
    # First align +Z with N; then turn local X into U about N.
    axis = cross({0, 0, 1}, frame.n)
    length = norm(axis)

    {axis, angle} =
      cond do
        length > 1.0e-12 -> {scale(axis, 1 / length), :math.atan2(length, elem(frame.n, 2))}
        elem(frame.n, 2) < 0 -> {{1, 0, 0}, :math.pi()}
        true -> {{1, 0, 0}, 0.0}
      end

    x = rotate_vector({1, 0, 0}, axis, angle)
    turn = :math.atan2(dot(cross(x, frame.u), frame.n), dot(x, frame.u))

    with {:ok, shape} <- rotate(shape, axis, angle),
         {:ok, shape} <- rotate(shape, frame.n, turn),
         do: OCEx.translate(shape, frame.origin)
  end

  defp rotate(shape, _, angle) when abs(angle) < 1.0e-12, do: {:ok, shape}

  defp rotate(shape, axis, angle),
    do: OCEx.rotate(shape, {0, 0, 0}, axis, angle * 180 / :math.pi())

  defp rotate_vector(v, axis, angle),
    do:
      add(
        add(scale(v, :math.cos(angle)), scale(cross(axis, v), :math.sin(angle))),
        scale(axis, dot(axis, v) * (1 - :math.cos(angle)))
      )

  defp unit(v) do
    length = norm(v)
    if length > 1.0e-12, do: {:ok, scale(v, 1 / length)}, else: {:error, :invalid_plane}
  end

  @doc false
  def point(frame, {x, y}), do: add(frame.origin, add(scale(frame.u, x), scale(frame.v, y)))
  @doc false
  def add({a, b, c}, {x, y, z}), do: {a + x, b + y, c + z}
  @doc false
  def sub({a, b, c}, {x, y, z}), do: {a - x, b - y, c - z}
  @doc false
  def scale({x, y, z}, k), do: {x * k, y * k, z * k}
  @doc false
  def dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z
  defp cross({a, b, c}, {x, y, z}), do: {b * z - c * y, c * x - a * z, a * y - b * x}
  defp norm(v), do: :math.sqrt(dot(v, v))
  defp vector?({x, y, z}), do: is_number(x) and is_number(y) and is_number(z)
  defp vector?(_), do: false
  @doc false
  def keywords?(opts, allowed),
    do:
      is_list(opts) and Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Enum.all?(Keyword.keys(opts), &(&1 in allowed))
end
