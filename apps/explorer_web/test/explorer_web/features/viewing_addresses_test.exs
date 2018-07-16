defmodule ExplorerWeb.ViewingAddressesTest do
  use ExplorerWeb.FeatureCase, async: true

  alias Explorer.Chain
  alias Explorer.Chain.{Address, Wei}
  alias Explorer.ExchangeRates.Token
  alias ExplorerWeb.{AddressPage, HomePage}

  setup do
    block = insert(:block)

    {:ok, balance} = Wei.cast(5)
    lincoln = insert(:address, fetched_balance: balance)
    taft = insert(:address)

    from_taft =
      :transaction
      |> insert(from_address: taft, to_address: lincoln)
      |> with_block(block)

    from_lincoln =
      :transaction
      |> insert(from_address: lincoln, to_address: taft)
      |> with_block(block)

    {:ok,
     %{
       addresses: %{lincoln: lincoln, taft: taft},
       block: block,
       transactions: %{from_lincoln: from_lincoln, from_taft: from_taft}
     }}
  end

  test "search for address", %{session: session} do
    address = insert(:address)

    session
    |> HomePage.visit_page()
    |> HomePage.search(to_string(address.hash))
    |> assert_has(AddressPage.detail_hash(address))
  end

  test "viewing address overview information", %{session: session} do
    address = insert(:address, fetched_balance: 500)

    session
    |> AddressPage.visit_page(address)
    |> assert_text(AddressPage.balance(), "0.0000000000000005 POA")
  end

  describe "viewing contract creator" do
    test "see the contract creator and transaction links", %{session: session} do
      address = insert(:address)
      transaction = insert(:transaction, from_address: address)
      contract = insert(:address, contract_code: Explorer.Factory.data("contract_code"))

      internal_transaction =
        insert(
          :internal_transaction_create,
          index: 0,
          transaction: transaction,
          from_address: address,
          created_contract_address: contract
        )

      address_hash = ExplorerWeb.AddressView.trimmed_hash(address.hash)
      transaction_hash = ExplorerWeb.AddressView.trimmed_hash(transaction.hash)

      session
      |> AddressPage.visit_page(internal_transaction.created_contract_address)
      |> assert_text(AddressPage.contract_creator(), "#{address_hash} at #{transaction_hash}")
    end

    test "see the contract creator and transaction links even when the creator is another contract", %{session: session} do
      lincoln = insert(:address)
      contract = insert(:address, contract_code: Explorer.Factory.data("contract_code"))
      transaction = insert(:transaction)
      another_contract = insert(:address, contract_code: Explorer.Factory.data("contract_code"))

      insert(
        :internal_transaction,
        index: 0,
        transaction: transaction,
        from_address: lincoln,
        to_address: contract,
        created_contract_address: contract,
        type: :call
      )

      internal_transaction =
        insert(
          :internal_transaction_create,
          index: 1,
          transaction: transaction,
          from_address: contract,
          created_contract_address: another_contract
        )

      contract_hash = ExplorerWeb.AddressView.trimmed_hash(contract.hash)
      transaction_hash = ExplorerWeb.AddressView.trimmed_hash(transaction.hash)

      session
      |> AddressPage.visit_page(internal_transaction.created_contract_address)
      |> assert_text(AddressPage.contract_creator(), "#{contract_hash} at #{transaction_hash}")
    end
  end

  describe "viewing transactions" do
    test "sees all addresses transactions by default", %{
      addresses: addresses,
      session: session,
      transactions: transactions
    } do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> assert_has(AddressPage.transaction(transactions.from_taft))
      |> assert_has(AddressPage.transaction(transactions.from_lincoln))
    end

    test "can filter to only see transactions from an address", %{
      addresses: addresses,
      session: session,
      transactions: transactions
    } do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.apply_filter("From")
      |> assert_has(AddressPage.transaction(transactions.from_lincoln))
      |> refute_has(AddressPage.transaction(transactions.from_taft))
    end

    test "can filter to only see transactions to an address", %{
      addresses: addresses,
      session: session,
      transactions: transactions
    } do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.apply_filter("To")
      |> refute_has(AddressPage.transaction(transactions.from_lincoln))
      |> assert_has(AddressPage.transaction(transactions.from_taft))
    end

    test "contract creation is shown for to_address on list page", %{
      addresses: addresses,
      block: block,
      session: session
    } do
      lincoln = addresses.lincoln

      from_lincoln =
        :transaction
        |> insert(from_address: lincoln, to_address: nil)
        |> with_block(block)

      internal_transaction =
        insert(
          :internal_transaction_create,
          transaction: from_lincoln,
          from_address: lincoln,
          index: 0
        )

      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> assert_has(AddressPage.contract_creation(internal_transaction))
    end

    test "only addresses not matching the page are links", %{
      addresses: addresses,
      session: session,
      transactions: transactions
    } do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> assert_has(AddressPage.transaction_address_link(transactions.from_lincoln, :to))
    end
  end

  describe "viewing internal transactions" do
    setup %{addresses: addresses, transactions: transactions} do
      address = addresses.lincoln
      transaction = transactions.from_lincoln

      internal_transaction_lincoln_to_address =
        insert(:internal_transaction, transaction: transaction, to_address: address, index: 0)

      insert(:internal_transaction, transaction: transaction, from_address: address, index: 1)
      {:ok, %{internal_transaction_lincoln_to_address: internal_transaction_lincoln_to_address}}
    end

    test "can see internal transactions for an address", %{addresses: addresses, session: session} do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.click_internal_transactions()
      |> assert_has(AddressPage.internal_transactions(count: 2))
    end

    test "can filter to only see internal transactions from an address", %{addresses: addresses, session: session} do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.click_internal_transactions()
      |> AddressPage.apply_filter("From")
      |> assert_has(AddressPage.internal_transactions(count: 1))
    end

    test "can filter to only see internal transactions to an address", %{addresses: addresses, session: session} do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.click_internal_transactions()
      |> AddressPage.apply_filter("To")
      |> assert_has(AddressPage.internal_transactions(count: 1))
    end

    test "only addresses not matching the page are links", %{
      addresses: addresses,
      internal_transaction_lincoln_to_address: internal_transaction,
      session: session
    } do
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> AddressPage.click_internal_transactions()
      |> assert_has(AddressPage.internal_transaction_address_link(internal_transaction, :from))
    end
  end

  test "viewing transaction count", %{addresses: addresses, session: session} do
    insert_list(1000, :transaction, to_address: addresses.lincoln)

    session
    |> AddressPage.visit_page(addresses.lincoln)
    |> assert_text(AddressPage.transaction_count(), "1,002")
  end

  test "viewing new transactions via live update", %{addresses: addresses, session: session} do
    import_data = [
      blocks: [
        params: [
          %{
            difficulty: 340_282_366_920_938_463_463_374_607_431_768_211_454,
            gas_limit: 6_946_336,
            gas_used: 50450,
            hash: "0xf6b4b8c88df3ebd252ec476328334dc026cf66606a84fb769b3d3cbccc8471bd",
            miner_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca",
            nonce: 0,
            number: 565,
            parent_hash: "0xc37bbad7057945d1bf128c1ff009fb1ad632110bf6a000aac025a80f7766b66e",
            size: 719,
            timestamp: Timex.parse!("2017-12-15T21:06:30.000000Z", "{ISO:Extended:Z}"),
            total_difficulty: 12_590_447_576_074_723_148_144_860_474_975_121_280_509
          }
        ]
      ],
      internal_transactions: [
        params: [
          %{
            call_type: "call",
            from_address_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca",
            gas: 4_677_320,
            gas_used: 27770,
            index: 0,
            output: "0x",
            to_address_hash: "0x8bf38d4764929064f2d4d3a56520a76ab3df415b",
            trace_address: [],
            transaction_hash: "0x53bd884872de3e488692881baeec262e7b95234d3965248c39fe992fffd433e5",
            type: "call",
            value: 0
          }
        ]
      ],
      logs: [
        params: [
          %{
            address_hash: "0x8bf38d4764929064f2d4d3a56520a76ab3df415b",
            data: "0x000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef",
            first_topic: "0x600bcf04a13e752d1e3670a5a9f1c21177ca2a93c6f5391d4f1298d098097c22",
            fourth_topic: nil,
            index: 0,
            second_topic: nil,
            third_topic: nil,
            transaction_hash: "0x53bd884872de3e488692881baeec262e7b95234d3965248c39fe992fffd433e5",
            type: "mined"
          }
        ]
      ],
      transactions: [
        on_conflict: :replace_all,
        params: [
          %{
            block_hash: "0xf6b4b8c88df3ebd252ec476328334dc026cf66606a84fb769b3d3cbccc8471bd",
            block_number: 37,
            cumulative_gas_used: 50450,
            from_address_hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca",
            gas: 4_700_000,
            gas_price: 100_000_000_000,
            gas_used: 50450,
            hash: "0x53bd884872de3e488692881baeec262e7b95234d3965248c39fe992fffd433e5",
            index: 0,
            input: "0x10855269000000000000000000000000862d67cb0773ee3f8ce7ea89b328ffea861ab3ef",
            nonce: 4,
            public_key:
              "0xe5d196ad4ceada719d9e592f7166d0c75700f6eab2e3c3de34ba751ea786527cb3f6eb96ad9fdfdb9989ff572df50f1c42ef800af9c5207a38b929aff969b5c9",
            r: 0xA7F8F45CCE375BB7AF8750416E1B03E0473F93C256DA2285D1134FC97A700E01,
            s: 0x1F87A076F13824F4BE8963E3DFFD7300DAE64D5F23C9A062AF0C6EAD347C135F,
            standard_v: 1,
            status: :ok,
            to_address_hash: to_string(addresses.lincoln.hash),
            v: 0xBE,
            value: 0
          }
        ]
      ],
      addresses: [
        params: [
          %{hash: "0x8bf38d4764929064f2d4d3a56520a76ab3df415b"},
          %{hash: "0xe8ddc5c7a2d2f0d7a9798459c0104fdf5e987aca"}
        ]
      ]
    ]

    session =
      session
      |> AddressPage.visit_page(addresses.lincoln)
      |> assert_has(AddressPage.balance())

    Chain.import_blocks(import_data)

    assert_has(session, AddressPage.transaction("0x53bd884872de3e488692881baeec262e7b95234d3965248c39fe992fffd433e5"))
  end

  test "viewing updated overview via live update", %{session: session} do
    address = %Address{hash: hash} = insert(:address, fetched_balance: 500)

    session
    |> AddressPage.visit_page(address)
    |> assert_text(AddressPage.balance(), "0.0000000000000005 POA")

    {:ok, [^hash]} =
      Chain.update_balances([
        %{
          fetched_balance: 100,
          fetched_balance_block_number: 1,
          hash: hash
        }
      ])

    {:ok, updated_address} = Chain.hash_to_address(hash)

    ExplorerWeb.Endpoint.broadcast!("addresses:#{hash}", "overview", %{
      address: updated_address,
      exchange_rate: %Token{},
      transaction_count: 1
    })

    assert_text(session, AddressPage.balance(), "0.0000000000000001 POA")
  end

  test "contract creation is shown for to_address on list page", %{
    addresses: addresses,
    block: block,
    session: session
  } do
    lincoln = addresses.lincoln

    from_lincoln =
      :transaction
      |> insert(from_address: lincoln, to_address: nil)
      |> with_block(block)

    internal_transaction =
      insert(
        :internal_transaction_create,
        transaction: from_lincoln,
        from_address: lincoln,
        index: 0
      )

    session
    |> AddressPage.visit_page(addresses.lincoln)
    |> AddressPage.click_internal_transactions()
    |> assert_has(AddressPage.contract_creation(internal_transaction))
  end
end
