defmodule Smith.Assembly.Result do
  @moduledoc """
  An evaluated assembly and its placed members.

    * `:name` — the original assembly recipe name.
    * `:shape` — an unfused compound of installed manufactured parts.
    * `:revision` — SHA-256 of that compound's serialized BREP.
    * `:entries` — immediate members in insertion order, including subassemblies, references
      and uninstalled extras.
    * `:joints` — this level's evaluated attachment frames.
    * `:connections` — this level's normalized connection parameters and limits.

  Each entry contains `:name`, normalized `:key`, `:kind` (`:part`, `:reference`, or `:assembly`), `:options`, its resolved world `:pose`, and its placed `:result`. Prefer
  `Smith.Assembly.fetch/2` for name/path lookup and `Smith.Assembly.members/1`
  for a flat leaf view. Subassembly entries retain another instance of this
  struct; all descendant shapes are in final world coordinates. Treat these fields as read-only.

  The assembly revision excludes references, printable extras, and export
  settings. It does not identify the entire design configuration. Export
  checks every member revision and assigns a separate unique export ID.
  """
  defstruct [:name, :shape, :revision, entries: [], joints: [], connections: []]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          shape: OCEx.Shape.t(),
          revision: String.t(),
          entries: [map()],
          joints: [Smith.Assembly.Joint.t()],
          connections: [map()]
        }
end
