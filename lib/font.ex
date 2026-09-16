defmodule Smith.Font do
  @moduledoc """
  Immutable font bytes with SHA-256 provenance.

  Load an explicit TTF/OTF file once with `load/2`, then reuse the snapshot in
  `Smith.Text.new/2`. Editing or deleting the file cannot change that snapshot.
  No system font discovery, fallback, or silent replacement occurs. Keep your
  font's license with the project; the example Graduate font is bundled in
  `priv/fonts` under the SIL Open Font License.
  """
  @derive {Inspect, only: [:sha256, :face_index, :info]}
  defstruct [:bytes, :sha256, :face_index, :info]

  @opaque t :: %__MODULE__{
            bytes: binary(),
            sha256: String.t(),
            face_index: non_neg_integer(),
            info: map()
          }

  @doc "Loads and validates a font file. Options: `face_index: 0`. Returns file-read or native font errors."
  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, opts \\ []) do
    if is_binary(path) do
      with {:ok, bytes} <- File.read(path), do: from_binary(bytes, opts)
    else
      {:error, :invalid_font}
    end
  end

  @doc "Validates font bytes and captures their content hash. Options: `face_index: 0` for collections."
  @spec from_binary(binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_binary(bytes, opts \\ []) do
    with true <- Smith.Geometry.options(opts, [:face_index]),
         index = Keyword.get(opts, :face_index, 0),
         {:ok, info} <- OCEx.font_info(bytes, index) do
      {:ok,
       %__MODULE__{
         bytes: bytes,
         sha256: Smith.Geometry.hash(bytes),
         face_index: index,
         info: info
       }}
    else
      false -> {:error, :invalid_options}
      error -> error
    end
  end

  @doc false
  def validate(%__MODULE__{bytes: bytes, sha256: hash, face_index: index})
      when is_binary(bytes) and is_integer(index) and index >= 0 do
    if Smith.Geometry.hash(bytes) == hash, do: :ok, else: {:error, :font_revision_mismatch}
  end

  def validate(_), do: {:error, :invalid_font}
end
