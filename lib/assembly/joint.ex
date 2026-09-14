defmodule Smith.Assembly.Joint do
  @moduledoc """
  An evaluated attachment frame and the member to which it belongs.

  Define frames with `Smith.Assembly.joint/3`, connect them with
  `Smith.Assembly.connect/3`, and inspect them with `Smith.Assembly.fetch_joint/2`.
  `:name` is normalized like an assembly member name. `:member` is a list of
  normalized names relative to the result used for lookup. `:frame` contains
  the final world `:origin` and unit local axes `:u`, `:v`, and `:n`.

  These are immutable evaluated values, not live constraints. Reevaluate the
  recipe after changing a motion parameter. Connections calculate rigid poses;
  they do not detect collisions or solve closed mechanical linkages.
  """
  alias Smith.{Assembly, Error, Plane}
  alias Smith.Assembly.{Frame, Result}
  defstruct [:name, :member, :frame]
  @type t :: %__MODULE__{name: String.t(), member: [String.t()], frame: Frame.t()}

  @doc false
  def fetch(%Result{} = result, path) do
    case parts(path) do
      [name] ->
        case Enum.find(result.joints, &(&1.name == name)) do
          nil -> {:error, :unknown_joint}
          joint -> {:ok, joint}
        end

      [head | tail] ->
        with %{kind: :assembly, result: child} <- Enum.find(result.entries, &(&1.key == head)),
             {:ok, joint} <- fetch(child, tail) do
          {:ok, %{joint | member: [head | joint.member]}}
        else
          _ -> {:error, :unknown_joint}
        end

      _ ->
        {:error, :unknown_joint}
    end
  end

  @doc false
  def resolve(entries, definitions, connections, move) do
    with {:ok, definitions} <- definitions(entries, definitions),
         {:ok, graph, reports} <- connections(entries, definitions, connections),
         {:ok, entries} <- solve_all(entries, definitions, graph, move) do
      {:ok, entries, Enum.map(definitions, &world(entries, &1)), reports}
    end
  end

  @doc false
  def placed(joints, frame), do: Enum.map(joints, &%{&1 | frame: Frame.compose(frame, &1.frame)})
  @doc false
  def records(joints), do: Enum.map(joints, &Map.from_struct/1)

  defp definitions(entries, definitions) do
    Enum.reduce_while(definitions, {:ok, []}, fn definition, {:ok, result} ->
      name = Assembly.key(definition.name)
      opts = definition.options

      cond do
        not Assembly.valid_name?(definition.name) ->
          {:halt, failure(:joint, definition.name, :invalid_joint_name)}

        Enum.any?(result, &(&1.name == name)) ->
          {:halt, failure(:joint, name, :duplicate_joint)}

        not keywords?(opts, [:on, :at]) or not Keyword.has_key?(opts, :on) ->
          {:halt, failure(:joint, name, :invalid_options)}

        true ->
          member = Assembly.key(opts[:on])

          case Enum.find(entries, &(&1.key == member)) do
            nil ->
              {:halt, failure(:joint, name, :unknown_joint_member)}

            _ ->
              case plane(Keyword.get(opts, :at, :xy)) do
                {:ok, frame} ->
                  {:cont,
                   {:ok, result ++ [%__MODULE__{name: name, member: [member], frame: frame}]}}

                {:error, reason} ->
                  {:halt, failure(:joint, member, reason)}
              end
          end
      end
    end)
  end

  defp connections(entries, definitions, connections) do
    Enum.reduce_while(connections, {:ok, %{}, []}, fn connection, {:ok, graph, reports} ->
      from = Assembly.path_key(connection.from)
      opts = connection.options

      with {:ok, motion, values, kind, limits} <- motion(opts),
           {:ok, source} <- endpoint(entries, definitions, from),
           {:ok, target} <- endpoint(entries, definitions, opts[:to]),
           :ok <- link(source, target, graph) do
        report = %{
          from: from,
          to: Assembly.path_key(opts[:to]),
          kind: kind,
          values: values,
          limits: limits
        }

        edge = %{from: from, to: report.to, target: hd(target.member), motion: motion}
        {:cont, {:ok, Map.put(graph, hd(source.member), edge), reports ++ [report]}}
      else
        {:error, reason} ->
          {:halt, failure(:connect, from, reason)}
      end
    end)
  end

  defp link(source, target, graph) do
    cond do
      hd(source.member) == hd(target.member) -> {:error, :self_connection}
      Map.has_key?(graph, hd(source.member)) -> {:error, :multiple_connections}
      true -> :ok
    end
  end

  defp solve_all(entries, definitions, graph, move) do
    Enum.reduce_while(entries, {:ok, entries, MapSet.new()}, fn entry, {:ok, placed, done} ->
      case solve(entry.key, placed, definitions, graph, move, done, MapSet.new()) do
        {:ok, placed, done} -> {:cont, {:ok, placed, done}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries, _} -> {:ok, entries}
      error -> error
    end
  end

  defp solve(owner, entries, definitions, graph, move, done, visiting) do
    cond do
      MapSet.member?(done, owner) ->
        {:ok, entries, done}

      MapSet.member?(visiting, owner) ->
        failure(:connect, owner, :connection_cycle)

      not Map.has_key?(graph, owner) ->
        {:ok, entries, MapSet.put(done, owner)}

      true ->
        edge = graph[owner]

        with {:ok, entries, done} <-
               solve(
                 edge.target,
                 entries,
                 definitions,
                 graph,
                 move,
                 done,
                 MapSet.put(visiting, owner)
               ),
             {:ok, source} <- endpoint(entries, definitions, edge.from),
             {:ok, target} <- endpoint(entries, definitions, edge.to) do
          desired = Frame.compose(target.frame, edge.motion)
          delta = Frame.compose(desired, Frame.inverse(source.frame))
          index = Enum.find_index(entries, &(&1.key == owner))

          case move.(Enum.at(entries, index), delta) do
            {:ok, entry} -> {:ok, List.replace_at(entries, index, entry), MapSet.put(done, owner)}
            {:error, reason} -> failure(:connect, owner, reason)
          end
        end
    end
  end

  defp endpoint(entries, definitions, path) do
    case parts(path) do
      [name] ->
        case Enum.find(definitions, &(&1.name == name)) do
          nil -> {:error, :unknown_joint}
          definition -> {:ok, world(entries, definition)}
        end

      [_ | _] ->
        fetch(%Result{entries: entries}, path)

      _ ->
        {:error, :unknown_joint}
    end
  end

  defp world(entries, definition) do
    entry = Enum.find(entries, &(&1.key == hd(definition.member)))
    %{definition | frame: Frame.compose(entry.pose, definition.frame)}
  end

  defp motion(opts) do
    if is_list(opts) and Keyword.keyword?(opts) do
      kind = Keyword.get(opts, :kind, :rigid)

      fields =
        case kind do
          :rigid -> []
          :revolute -> [:angle]
          :linear -> [:offset]
          :cylindrical -> [:angle, :offset]
          :ball -> [:angles]
          _ -> nil
        end

      limits = Keyword.get(opts, :limits, [])

      valid =
        fields != nil and keywords?(opts, [:to, :kind, :limits] ++ fields) and
          Keyword.has_key?(opts, :to)

      if valid do
        values =
          Map.new(fields, &{&1, Keyword.get(opts, &1, if(&1 == :angles, do: {0, 0, 0}, else: 0))})

        with {:ok, coordinates} <- coordinates(kind, values),
             :ok <- limits(coordinates, limits) do
          {:ok, motion_frame(kind, values), values, kind, Map.new(limits)}
        end
      else
        {:error, :invalid_options}
      end
    else
      {:error, :invalid_options}
    end
  end

  defp coordinates(:ball, %{angles: {x, y, z}})
       when is_number(x) and is_number(y) and is_number(z) do
    {:ok, %{x: x, y: y, z: z}}
  end

  defp coordinates(:ball, _), do: {:error, :invalid_options}

  defp coordinates(_, values) do
    if Enum.all?(values, fn {_, value} -> is_number(value) end),
      do: {:ok, values},
      else: {:error, :invalid_options}
  end

  defp limits(values, limits) do
    cond do
      not keywords?(limits, Map.keys(values)) ->
        {:error, :invalid_options}

      not Enum.all?(limits, fn {_, range} -> valid_range?(range) end) ->
        {:error, :invalid_options}

      Enum.any?(limits, fn {key, {low, high}} -> values[key] < low or values[key] > high end) ->
        {:error, :joint_limit}

      true ->
        :ok
    end
  end

  defp valid_range?({low, high}), do: is_number(low) and is_number(high) and low <= high
  defp valid_range?(_), do: false

  defp motion_frame(:ball, %{angles: {x, y, z}}) do
    Frame.compose(
      Frame.placement(rotation: {{0, 0, 1}, z}),
      Frame.compose(
        Frame.placement(rotation: {{0, 1, 0}, y}),
        Frame.placement(rotation: {{1, 0, 0}, x})
      )
    )
  end

  defp motion_frame(_, values),
    do:
      Frame.placement(
        rotation: {{0, 0, 1}, Map.get(values, :angle, 0)},
        position: {0, 0, Map.get(values, :offset, 0)}
      )

  defp parts(path) do
    case Assembly.path_key(path) do
      nil -> []
      key -> String.split(key, "/")
    end
  end

  defp plane(:xy), do: Plane.frame(Plane.xy())
  defp plane(:xz), do: Plane.frame(Plane.xz())
  defp plane(:yz), do: Plane.frame(Plane.yz())
  defp plane(plane), do: Plane.frame(plane)
  defp keywords?(opts, allowed), do: Plane.keywords?(opts, allowed)

  defp failure(operation, part, reason),
    do: {:error, %Error{operation: operation, part: part, reason: reason}}
end
