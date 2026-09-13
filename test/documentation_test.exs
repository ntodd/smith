defmodule Smith.DocumentationTest do
  use ExUnit.Case, async: true

  doctest Smith
  doctest Smith.Path
  doctest Smith.Selector
  doctest Smith.Plane
  doctest Smith.Sketch
  doctest Smith.Assembly
  doctest Smith.Export
  doctest Smith.Drawing
  doctest Smith.Mesh
  doctest Smith.Kino
end
