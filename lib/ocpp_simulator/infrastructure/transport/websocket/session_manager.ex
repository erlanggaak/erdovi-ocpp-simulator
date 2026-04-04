defmodule OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager do
  @moduledoc """
  Manages charge-point transport sessions, reconnect retries, and lifecycle synchronization.
  """

  use GenServer

  @behaviour OcppSimulator.Application.Contracts.TransportGateway

  alias OcppSimulator.Domain.Ocpp.CorrelationPolicy
  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Domain.Sessions.MessageIdRegistry
  alias OcppSimulator.Domain.Sessions.SessionStateMachine
  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulator.Infrastructure.Serialization.OcppJson
  alias OcppSimulator.Infrastructure.Serialization.OcppJson.PayloadValidator
  alias OcppSimulator.Infrastructure.Transport.WebSocket.NoopAdapter
  alias OcppSimulator.Infrastructure.Transport.WebSocket.OutboundQueue
  alias OcppSimulator.Infrastructure.Transport.WebSocket.RemoteOperationHandler

  @default_max_reconnect_attempts 3
  @default_max_queue_size 200
  @default_max_in_flight 8
  @default_max_queue_retry_attempts 3

  defmodule SessionEntry do
    @moduledoc false

    @enforce_keys [
      :id,
      :endpoint_profile,
      :session,
      :message_registry,
      :correlation_policy,
      :queue_pid,
      :reconnect_attempt,
      :max_reconnect_attempts,
      :auto_reconnect,
      :remote_context
    ]
    defstruct [
      :id,
      :endpoint_profile,
      :session,
      :message_registry,
      :correlation_policy,
      :queue_pid,
      :reconnect_attempt,
      :max_reconnect_attempts,
      :auto_reconnect,
      :last_error,
      :remote_context
    ]
  end

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :adapter,
      :sessions,
      :retry_base_delay_ms,
      :max_reconnect_attempts,
      :max_active_sessions,
      :queue_opts
    ]
    defstruct [
      :adapter,
      :sessions,
      :retry_base_delay_ms,
      :max_reconnect_attempts,
      :max_active_sessions,
      :queue_opts
    ]
  end

  @type inbound_result ::
          %{
            required(:message) => Message.t(),
            optional(:response) => Message.t(),
            optional(:correlation_event) => map()
          }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl OcppSimulator.Application.Contracts.TransportGateway
  def connect(session_id, endpoint_profile)
      when is_binary(session_id) and is_map(endpoint_profile) do
    GenServer.call(__MODULE__, {:connect, session_id, endpoint_profile})
  end

  @impl OcppSimulator.Application.Contracts.TransportGateway
  def disconnect(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:disconnect, session_id, :requested})
  end

  @impl OcppSimulator.Application.Contracts.TransportGateway
  def send_message(session_id, %Message{} = message) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:send_message, session_id, message})
  end

  @spec reconnect(String.t(), term()) :: :ok | {:error, term()}
  def reconnect(session_id, reason \\ :manual_reconnect) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:reconnect, session_id, reason})
  end

  @spec ingest_inbound(String.t(), String.t()) :: {:ok, inbound_result()} | {:error, term()}
  def ingest_inbound(session_id, encoded_frame)
      when is_binary(session_id) and is_binary(encoded_frame) do
    GenServer.call(__MODULE__, {:ingest_inbound, session_id, encoded_frame})
  end

  @spec session(String.t()) :: {:ok, map()} | {:error, :not_found}
  def session(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:session, session_id})
  end

  @spec list_sessions() :: [map()]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @spec expire_correlations() :: [map()]
  def expire_correlations do
    GenServer.call(__MODULE__, :expire_correlations)
  end

  @impl true
  def init(opts) do
    runtime = Application.get_env(:ocpp_simulator, :runtime, [])

    retry_base_delay_ms =
      Keyword.get(
        opts,
        :retry_base_delay_ms,
        Keyword.get(runtime, :ws_retry_base_delay_ms, 1_000)
      )

    state = %State{
      adapter:
        Keyword.get(
          opts,
          :adapter,
          Application.get_env(:ocpp_simulator, :ocpp_transport_adapter, NoopAdapter)
        ),
      sessions: %{},
      retry_base_delay_ms: retry_base_delay_ms,
      max_reconnect_attempts:
        Keyword.get(
          opts,
          :max_reconnect_attempts,
          Keyword.get(runtime, :ws_max_reconnect_attempts, @default_max_reconnect_attempts)
        ),
      max_active_sessions:
        Keyword.get(
          opts,
          :max_active_sessions,
          Keyword.get(runtime, :max_active_sessions, 200)
        ),
      queue_opts: %{
        max_queue_size:
          Keyword.get(
            opts,
            :max_queue_size,
            Keyword.get(runtime, :ws_outbound_max_queue_size, @default_max_queue_size)
          ),
        max_in_flight:
          Keyword.get(
            opts,
            :max_in_flight,
            Keyword.get(runtime, :ws_outbound_max_in_flight, @default_max_in_flight)
          ),
        max_retry_attempts:
          Keyword.get(
            opts,
            :max_queue_retry_attempts,
            Keyword.get(
              runtime,
              :ws_outbound_max_retry_attempts,
              @default_max_queue_retry_attempts
            )
          ),
        retry_base_delay_ms:
          Keyword.get(
            opts,
            :queue_retry_base_delay_ms,
            Keyword.get(runtime, :ws_outbound_retry_base_delay_ms, retry_base_delay_ms)
          )
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, session_id, endpoint_profile}, _from, %State{} = state) do
    with :ok <- ensure_session_capacity(state, session_id),
         {:ok, entry} <- ensure_session_entry(state, session_id, endpoint_profile),
         {:ok, updated_entry} <- attempt_connect(entry, state) do
      StructuredLogger.info("session.connected", %{
        persist: true,
        session_id: session_id,
        event: "connect"
      })

      {:reply, :ok, put_entry(state, updated_entry)}
    else
      {:error, reason, entry} ->
        failed_entry = schedule_reconnect(%{entry | last_error: reason}, state)

        StructuredLogger.warn("session.connect_failed", %{
          persist: true,
          session_id: session_id,
          event: "connect_failed",
          reason: inspect(reason)
        })

        {:reply, {:error, {:connect_failed, reason}}, put_entry(state, failed_entry)}

      {:error, reason} ->
        StructuredLogger.warn("session.connect_rejected", %{
          persist: true,
          session_id: session_id,
          event: "connect_rejected",
          reason: inspect(reason)
        })

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:disconnect, session_id, reason}, _from, %State{} = state) do
    case fetch_entry(state, session_id) do
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:ok, entry} ->
        _ = maybe_stop_queue(entry.queue_pid)
        adapter_result = state.adapter.disconnect(session_id, reason)

        updated_entry =
          entry
          |> Map.put(:queue_pid, nil)
          |> Map.put(:auto_reconnect, false)
          |> Map.put(:reconnect_attempt, 0)
          |> Map.put(:last_error, nil)
          |> transition_session(:disconnected, %{event: "disconnect", reason: inspect(reason)})

        StructuredLogger.info("session.disconnected", %{
          persist: true,
          session_id: session_id,
          event: "disconnect",
          reason: inspect(reason)
        })

        {:reply, adapter_result, put_entry(state, updated_entry)}
    end
  end

  def handle_call({:reconnect, session_id, reason}, _from, %State{} = state) do
    with {:ok, entry} <- fetch_entry(state, session_id),
         :ok <- ensure_endpoint_profile(entry.endpoint_profile) do
      reconnecting_entry =
        entry
        |> Map.put(:auto_reconnect, true)
        |> transition_session(:reconnecting, %{event: "reconnect", reason: inspect(reason)})

      case attempt_connect(reconnecting_entry, state) do
        {:ok, connected_entry} ->
          {:reply, :ok, put_entry(state, connected_entry)}

        {:error, connect_reason, failed_entry} ->
          scheduled_entry =
            schedule_reconnect(%{failed_entry | last_error: connect_reason}, state)

          {:reply, {:error, {:connect_failed, connect_reason}}, put_entry(state, scheduled_entry)}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, session_id, message}, _from, %State{} = state) do
    with {:ok, entry} <- fetch_entry(state, session_id),
         :ok <- ensure_connected(entry),
         {:ok, queue_pid, entry_with_queue} <- ensure_queue(entry, state),
         {:ok, outbound_message} <- ensure_outbound_message(message),
         {:ok, tracked_entry} <- track_outbound_message(entry_with_queue, outbound_message),
         :ok <- OutboundQueue.enqueue(queue_pid, outbound_message) do
      updated_entry =
        tracked_entry
        |> transition_session(:active, %{
          event: "send_message",
          message_id: outbound_message.message_id
        })
        |> Map.put(:last_error, nil)

      StructuredLogger.info("protocol.outbound_queued", %{
        persist: true,
        session_id: session_id,
        message_id: outbound_message.message_id,
        action: outbound_message.action,
        event: "send_message"
      })

      {:reply, :ok, put_entry(state, updated_entry)}
    else
      {:error, reason} ->
        StructuredLogger.warn("protocol.outbound_rejected", %{
          persist: true,
          session_id: session_id,
          event: "send_message_rejected",
          reason: inspect(reason)
        })

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:ingest_inbound, session_id, encoded_frame}, _from, %State{} = state) do
    with {:ok, entry} <- fetch_entry(state, session_id),
         {:ok, queue_pid, entry_with_queue} <- ensure_queue(entry, state),
         {:ok, message} <- OcppJson.decode(encoded_frame, :inbound) do
      case message.type do
        :call ->
          with {:ok, response, updated_context} <-
                 RemoteOperationHandler.handle_inbound(message, entry_with_queue.remote_context),
               :ok <- OutboundQueue.enqueue(queue_pid, response, request_action: message.action) do
            updated_entry =
              entry_with_queue
              |> Map.put(:remote_context, updated_context)
              |> transition_session(:active, %{event: "inbound_call", action: message.action})

            StructuredLogger.info("protocol.inbound_call", %{
              persist: true,
              session_id: session_id,
              message_id: message.message_id,
              action: message.action,
              event: "inbound_call"
            })

            reply = %{message: message, response: response}
            {:reply, {:ok, reply}, put_entry(state, updated_entry)}
          else
            {:error, reason} ->
              StructuredLogger.warn("protocol.inbound_call_failed", %{
                persist: true,
                session_id: session_id,
                message_id: message.message_id,
                action: message.action,
                reason: inspect(reason)
              })

              {:reply, {:error, reason}, state}
          end

        response_type when response_type in [:call_result, :call_error] ->
          with {:ok, event, policy} <-
                 CorrelationPolicy.correlate_response(
                   entry_with_queue.correlation_policy,
                   message
                 ),
               :ok <-
                 PayloadValidator.validate_message(message, request_action: event.request_action) do
            updated_entry = %{entry_with_queue | correlation_policy: policy, last_error: nil}

            StructuredLogger.info("protocol.inbound_response", %{
              persist: true,
              session_id: session_id,
              message_id: message.message_id,
              action: message.action,
              event: "inbound_response"
            })

            reply = %{message: message, correlation_event: event}
            {:reply, {:ok, reply}, put_entry(state, updated_entry)}
          else
            {:error, reason} ->
              StructuredLogger.warn("protocol.inbound_response_failed", %{
                persist: true,
                session_id: session_id,
                message_id: message.message_id,
                action: message.action,
                reason: inspect(reason)
              })

              {:reply, {:error, reason}, state}
          end
      end
    else
      {:error, reason} ->
        StructuredLogger.warn("protocol.inbound_rejected", %{
          persist: true,
          session_id: session_id,
          reason: inspect(reason)
        })

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:session, session_id}, _from, %State{} = state) do
    case fetch_entry(state, session_id) do
      {:ok, entry} ->
        {:reply, {:ok, present_entry(entry)}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list_sessions, _from, %State{} = state) do
    sessions =
      state.sessions
      |> Map.values()
      |> Enum.map(&present_entry/1)
      |> Enum.sort_by(& &1.id)

    {:reply, sessions, state}
  end

  def handle_call(:expire_correlations, _from, %State{} = state) do
    now = DateTime.utc_now()

    {updated_sessions, expired_events} =
      Enum.reduce(state.sessions, {%{}, []}, fn {session_id, entry}, {sessions_acc, events_acc} ->
        {:ok, events, updated_policy} = CorrelationPolicy.expire(entry.correlation_policy, now)

        session_events =
          Enum.map(events, fn event ->
            Map.put(event, :session_id, session_id)
          end)

        updated_entry = %{entry | correlation_policy: updated_policy}

        {Map.put(sessions_acc, session_id, updated_entry), events_acc ++ session_events}
      end)

    {:reply, expired_events, %{state | sessions: updated_sessions}}
  end

  @impl true
  def handle_info({:retry_connect, session_id}, %State{} = state) do
    case fetch_entry(state, session_id) do
      {:error, :not_found} ->
        {:noreply, state}

      {:ok, %SessionEntry{auto_reconnect: false}} ->
        {:noreply, state}

      {:ok, entry} ->
        case attempt_connect(entry, state) do
          {:ok, connected_entry} ->
            {:noreply, put_entry(state, connected_entry)}

          {:error, reason, failed_entry} ->
            scheduled_entry = schedule_reconnect(%{failed_entry | last_error: reason}, state)
            {:noreply, put_entry(state, scheduled_entry)}
        end
    end
  end

  defp attempt_connect(%SessionEntry{} = entry, %State{} = state) do
    with :ok <- ensure_endpoint_profile(entry.endpoint_profile),
         :ok <- state.adapter.connect(entry.id, entry.endpoint_profile),
         {:ok, _queue_pid, with_queue} <- ensure_queue(entry, state),
         {:ok, updated_policy} <-
           CorrelationPolicy.new(timeout_ms: entry.correlation_policy.timeout_ms) do
      connected_entry =
        with_queue
        |> Map.put(:correlation_policy, updated_policy)
        |> Map.put(:reconnect_attempt, 0)
        |> Map.put(:auto_reconnect, true)
        |> Map.put(:last_error, nil)
        |> transition_session(:connected, %{event: "connect"})

      {:ok, connected_entry}
    else
      {:error, reason} -> {:error, reason, entry}
    end
  end

  defp ensure_session_entry(%State{} = state, session_id, endpoint_profile) do
    with :ok <- ensure_endpoint_profile(endpoint_profile),
         {:ok, entry} <- fetch_or_build_entry(state, session_id, endpoint_profile) do
      {:ok, %{entry | endpoint_profile: endpoint_profile, auto_reconnect: true}}
    end
  end

  defp ensure_session_capacity(%State{} = state, session_id) do
    if Map.has_key?(state.sessions, session_id) or
         map_size(state.sessions) < state.max_active_sessions do
      :ok
    else
      {:error, {:capacity_reached, :max_active_sessions}}
    end
  end

  defp fetch_or_build_entry(%State{} = state, session_id, endpoint_profile) do
    case fetch_entry(state, session_id) do
      {:ok, entry} ->
        {:ok, %{entry | endpoint_profile: endpoint_profile}}

      {:error, :not_found} ->
        build_entry(session_id, endpoint_profile, state.max_reconnect_attempts)
    end
  end

  defp build_entry(session_id, endpoint_profile, max_reconnect_attempts) do
    with {:ok, session} <- SessionStateMachine.new_session(session_id),
         {:ok, message_registry} <- MessageIdRegistry.new(session_id),
         {:ok, correlation_policy} <- CorrelationPolicy.new() do
      {:ok,
       %SessionEntry{
         id: session_id,
         endpoint_profile: endpoint_profile,
         session: session,
         message_registry: message_registry,
         correlation_policy: correlation_policy,
         queue_pid: nil,
         reconnect_attempt: 0,
         max_reconnect_attempts: max_reconnect_attempts,
         auto_reconnect: true,
         last_error: nil,
         remote_context: %{}
       }}
    end
  end

  defp ensure_endpoint_profile(endpoint_profile)
       when is_map(endpoint_profile) and map_size(endpoint_profile) > 0,
       do: :ok

  defp ensure_endpoint_profile(_endpoint_profile),
    do: {:error, {:invalid_field, :endpoint_profile, :must_be_non_empty_map}}

  defp ensure_connected(%SessionEntry{} = entry) do
    if entry.session.state in [:connected, :active] do
      :ok
    else
      {:error, {:session_not_connected, entry.session.state}}
    end
  end

  defp ensure_queue(%SessionEntry{} = entry, %State{} = state) do
    if is_pid(entry.queue_pid) and Process.alive?(entry.queue_pid) do
      {:ok, entry.queue_pid, entry}
    else
      queue_opts = [
        session_id: entry.id,
        adapter: state.adapter,
        max_queue_size: state.queue_opts.max_queue_size,
        max_in_flight: state.queue_opts.max_in_flight,
        max_retry_attempts: state.queue_opts.max_retry_attempts,
        retry_base_delay_ms: state.queue_opts.retry_base_delay_ms
      ]

      case start_queue_child(queue_opts) do
        {:ok, queue_pid} ->
          {:ok, queue_pid, %{entry | queue_pid: queue_pid}}

        {:error, {:already_started, queue_pid}} ->
          {:ok, queue_pid, %{entry | queue_pid: queue_pid}}

        {:error, reason} ->
          {:error, {:queue_start_failed, reason}}
      end
    end
  end

  defp start_queue_child(queue_opts) do
    case Process.whereis(OcppSimulator.Infrastructure.WebSocketConnectionSupervisor) do
      nil ->
        OutboundQueue.start_link(queue_opts)

      _pid ->
        DynamicSupervisor.start_child(
          OcppSimulator.Infrastructure.WebSocketConnectionSupervisor,
          {OutboundQueue, queue_opts}
        )
    end
  end

  defp maybe_stop_queue(queue_pid) when is_pid(queue_pid) do
    if Process.alive?(queue_pid) do
      try do
        OutboundQueue.shutdown(queue_pid)
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
    end
  end

  defp maybe_stop_queue(_queue_pid), do: :ok

  defp ensure_outbound_message(%Message{type: :call_result}),
    do: {:error, {:missing_request_action, :call_result}}

  defp ensure_outbound_message(%Message{direction: nil} = message),
    do: {:ok, %{message | direction: :outbound}}

  defp ensure_outbound_message(%Message{direction: :outbound} = message), do: {:ok, message}

  defp ensure_outbound_message(%Message{}),
    do: {:error, {:invalid_field, :message, :must_be_outbound_or_unspecified_direction}}

  defp track_outbound_message(%SessionEntry{} = entry, %Message{type: :call} = message) do
    with {:ok, updated_registry} <-
           MessageIdRegistry.register(entry.message_registry, message.message_id),
         {:ok, updated_policy} <- CorrelationPolicy.track_call(entry.correlation_policy, message) do
      {:ok, %{entry | message_registry: updated_registry, correlation_policy: updated_policy}}
    end
  end

  defp track_outbound_message(%SessionEntry{} = entry, %Message{}), do: {:ok, entry}

  defp schedule_reconnect(%SessionEntry{} = entry, %State{} = state) do
    if entry.auto_reconnect and entry.reconnect_attempt < entry.max_reconnect_attempts do
      next_attempt = entry.reconnect_attempt + 1
      delay_ms = compute_retry_delay(state.retry_base_delay_ms, next_attempt)
      Process.send_after(self(), {:retry_connect, entry.id}, delay_ms)

      entry
      |> Map.put(:reconnect_attempt, next_attempt)
      |> transition_session(:reconnecting, %{event: "retry_connect", attempt: next_attempt})
    else
      transition_session(entry, :disconnected, %{event: "reconnect_exhausted"})
    end
  end

  defp compute_retry_delay(base_delay_ms, attempt) when is_integer(attempt) and attempt > 0 do
    multiplier = :math.pow(2, attempt - 1) |> round()
    base_delay_ms * multiplier
  end

  defp transition_session(%SessionEntry{} = entry, to_state, correlation_metadata) do
    correlation =
      correlation_metadata
      |> Map.put_new(:source, "session_manager")
      |> Map.put_new(:session_id, entry.id)

    case SessionStateMachine.transition(entry.session, to_state, correlation) do
      {:ok, updated_session, _event} -> %{entry | session: updated_session}
      {:error, {:invalid_transition, _from, _to}} -> entry
      {:error, _reason} -> entry
    end
  end

  defp fetch_entry(%State{} = state, session_id) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  defp put_entry(%State{} = state, %SessionEntry{} = entry) do
    %{state | sessions: Map.put(state.sessions, entry.id, entry)}
  end

  defp present_entry(%SessionEntry{} = entry) do
    %{
      id: entry.id,
      endpoint_profile: entry.endpoint_profile,
      session_state: entry.session.state,
      reconnect_attempt: entry.reconnect_attempt,
      max_reconnect_attempts: entry.max_reconnect_attempts,
      auto_reconnect: entry.auto_reconnect,
      last_error: entry.last_error,
      pending_correlation_count: CorrelationPolicy.pending_count(entry.correlation_policy),
      queue_stats: queue_stats(entry.queue_pid),
      remote_context: entry.remote_context
    }
  end

  defp queue_stats(queue_pid) when is_pid(queue_pid) do
    if Process.alive?(queue_pid), do: OutboundQueue.stats(queue_pid), else: nil
  end

  defp queue_stats(_queue_pid), do: nil
end
