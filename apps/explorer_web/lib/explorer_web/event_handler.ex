defmodule ExplorerWeb.EventHandler do
  use GenServer
  alias Explorer.Chain
  alias ExplorerWeb.Endpoint

  # Client

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server

  def init([]) do
    Chain.subscribe_to_events(:blocks)
    Chain.subscribe_to_events(:transactions)
    {:ok, []}
  end

  def handle_info({:chain_event, :blocks, blocks}, state) do
    max_numbered_block = Enum.max_by(blocks, & &1.number).number
    Endpoint.broadcast("transactions:confirmations", "update", %{block_number: max_numbered_block})
    {:noreply, state}
  end

  def handle_info({:chain_event, :transactions, transactions}, state) do
    transactions
    |> Enum.each(&broadcast_transaction/1)
    {:noreply, state}
  end

  def handle_info(_event, state) do
    {:noreply, state}
  end

  defp broadcast_transaction(transaction_hash) do
    {:ok, transaction} = Chain.hash_to_transaction(
      transaction_hash,
      necessity_by_association: %{
        block: :required,
        from_address: :optional,
        to_address: :optional
      }
    )
    Endpoint.broadcast("addresses:#{transaction.from_address_hash}", "transaction", %{
      address: transaction.from_address,
      transaction: transaction
    })
    if (transaction.from_address && transaction.to_address != transaction.from_address) do
      Endpoint.broadcast("addresses:#{transaction.to_address_hash}", "transaction", %{
        address: transaction.to_address,
        transaction: transaction
      })
    end
  end
end
