defmodule ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer do
  @moduledoc """
  Represents a UCO transfer
  """
  defstruct [:to, :amount, conditions: []]

  alias ArchEthic.Crypto

  @typedoc """
  Transfer is composed from:
  - to: receiver address of the UCO
  - amount: specify the number of UCO to transfer to the recipients (in the smallest unit 10^-8)
  - conditions: specify to which address the UCO can be used
  """
  @type t :: %__MODULE__{
          to: binary(),
          amount: non_neg_integer(),
          conditions: list(binary())
        }

  @doc """
  Serialize UCO transfer into binary format

  ## Examples

      iex> %Transfer{
      ...>   to: <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...>    85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
      ...>   amount: 1_050_000_000
      ...> }
      ...> |> Transfer.serialize()
      <<
        # UCO recipient
        0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
        85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
        # UCO amount
        0, 0, 0, 0, 62, 149, 186, 128
      >>
  """
  def serialize(%__MODULE__{to: to, amount: amount}) do
    <<to::binary, amount::64>>
  end

  @doc """
  Deserialize an encoded UCO transfer

  ## Examples

      iex> <<
      ...> 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...> 85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
      ...> 0, 0, 0, 0, 62, 149, 186, 128>>
      ...> |> Transfer.deserialize()
      {
        %Transfer{
          to: <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
            85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
          amount: 1_050_000_000
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::64, rest::bitstring>> = rest

    {
      %__MODULE__{to: <<hash_id::8, address::binary>>, amount: amount},
      rest
    }
  end

  @spec from_map(map()) :: t()
  def from_map(transfer = %{}) do
    %__MODULE__{
      to: Map.get(transfer, :to),
      amount: Map.get(transfer, :amount)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end
end
