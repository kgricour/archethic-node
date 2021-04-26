defmodule UnirisWeb.ExplorerController do
  @moduledoc false

  use UnirisWeb, :controller

  alias Uniris.Crypto
  alias Uniris.TransactionChain.Transaction

  def index(conn, _params) do
    render(conn, "index.html", layout: {UnirisWeb.LayoutView, "index.html"})
  end

  def search(conn, _params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_hash?(address),
         {:ok, tx} <- Uniris.search_transaction(address) do
      previous_address = Transaction.previous_address(tx)

      render(conn, "transaction_details.html", transaction: tx, previous_address: previous_address)
    else
      _reason ->
        render(conn, "404.html")
    end
  end

  def chain(conn, _params = %{"address" => address, "last" => "on"}) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_hash?(addr),
         {:ok, %Transaction{address: last_address}} <- Uniris.get_last_transaction(addr) do
      chain = Uniris.get_transaction_chain(last_address)
      %{uco: uco_balance} = Uniris.get_balance(addr)

      render(conn, "chain.html",
        transaction_chain: chain,
        chain_size: Enum.count(chain),
        address: addr,
        uco_balance: uco_balance,
        last_checked?: true
      )
    else
      :error ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: "",
          last_checked?: true,
          error: :invalid_address
        )

      false ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: "",
          last_checked?: true,
          error: :invalid_address
        )

      _ ->
        render(conn, "chain.html",
          transaction_chain: [],
          chain_size: 0,
          address: Base.decode16!(address, case: :mixed),
          last_checked?: true
        )
    end
  end

  def chain(conn, _params = %{"address" => address}) do
    with {:ok, addr} <- Base.decode16(address, case: :mixed),
         true <- Crypto.valid_hash?(addr) do
      chain = Uniris.get_transaction_chain(addr)
      %{uco: uco_balance} = Uniris.get_balance(addr)

      render(conn, "chain.html",
        transaction_chain: chain,
        address: addr,
        chain_size: Enum.count(chain),
        uco_balance: uco_balance,
        last_checked?: false
      )
    else
      :error ->
        render(conn, "chain.html",
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          last_checked?: false,
          error: :invalid_address
        )

      false ->
        render(conn, "chain.html",
          transaction_chain: [],
          address: "",
          chain_size: 0,
          uco_balance: 0,
          last_checked?: false,
          error: :invalid_address
        )
    end
  end

  def chain(conn, _params) do
    render(conn, "chain.html",
      transaction_chain: [],
      address: "",
      chain_size: 0,
      last_checked?: false
    )
  end
end
