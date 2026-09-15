defmodule Smith.Geometry do
  @moduledoc false
  alias Smith.{Result, Assembly}

  def result(%Result{} = result) do
    with {:ok, brep} <- OCEx.to_brep(result.shape),
         true <- hash(brep) == result.revision do
      {:ok, result}
    else
      false -> {:error, :revision_mismatch}
      error -> error
    end
  end

  def result(%Assembly.Result{} = result) do
    with :ok <- Assembly.validate_result(result), do: snapshot(result.shape)
  end

  def result(%OCEx.Shape{} = shape), do: snapshot(shape)
  def result({:ok, result}), do: result(result)
  def result({:error, _} = error), do: error
  def result(source), do: Smith.evaluate(source)

  def snapshot(shape) do
    with {:ok, true} <- OCEx.valid?(shape), {:ok, brep} <- OCEx.to_brep(shape) do
      {:ok, %Result{shape: shape, revision: hash(brep)}}
    else
      {:ok, false} -> {:error, :invalid_shape}
      error -> error
    end
  end

  def hash(binary), do: Base.encode16(:crypto.hash(:sha256, binary), case: :lower)

  def vector(a, b),
    do: Enum.zip_with(Tuple.to_list(a), Tuple.to_list(b), &(&1 - &2)) |> List.to_tuple()

  def add(a, b),
    do: Enum.zip_with(Tuple.to_list(a), Tuple.to_list(b), &(&1 + &2)) |> List.to_tuple()

  def scale(a, n), do: a |> Tuple.to_list() |> Enum.map(&(&1 * n)) |> List.to_tuple()
  def dot(a, b), do: Enum.zip_with(Tuple.to_list(a), Tuple.to_list(b), &(&1 * &2)) |> Enum.sum()
  def norm(a), do: :math.sqrt(dot(a, a))
  def point?({a, b, c}), do: is_number(a) and is_number(b) and is_number(c)
  def point?(_), do: false

  def options(opts, allowed),
    do:
      is_list(opts) and Keyword.keyword?(opts) and
        length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))) and
        Enum.all?(Keyword.keys(opts), &(&1 in allowed))

  def collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  def json(value) when is_tuple(value), do: value |> Tuple.to_list() |> json()
  def json(value) when is_list(value), do: Enum.map(value, &json/1)
  def json(%_{} = value), do: value |> Map.from_struct() |> json()
  def json(value) when is_map(value), do: Map.new(value, fn {k, v} -> {to_string(k), json(v)} end)
  def json(value), do: value
end
