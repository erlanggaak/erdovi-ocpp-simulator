defmodule OcppSimulator.Domain.Transactions.TransactionStateMachineTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Transactions.TransactionStateMachine

  test "transition/3 allows valid transaction lifecycle changes" do
    {:ok, tx} = TransactionStateMachine.new_transaction("tx-1")

    assert {:ok, tx, _event} =
             TransactionStateMachine.transition(tx, :authorized, %{
               run_id: "run-1",
               message_id: "msg-1"
             })

    assert {:ok, tx, _event} =
             TransactionStateMachine.transition(tx, :started, %{
               run_id: "run-1",
               message_id: "msg-2"
             })

    assert {:ok, tx, _event} =
             TransactionStateMachine.transition(tx, :metering, %{
               run_id: "run-1",
               message_id: "msg-3"
             })

    assert {:ok, tx, event} =
             TransactionStateMachine.transition(tx, :stopped, %{
               run_id: "run-1",
               message_id: "msg-4"
             })

    assert tx.state == :stopped
    assert event.from_state == :metering
    assert event.to_state == :stopped
  end

  test "transition/3 rejects invalid transaction transitions" do
    {:ok, tx} = TransactionStateMachine.new_transaction("tx-2")

    assert {:error, {:invalid_transition, :none, :started}} =
             TransactionStateMachine.transition(tx, :started, %{run_id: "run-1"})
  end

  test "transition/3 returns error instead of raising for unknown current state" do
    corrupted_tx = %TransactionStateMachine.Transaction{
      id: "tx-unknown",
      state: :unknown,
      last_transition: nil
    }

    assert {:error, {:invalid_state, :unknown}} =
             TransactionStateMachine.transition(corrupted_tx, :started, %{run_id: "run-1"})
  end
end
