defmodule OcppSimulator.Domain.Sessions.SessionStateMachine do
  @moduledoc """
  Session lifecycle transitions with correlation-rich transition events.
  """

  @states [:idle, :connected, :active, :reconnecting, :disconnected, :terminated]
  @allowed_transitions %{
    idle: [:connected, :reconnecting, :disconnected, :terminated],
    connected: [:active, :reconnecting, :disconnected, :terminated],
    active: [:reconnecting, :disconnected, :terminated],
    reconnecting: [:connected, :disconnected, :terminated],
    disconnected: [:reconnecting, :terminated],
    terminated: []
  }

  defmodule Session do
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

    @enforce_keys [:session_id, :from_state, :to_state, :occurred_at, :correlation]
    defstruct [:session_id, :from_state, :to_state, :occurred_at, :correlation]

    @type t :: %__MODULE__{
            session_id: String.t(),
            from_state: atom(),
            to_state: atom(),
            occurred_at: DateTime.t(),
            correlation: map()
          }
  end

  @type state :: :idle | :connected | :active | :reconnecting | :disconnected | :terminated

  @spec new_session(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def new_session(session_id) when is_binary(session_id) and session_id != "" do
    {:ok, %Session{id: session_id, state: :idle, last_transition: nil}}
  end

  def new_session(_session_id),
    do: {:error, {:invalid_field, :session_id, :must_be_non_empty_string}}

  @spec transition(Session.t(), state(), map()) ::
          {:ok, Session.t(), TransitionEvent.t()} | {:error, term()}
  def transition(%Session{} = session, to_state, correlation) when to_state in @states do
    with :ok <- ensure_correlation(correlation),
         :ok <- ensure_allowed_transition(session.state, to_state) do
      event = %TransitionEvent{
        session_id: session.id,
        from_state: session.state,
        to_state: to_state,
        occurred_at: DateTime.utc_now(),
        correlation: correlation
      }

      updated_session = %{session | state: to_state, last_transition: event}
      {:ok, updated_session, event}
    end
  end

  def transition(%Session{}, _to_state, _correlation),
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
