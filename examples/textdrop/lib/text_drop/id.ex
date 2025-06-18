defmodule TextDrop.Id do
  @doc """
  Generates a random hexadecimal identifier.

  Uses cryptographically strong random bytes to generate a 32-character
  lowercase hexadecimal string. Each call produces a unique identifier
  with very high probability.
  """
  @spec generate :: String.t()
  def generate do
    :crypto.strong_rand_bytes(16)
    |> :binary.encode_hex()
    |> String.downcase()
  end
end
