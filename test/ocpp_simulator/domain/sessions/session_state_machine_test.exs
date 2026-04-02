defmodule OcppSimulator.Domain.Sessions.SessionStateMachineTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Domain.Sessions.MessageIdRegistry
  alias OcppSimulator.Domain.Sessions.SessionStateMachine

  test "transition/3 moves state and emits correlation metadata" do
    {:ok, session} = SessionStateMachine.new_session("session-1")

    correlation = %{run_id: "run-1", message_id: "msg-1", charge_point_id: "CP-001"}

    assert {:ok, updated_session, event} =
             SessionStateMachine.transition(session, :connected, correlation)

    assert updated_session.state == :connected
    assert event.from_state == :idle
    assert event.to_state == :connected
    assert event.correlation == correlation
  end

  test "transition/3 rejects invalid transitions" do
    {:ok, session} = SessionStateMachine.new_session("session-1")

    assert {:error, {:invalid_transition, :idle, :active}} =
             SessionStateMachine.transition(session, :active, %{run_id: "run-1"})
  end

  test "transition/3 allows reconnecting state from idle for failed initial connect lifecycle" do
    {:ok, session} = SessionStateMachine.new_session("session-1")

    assert {:ok, updated_session, _event} =
             SessionStateMachine.transition(session, :reconnecting, %{run_id: "run-1"})

    assert updated_session.state == :reconnecting
  end

  test "transition/3 returns error instead of raising for unknown current state" do
    corrupted_session = %SessionStateMachine.Session{
      id: "session-unknown",
      state: :unknown,
      last_transition: nil
    }

    assert {:error, {:invalid_state, :unknown}} =
             SessionStateMachine.transition(corrupted_session, :connected, %{run_id: "run-1"})
  end

  test "message id registry enforces uniqueness per session" do
    {:ok, registry} = MessageIdRegistry.new("session-1")
    assert {:ok, registry} = MessageIdRegistry.register(registry, "msg-1")
    assert MessageIdRegistry.registered?(registry, "msg-1")

    assert {:error, {:duplicate_message_id, "msg-1"}} =
             MessageIdRegistry.register(registry, "msg-1")
  end
end
