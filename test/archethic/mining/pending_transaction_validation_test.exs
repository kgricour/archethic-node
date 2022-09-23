defmodule Archethic.Mining.PendingTransactionValidationTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.Governance.Pools.MemTable, as: PoolsMemTable

  alias Archethic.Mining.PendingTransactionValidation

  alias Archethic.SharedSecrets.MemTables.NetworkLookup

  alias Archethic.Reward.Scheduler

  alias Archethic.P2P
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA"
    })

    on_exit(fn ->
      Application.put_env(:archethic, Archethic.Mining.PendingTransactionValidation,
        allowed_node_key_origins: []
      )
    end)

    :ok
  end

  describe "validate_pending_transaction/1" do
    test "should return :ok when a node transaction data content contains node endpoint information" do
      {public_key, _} = Crypto.derive_keypair("seed", 0)
      certificate = Crypto.get_key_certificate(public_key)

      tx =
        Transaction.new(
          :node,
          %TransactionData{
            content:
              Node.encode_transaction_content(
                {80, 20, 10, 200},
                3000,
                4000,
                :tcp,
                <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118,
                  139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
                <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                certificate
              )
          },
          "seed",
          0
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type] ->
        {:error, :transaction_not_exists}
      end)

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return an error when a node transaction public key used on non allowed origin" do
      Application.put_env(:archethic, Archethic.Mining.PendingTransactionValidation,
        allowed_node_key_origins: [:tpm]
      )

      {public_key, private_key} = Crypto.derive_keypair("seed", 0)
      {next_public_key, _} = Crypto.derive_keypair("seed", 1)
      certificate = Crypto.get_key_certificate(public_key)

      tx =
        Transaction.new_with_keys(
          :node,
          %TransactionData{
            content:
              Node.encode_transaction_content(
                {80, 20, 10, 200},
                3000,
                4000,
                :tcp,
                <<0, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24, 115, 128, 241, 110, 118,
                  139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64, 157, 137>>,
                <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                certificate
              )
          },
          private_key,
          public_key,
          next_public_key
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type] ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, "Invalid node transaction with invalid key origin"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return an error when a node transaction content is greater than content_max_size " do
      {public_key, private_key} = Crypto.derive_keypair("seed", 0)
      {next_public_key, _} = Crypto.derive_keypair("seed", 1)
      certificate = Crypto.get_key_certificate(public_key)

      content_pretext =
        <<80, 20, 10, 200, 3000::16, 4000::16, 1, 0, 4, 221, 19, 74, 75, 69, 16, 50, 149, 253, 24,
          115, 128, 241, 110, 118, 139, 7, 48, 217, 58, 43, 145, 233, 77, 125, 190, 207, 31, 64,
          157, 137>>

      random_content = :crypto.strong_rand_bytes(4 * 1024 * 1024)

      content =
        content_pretext <> random_content <> <<byte_size(certificate)::16, certificate::binary>>

      tx =
        Transaction.new_with_keys(
          :node,
          %TransactionData{
            content: content
          },
          private_key,
          public_key,
          next_public_key
        )

      MockDB
      |> stub(:get_last_chain_address, fn address ->
        address
      end)
      |> stub(:get_transaction, fn _address, [:address, :type] ->
        {:error, :transaction_not_exists}
      end)

      assert {:error, "Invalid node transaction with content size greaterthan content_max_size"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a node shared secrets transaction data keys contains existing node public keys with first tx" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content:
              <<0, 0, 219, 82, 144, 35, 140, 59, 161, 231, 225, 145, 111, 203, 173, 197, 200, 150,
                213, 145, 87, 209, 98, 25, 28, 148, 198, 77, 174, 48, 16, 117, 253, 15, 0, 0, 105,
                113, 238, 128, 201, 90, 172, 230, 46, 99, 215, 130, 104, 26, 196, 222, 157, 89,
                101, 74, 248, 245, 118, 36, 194, 213, 108, 141, 175, 248, 6, 120>>,
            code: """
            condition inherit: [
              type: node_shared_secrets
            ]
            """,
            ownerships: [
              %Ownership{
                secret: :crypto.strong_rand_bytes(32),
                authorized_keys: %{
                  "node_key1" => "",
                  "node_key2" => ""
                }
              }
            ]
          }
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))
      :persistent_term.put(:node_shared_secrets_gen_addr, Transaction.previous_address(tx))
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:node_shared_secrets_gen_addr, nil)
    end

    test "should return :ok when a origin transaction is made" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        available?: true
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node_key2",
        last_public_key: "node_key2",
        available?: true
      })

      {public_key, _} = Crypto.derive_keypair("random", 0)
      certificate = Crypto.get_key_certificate(public_key)
      certificate_size = byte_size(certificate)

      tx =
        Transaction.new(
          :origin,
          %TransactionData{
            code: """
            condition inherit: [
              type: origin,
              content: true
            ]
            """,
            content: <<public_key::binary, certificate_size::16, certificate::binary>>
          }
        )

      :persistent_term.put(:origin_gen_addr, [Transaction.previous_address(tx)])
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:origin_gen_addr, nil)
    end

    test "should return :ok when a code approval transaction contains a proposal target and the sender is member of the technical council and not previously signed" do
      tx =
        Transaction.new(
          :code_approval,
          %TransactionData{
            recipients: ["@CodeProposal1"]
          },
          "approval_seed",
          0
        )

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        first_public_key: "node1",
        last_public_key: "node1",
        geo_patch: "AAA",
        network_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      assert :ok = PoolsMemTable.put_pool_member(:technical_council, tx.previous_public_key)

      MockDB
      |> expect(:get_transaction, fn _, _ ->
        {:ok,
         %Transaction{
           data: %TransactionData{
             content: """
             Description: My Super Description
             Changes:
             diff --git a/mix.exs b/mix.exs
             index d9d9a06..5e34b89 100644
             --- a/mix.exs
             +++ b/mix.exs
             @@ -4,7 +4,7 @@ defmodule Archethic.MixProject do
               def project do
                 [
                   app: :archethic,
             -      version: \"0.7.1\",
             +      version: \"0.7.2\",
                   build_path: \"_build\",
                   config_path: \"config/config.exs\",
                   deps_path: \"deps\",
             @@ -53,7 +53,7 @@ defmodule Archethic.MixProject do
                   {:git_hooks, \"~> 0.4.0\", only: [:test, :dev], runtime: false},
                   {:mox, \"~> 0.5.2\", only: [:test]},
                   {:stream_data, \"~> 0.4.3\", only: [:test]},
             -      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test], runtime: false},
             +      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test]},
                   {:logger_file_backend, \"~> 0.0.11\", only: [:dev]}
                 ]
               end
             """
           }
         }}
      end)

      MockClient
      |> expect(:send_message, fn _, %GetFirstPublicKey{}, _ ->
        {:ok, %FirstPublicKey{public_key: tx.previous_public_key}}
      end)

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a transaction contains a valid smart contract code" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            code: """
            condition inherit: [
              content: "hello"
            ]

            condition transaction: [
              content: ""
            ]

            actions triggered_by: transaction do
              set_content "hello"
            end
            """,
            ownerships: [
              Ownership.new(tx_seed, :crypto.strong_rand_bytes(32), [
                Crypto.storage_nonce_public_key()
              ])
            ]
          },
          tx_seed,
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a transaction contains valid fields for token creation" do
      tx_seed = :crypto.strong_rand_bytes(32)

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "non-fungible",
                symbol: "MTK",
                properties: %{
                  global: "property"
                },
                collection: [
                  %{image: "link", value: "link"},
                  %{image: "link", value: "link"},
                  %{image: "link", value: "link"}
                ]
              })
          },
          tx_seed,
          0
        )

      assert :ok = PendingTransactionValidation.validate(tx)
    end

    test "should return :ok when a mint reward transaction passes all tests" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(address)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      :persistent_term.put(:reward_gen_addr, Transaction.previous_address(tx))
      assert :ok = PendingTransactionValidation.validate(tx)
      :persistent_term.put(:reward_gen_addr, nil)
    end

    test "should return :error when a mint reward transaction has != burned_fees" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(address)

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 200_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)
      |> stub(:get_last_chain_address, fn _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      assert {:error, "The supply do not match burned fees from last summary"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return :error when there is already a mint rewards transaction since last schedule" do
      tx_seed = :crypto.strong_rand_bytes(32)
      {pub, _} = Crypto.derive_keypair(tx_seed, 1)
      address = Crypto.derive_address(pub)

      NetworkLookup.set_network_pool_address(:crypto.strong_rand_bytes(32))

      {:ok, pid} = Scheduler.start_link(interval: "0 * * * * *")

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle, %{interval: "0 * * * * *"}} = :sys.get_state(pid)

      MockDB
      |> stub(:get_latest_burned_fees, fn -> 300_000_000 end)
      |> stub(:get_last_chain_address, fn _, _ -> {address, DateTime.utc_now()} end)

      tx =
        Transaction.new(
          :mint_rewards,
          %TransactionData{
            content:
              Jason.encode!(%{
                supply: 300_000_000,
                name: "MyToken",
                type: "fungible",
                symbol: "MTK"
              })
          },
          tx_seed,
          0
        )

      assert {:error, "There is already a mint rewards transaction since last schedule"} =
               PendingTransactionValidation.validate(tx)
    end

    test "should return error when there is already a oracle transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      tx = Transaction.new(:oracle, %TransactionData{}, "seed", 0)

      assert {:error, "Invalid oracle trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:10:03Z])
    end

    test "should return error when there is already a node shared secrets transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)

      tx =
        Transaction.new(
          :node_shared_secrets,
          %TransactionData{
            content: :crypto.strong_rand_bytes(32),
            ownerships: [
              %Ownership{
                secret: :crypto.strong_rand_bytes(32),
                authorized_keys: %{"node_key" => :crypto.strong_rand_bytes(32)}
              }
            ]
          },
          "seed",
          0
        )

      assert {:error, "Invalid node shared secrets trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:00:03Z])
    end

    test "should return error when there is already a node rewards transaction since the last schedule" do
      MockDB
      |> expect(:get_last_chain_address, fn _, _ ->
        {"OtherAddress", DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn _, _ ->
        {:ok, %Transaction{type: :node_rewards}}
      end)

      tx =
        Transaction.new(
          :node_rewards,
          %TransactionData{},
          "seed",
          0
        )

      assert {:error, "Invalid node rewards trigger time"} =
               PendingTransactionValidation.validate(tx, ~U[2022-01-01 00:00:03Z])
    end
  end
end
