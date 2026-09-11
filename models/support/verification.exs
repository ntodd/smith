defmodule Models.Verification do
  @moduledoc "Geometry acceptance checks shared by tests and the export command."
  def ok({:ok, value}), do: value
  def check(true, _), do: :ok
  def check(false, message), do: raise(message)
  def near(a, b, tolerance \\ 1.0e-6), do: abs(a - b) <= tolerance
  def shape(recipe), do: Smith.evaluate(recipe) |> ok() |> Map.fetch!(:shape)
  def volume(shape), do: OCEx.volume(shape) |> ok()

  def reference(body, name, opts \\ []) do
    reference_path = Path.expand("../reference/#{name}.step", __DIR__)
    reference = OCEx.read_step(reference_path) |> ok()
    {:ok, true} = OCEx.valid?(body)
    check(length(ok(OCEx.solids(body))) == 1, "Expected one solid")
    {low, high} = ok(OCEx.bounds(body))
    {ref_low, ref_high} = ok(OCEx.bounds(reference))

    bounds_error =
      Enum.zip(
        Tuple.to_list(low) ++ Tuple.to_list(high),
        Tuple.to_list(ref_low) ++ Tuple.to_list(ref_high)
      )
      |> Enum.map(fn {a, b} -> abs(a - b) end)
      |> Enum.max()

    check(bounds_error < 1.0e-4, "Reference bounds differ by #{bounds_error} mm")
    volume_error = abs(volume(body) - volume(reference))

    volume_tolerance =
      max(0.01, volume(reference) * Keyword.get(opts, :relative_volume_tolerance, 0))

    check(volume_error < volume_tolerance, "Reference volume differs by #{volume_error} mm³")

    differences =
      for {a, b} <- [{body, reference}, {reference, body}] do
        difference = OCEx.cut(a, b) |> ok()
        residual = abs(volume(difference))
        check(residual < 0.001, "Reference Boolean residual #{residual} mm³")
        residual
      end

    deviations =
      for {a, b} <- [{body, reference}, {reference, body}] do
        # Use shells: a solid's distance to an interior point is zero.
        boundary = b |> OCEx.shells() |> ok() |> OCEx.compound() |> ok()
        points = OCEx.mesh(a, 0.02) |> ok() |> Map.fetch!(:vertices)
        samples = Enum.take_every(points, max(1, div(length(points), 400)))
        distances = Enum.map(samples, &ok(OCEx.distance_to_point(boundary, &1)))
        maximum = Enum.max(distances)
        check(maximum < 1.0e-4, "Sampled boundary deviation #{maximum} mm")
        %{samples: length(samples), max_distance_mm: maximum}
      end

    %{
      bounds_mm: {low, high},
      volume_mm3: volume(body),
      reference_volume_error_mm3: volume_error,
      bounds_error_mm: bounds_error,
      difference_volumes_mm3: differences,
      boundary_samples: deviations,
      reference_sha256:
        :crypto.hash(:sha256, File.read!(reference_path)) |> Base.encode16(case: :lower)
    }
  end
end
