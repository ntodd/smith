defmodule Smith.Assembly.Frame do
  @moduledoc """
  Rigid-frame arithmetic used by assembly placement and joint evaluation.

  This implementation module uses the same right-handed frame maps as
  `Smith.Plane`: an origin and unit `u`, `v`, and `n` axes. Geometry stays in
  OCEx; these functions only compose coordinates and produce rotation/translation
  options. Use `Smith.Assembly` and `Smith.Plane` to define a public model.
  """
  alias Smith.Plane
  @type vector :: {number(), number(), number()}
  @type t :: %{origin: vector(), u: vector(), v: vector(), n: vector()}

  @doc "Returns the identity frame at world zero."
  @spec identity() :: t()
  def identity, do: %{origin: {0, 0, 0}, u: {1, 0, 0}, v: {0, 1, 0}, n: {0, 0, 1}}

  @doc "Builds a frame from validated assembly rotation and position options."
  @spec placement(keyword()) :: t()
  def placement(opts) do
    frame = identity()

    case opts[:rotation] do
      nil ->
        %{frame | origin: Keyword.get(opts, :position, {0, 0, 0})}

      {axis, degrees} ->
        %{
          frame
          | origin: Keyword.get(opts, :position, {0, 0, 0}),
            u: rotate(frame.u, axis, degrees),
            v: rotate(frame.v, axis, degrees),
            n: rotate(frame.n, axis, degrees)
        }
    end
  end

  @doc "Composes frames, applying the second frame before the first."
  @spec compose(t(), t()) :: t()
  def compose(a, b) do
    %{
      origin: Plane.add(a.origin, vector(a, b.origin)),
      u: vector(a, b.u),
      v: vector(a, b.v),
      n: vector(a, b.n)
    }
  end

  @doc "Returns the inverse of a normalized rigid frame."
  @spec inverse(t()) :: t()
  def inverse(f) do
    {ux, uy, uz} = f.u
    {vx, vy, vz} = f.v
    {nx, ny, nz} = f.n
    inverse = %{origin: {0, 0, 0}, u: {ux, vx, nx}, v: {uy, vy, ny}, n: {uz, vz, nz}}
    %{inverse | origin: vector(inverse, Plane.scale(f.origin, -1))}
  end

  @doc "Converts a rigid frame to OCEx-compatible rotation-then-translation options."
  @spec options(t()) :: keyword()
  def options(f) do
    {a, d, g} = f.u
    {b, e, h} = f.v
    {c, i, j} = f.n

    {w, x, y, z} =
      cond do
        a + e + j > 0 ->
          s = 2 * :math.sqrt(1 + a + e + j)
          {s / 4, (h - i) / s, (c - g) / s, (d - b) / s}

        a > e and a > j ->
          s = 2 * :math.sqrt(1 + a - e - j)
          {(h - i) / s, s / 4, (b + d) / s, (c + g) / s}

        e > j ->
          s = 2 * :math.sqrt(1 + e - a - j)
          {(c - g) / s, (b + d) / s, s / 4, (i + h) / s}

        true ->
          s = 2 * :math.sqrt(1 + j - a - e)
          {(d - b) / s, (c + g) / s, (i + h) / s, s / 4}
      end

    length = :math.sqrt(x * x + y * y + z * z)

    if length < 1.0e-14 do
      [position: f.origin]
    else
      angle = 2 * :math.atan2(length, w) * 180 / :math.pi()
      [rotation: {{x / length, y / length, z / length}, angle}, position: f.origin]
    end
  end

  defp vector(f, {x, y, z}),
    do: Plane.add(Plane.add(Plane.scale(f.u, x), Plane.scale(f.v, y)), Plane.scale(f.n, z))

  defp rotate(v, axis, degrees) do
    unit = Plane.scale(axis, 1 / :math.sqrt(Plane.dot(axis, axis)))
    angle = degrees * :math.pi() / 180

    Plane.add(
      Plane.add(Plane.scale(v, :math.cos(angle)), Plane.scale(cross(unit, v), :math.sin(angle))),
      Plane.scale(unit, Plane.dot(unit, v) * (1 - :math.cos(angle)))
    )
  end

  defp cross({a, b, c}, {x, y, z}), do: {b * z - c * y, c * x - a * z, a * y - b * x}
end
