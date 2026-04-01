defmodule OcppSimulator.Domain.Ocpp.CorrelationPolicy do
  @moduledoc """
  Tracks outbound OCPP calls, correlates responses, and expires timed-out calls.
  """

  alias OcppSimulator.Domain.Ocpp.Message

  @default_timeout_ms 30_000

  @enforce_keys [:timeout_ms, :pending_calls]
  defstruct timeout_ms: @default_timeout_ms, pending_calls: %{}

  @type pending_call :: %{action: String.t(), tracked_at: DateTime.t()}

  @type t :: %__MODULE__{
          timeout_ms: pos_integer(),
          pending_calls: %{String.t() => pending_call()}
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    if is_integer(timeout_ms) and timeout_ms > 0 do
      {:ok, %__MODULE__{timeout_ms: timeout_ms, pending_calls: %{}}}
    else
      {:error, {:invalid_field, :timeout_ms, :must_be_positive_integer}}
    end
  end

  @spec track_call(t(), Message.t(), DateTime.t()) :: {:ok, t()} | {:error, term()}
  def track_call(policy, message, now \\ DateTime.utc_now())

  def track_call(
        %__MODULE__{} = policy,
        %Message{type: :call, direction: :outbound} = message,
        now
      ) do
    if Map.has_key?(policy.pending_calls, message.message_id) do
      {:error, {:duplicate_message_id, message.message_id}}
    else
      pending_call = %{action: message.action, tracked_at: now}

      {:ok,
       %{policy | pending_calls: Map.put(policy.pending_calls, message.message_id, pending_call)}}
    end
  end

  def track_call(%__MODULE__{}, _message, _now),
    do: {:error, {:invalid_field, :message, :must_be_outbound_call_message}}

  @spec correlate_response(t(), Message.t(), DateTime.t()) :: {:ok, map(), t()} | {:error, term()}
  def correlate_response(policy, message, now \\ DateTime.utc_now())

  def correlate_response(
        %__MODULE__{} = policy,
        %Message{type: response_type, direction: :inbound, message_id: message_id},
        now
      )
      when response_type in [:call_result, :call_error] do
    case Map.pop(policy.pending_calls, message_id) do
      {nil, _pending_calls} ->
        {:error, {:unknown_message_id, message_id}}

      {pending_call, remaining_calls} ->
        event = %{
          message_id: message_id,
          request_action: pending_call.action,
          response_type: response_type,
          round_trip_ms: DateTime.diff(now, pending_call.tracked_at, :millisecond)
        }

        {:ok, event, %{policy | pending_calls: remaining_calls}}
    end
  end

  def correlate_response(%__MODULE__{}, _message, _now),
    do: {:error, {:invalid_field, :message, :must_be_inbound_call_result_or_call_error}}

  @spec expire(t(), DateTime.t()) :: {:ok, [map()], t()}
  def expire(%__MODULE__{} = policy, now \\ DateTime.utc_now()) do
    {expired_entries, active_entries} =
      Enum.split_with(policy.pending_calls, fn {_message_id, pending_call} ->
        DateTime.diff(now, pending_call.tracked_at, :millisecond) >= policy.timeout_ms
      end)

    expired_events =
      expired_entries
      |> Enum.map(fn {message_id, pending_call} ->
        %{
          message_id: message_id,
          request_action: pending_call.action,
          timeout_ms: policy.timeout_ms
        }
      end)
      |> Enum.sort_by(& &1.message_id)

    {:ok, expired_events, %{policy | pending_calls: Map.new(active_entries)}}
  end

  @spec pending_count(t()) :: non_neg_integer()
  def pending_count(%__MODULE__{} = policy), do: map_size(policy.pending_calls)
end
