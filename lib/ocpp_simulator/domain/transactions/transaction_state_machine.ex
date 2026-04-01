defmodule OcppSimulator.Domain.Transactions.TransactionStateMachine do
  @moduledoc """
  Transaction lifecycle transitions with correlation metadata on transition events.
  """

  @states [:none, :authorized, :started, :metering, :stopped]
  @allowed_transitions %{
    none: [:authorized],
    authorized: [:started, :stopped],
    started: [:metering, :stopped],
    metering: [:metering, :stopped],
    stopped: []
  }

  defmodule Transaction do
    @moduledoc false

    @enforce_keys [:id, :state]
    defstruct [:id, :state, :last_transition]

    @type t :: %__MODULE__{
            id: String.t(),
            state: atom(),
            last_transition: map() | nil
          }
  end

  defmodule TransitionEvent do
    @moduledoc false

    @enforce_keys [:transaction_id, :from_state, :to_state, :occurred_at, :correlation]
    defstruct [:transaction_id, :from_state, :to_state, :occurred_at, :correlation]

    @type t :: %__MODULE__{
            transaction_id: String.t(),
            from_state: atom(),
            to_state: atom(),
            occurred_at: DateTime.t(),
            correlation: map()
          }
  end

  @type state :: :none | :authorized | :started | :metering | :stopped

  @spec new_transaction(String.t()) :: {:ok, Transaction.t()} | {:error, term()}
  def new_transaction(transaction_id) when is_binary(transaction_id) and transaction_id != "" do
    {:ok, %Transaction{id: transaction_id, state: :none, last_transition: nil}}
  end

  def new_transaction(_transaction_id),
    do: {:error, {:invalid_field, :transaction_id, :must_be_non_empty_string}}

  @spec transition(Transaction.t(), state(), map()) ::
          {:ok, Transaction.t(), TransitionEvent.t()} | {:error, term()}
  def transition(%Transaction{} = transaction, to_state, correlation) when to_state in @states do
    with :ok <- ensure_correlation(correlation),
         :ok <- ensure_allowed_transition(transaction.state, to_state) do
      event = %TransitionEvent{
        transaction_id: transaction.id,
        from_state: transaction.state,
        to_state: to_state,
        occurred_at: DateTime.utc_now(),
        correlation: correlation
      }

      updated_transaction = %{transaction | state: to_state, last_transition: event}
      {:ok, updated_transaction, event}
    end
  end

  def transition(%Transaction{}, _to_state, _correlation),
    do: {:error, {:invalid_field, :to_state, :unsupported_state}}

  @spec states() :: [state()]
  def states, do: @states

  @spec allowed_next_states(state()) :: [state()]
  def allowed_next_states(state) when state in @states do
    Map.fetch!(@allowed_transitions, state)
  end

  def allowed_next_states(_state), do: []

  defp ensure_allowed_transition(from_state, to_state) do
    case Map.fetch(@allowed_transitions, from_state) do
      {:ok, allowed_states} ->
        if to_state in allowed_states do
          :ok
        else
          {:error, {:invalid_transition, from_state, to_state}}
        end

      :error ->
        {:error, {:invalid_state, from_state}}
    end
  end

  defp ensure_correlation(correlation) when is_map(correlation) and map_size(correlation) > 0,
    do: :ok

  defp ensure_correlation(_correlation),
    do: {:error, {:invalid_field, :correlation, :must_be_non_empty_map}}
end
