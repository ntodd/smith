defmodule Smith.SVG.XML do
  @moduledoc false
  # A deliberately bounded XML reader. Names stay binaries, and no DTD, external
  # entity, processing instruction or network resolver is ever invoked.
  def parse(bytes) when is_binary(bytes) and byte_size(bytes) <= 4_194_304 do
    try do
      unless String.valid?(bytes), do: fail(:invalid_utf8)
      bytes = String.trim_leading(bytes, "\uFEFF")
      bytes = Regex.replace(~r/\A\s*<\?xml\s[^?]*\?>/, bytes, "")
      {nodes, rest, count} = nodes(bytes, nil, 0, 0, [])
      if String.trim(rest) != "" or count > 10_000, do: fail(:invalid_xml)

      case nodes do
        [%{name: "svg"} = root] -> {:ok, root}
        _ -> fail(:invalid_svg_root)
      end
    catch
      {:svg_xml, reason} -> {:error, reason}
    end
  end

  def parse(_), do: {:error, :svg_size_limit}
  defp fail(reason), do: throw({:svg_xml, reason})

  defp nodes(_, _, depth, count, _) when depth > 64 or count > 10_000,
    do: fail(:svg_complexity_limit)

  defp nodes("", nil, _, count, acc), do: {Enum.reverse(acc), "", count}
  defp nodes("", _, _, _, _), do: fail(:unclosed_element)

  defp nodes("<!--" <> rest, parent, depth, count, acc) do
    case :binary.split(rest, "-->") do
      [_, tail] -> nodes(tail, parent, depth, count, acc)
      _ -> fail(:invalid_comment)
    end
  end

  defp nodes("</" <> rest, parent, _, count, acc) do
    case Regex.run(~r/\A([\w:.-]+)\s*>/u, rest) do
      [all, ^parent] ->
        {Enum.reverse(acc), binary_part(rest, byte_size(all), byte_size(rest) - byte_size(all)),
         count}

      _ ->
        fail(:mismatched_element)
    end
  end

  defp nodes("<!" <> _, _, _, _, _), do: fail(:unsupported_xml_declaration)
  defp nodes("<?" <> _, _, _, _, _), do: fail(:unsupported_processing_instruction)

  defp nodes("<" <> rest, parent, depth, count, acc) do
    case Regex.run(~r/\A([A-Za-z_][\w:.-]*)((?:[^<>"']|"[^"]*"|'[^']*')*)>/u, rest) do
      [all, name, raw] ->
        tail = binary_part(rest, byte_size(all), byte_size(rest) - byte_size(all))
        closed = String.ends_with?(String.trim_trailing(raw), "/")
        raw = if closed, do: raw |> String.trim_trailing() |> String.trim_trailing("/"), else: raw
        attrs = attributes(raw, %{})

        {children, tail, count} =
          if closed, do: {[], tail, count + 1}, else: nodes(tail, name, depth + 1, count + 1, [])

        node = %{name: name, attrs: attrs, children: children}
        nodes(tail, parent, depth, count, [node | acc])

      _ ->
        fail(:invalid_xml)
    end
  end

  defp nodes(bytes, parent, depth, count, acc) do
    [content | _] = :binary.split(bytes, "<")
    if content == "", do: fail(:invalid_xml)
    text = decode(content)

    unless String.trim(text) == "" or parent != nil,
      do: fail(:unexpected_text)

    nodes(
      binary_part(bytes, byte_size(content), byte_size(bytes) - byte_size(content)),
      parent,
      depth,
      count,
      acc
    )
  end

  defp attributes(raw, acc) do
    if String.trim(raw) == "" do
      acc
    else
      case Regex.run(~r/\A\s+([A-Za-z_][\w:.-]*)\s*=\s*("[^"]*"|'[^']*')/u, raw) do
        [all, key, quoted] ->
          if Map.has_key?(acc, key), do: fail(:duplicate_attribute)
          value = binary_part(quoted, 1, byte_size(quoted) - 2) |> decode()

          attributes(
            binary_part(raw, byte_size(all), byte_size(raw) - byte_size(all)),
            Map.put(acc, key, value)
          )

        _ ->
          fail(:invalid_attribute)
      end
    end
  end

  defp decode(text) do
    Regex.replace(~r/&([^;]*);|&/, text, fn
      _, "lt" -> "<"
      _, "gt" -> ">"
      _, "amp" -> "&"
      _, "quot" -> "\""
      _, "apos" -> "'"
      _, "#x" <> n -> codepoint(n, 16)
      _, "#" <> n -> codepoint(n, 10)
      _, _ -> fail(:unknown_entity)
    end)
  end

  defp codepoint(n, base) do
    case Integer.parse(n, base) do
      {i, ""} when i in 0x20..0xD7FF or i in 0xE000..0x10FFFF or i in [9, 10, 13] -> <<i::utf8>>
      _ -> fail(:invalid_entity)
    end
  end
end
