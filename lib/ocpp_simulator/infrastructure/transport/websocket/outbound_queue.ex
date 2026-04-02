defmodule OcppSimulator.Infrastructure.Transport.WebSocket.OutboundQueue do
  @moduledoc """
  Backpressure-aware outbound queue with bounded in-flight dispatch and retry coordination.
  """

  use GenServer

  alias OcppSimulator.Domain.Ocpp.Message
  alias OcppSimulator.Infrastructure.Serialization.OcppJson

  @default_max_queue_size 200
  @default_max_in_flight 8
  @default_max_retry_attempts 3
  @default_retry_base_delay_ms 200

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :session_id,
      :adapter,
      :max_queue_size,
      :max_in_flight,
      :max_retry_attempts,
      :retry_base_delay_ms,
      :queue,
      :in_flight,
      :dropped_count,
      :retry_count
    ]
    defstruct [
      :session_id,
      :adapter,
      :max_queue_size,
      :max_in_flight,
      :max_retry_attempts,
      :retry_base_delay_ms,
      :queue,
      :in_flight,
      :dropped_count,
      :retry_count
    ]
  end

  @type stats :: %{
          required(:session_id) => String.t(),
          required(:queued_count) => non_neg_integer(),
          required(:in_flight_count) => non_neg_integer(),
          required(:max_queue_size) => pos_integer(),
          required(:max_in_flight) => pos_integer(),
          required(:dropped_count) => non_neg_integer(),
          required(:retry_count) => non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @spec enqueue(pid(), Message.t()) :: :ok | {:error, term()}
  def enqueue(queue_pid, %Message{} = message) when is_pid(queue_pid) do
    enqueue(queue_pid, message, [])
  end

  @spec enqueue(pid(), Message.t(), keyword()) :: :ok | {:error, term()}
  def enqueue(queue_pid, %Message{} = message, validation_opts)
      when is_pid(queue_pid) and is_list(validation_opts) do
    GenServer.call(queue_pid, {:enqueue, message, validation_opts})
  end

  @spec stats(pid()) :: stats()
  def stats(queue_pid) when is_pid(queue_pid) do
    GenServer.call(queue_pid, :stats)
  end

  @spec shutdown(pid()) :: :ok
  def shutdown(queue_pid) when is_pid(queue_pid) do
    GenServer.call(queue_pid, :shutdown)
  end

  @impl true
  def init(opts) do
    with {:ok, session_id} <- fetch_non_empty_string(opts, :session_id),
         {:ok, adapter} <- fetch_adapter(opts),
         {:ok, max_queue_size} <- fetch_positive_integer(opts, :max_queue_size, @default_max_queue_size),
         {:ok, max_in_flight} <- fetch_positive_integer(opts, :max_in_flight, @default_max_in_flight),
         {:ok, max_retry_attempts} <-
           fetch_non_neg_integer(opts, :max_retry_attempts, @default_max_retry_attempts),
         {:ok, retry_base_delay_ms} <-
           fetch_positive_integer(opts, :retry_base_delay_ms, @default_retry_base_delay_ms) do
      state = %State{
        session_id: session_id,
        adapter: adapter,
        max_queue_size: max_queue_size,
        max_in_flight: max_in_flight,
        max_retry_attempts: max_retry_attempts,
        retry_base_delay_ms: retry_base_delay_ms,
        queue: :queue.new(),
        in_flight: %{},
        dropped_count: 0,
        retry_count: 0
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:enqueue, message, validation_opts}, _from, %State{} = state) do
    if queue_full?(state) do
      {:reply, {:error, {:backpressure, :queue_full}}, state}
    else
      updated_state =
        state
        |> push_entry(%{message: message, attempts: 0, validation_opts: validation_opts})
        |> dispatch_pending()

      {:reply, :ok, updated_state}
    end
  end

  def handle_call(:stats, _from, %State{} = state) do
    {:reply,
     %{
       session_id: state.session_id,
       queued_count: :queue.len(state.queue),
       in_flight_count: map_size(state.in_flight),
       max_queue_size: state.max_queue_size,
       max_in_flight: state.max_in_flight,
       dropped_count: state.dropped_count,
       retry_count: state.retry_count
     }, state}
  end

  def handle_call(:shutdown, _from, %State{} = state) do
    {:stop, :normal, :ok, cancel_in_flight(state)}
  end

  @impl true
  def handle_info({ref, result}, %State{in_flight: in_flight} = state) when is_reference(ref) do
    case Map.pop(in_flight, ref) do
      {nil, _in_flight} ->
        {:noreply, state}

      {%{task_pid: _task_pid, entry: entry}, remaining_in_flight} ->
        Process.demonitor(ref, [:flush])

        updated_state =
          state
          |> Map.put(:in_flight, remaining_in_flight)
          |> handle_delivery_result(entry, result)
          |> dispatch_pending()

        {:noreply, updated_state}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{in_flight: in_flight} = state
      )
      when is_reference(ref) do
    case Map.pop(in_flight, ref) do
      {nil, _in_flight} ->
        {:noreply, state}

      {%{task_pid: _task_pid, entry: entry}, remaining_in_flight} ->
        updated_state =
          state
          |> Map.put(:in_flight, remaining_in_flight)
          |> handle_delivery_result(entry, {:error, {:transport_task_down, reason}})
          |> dispatch_pending()

        {:noreply, updated_state}
    end
  end

  def handle_info({:retry_entry, entry}, %State{} = state) do
    updated_state =
      if queue_full?(state) do
        %{state | dropped_count: state.dropped_count + 1}
      else
        state
        |> push_entry(entry)
        |> dispatch_pending()
      end

    {:noreply, updated_state}
  end

  defp dispatch_pending(%State{} = state) do
    cond do
      map_size(state.in_flight) >= state.max_in_flight ->
        state

      :queue.is_empty(state.queue) ->
        state

      true ->
        {{:value, entry}, remaining_queue} = :queue.out(state.queue)

        task =
          Task.Supervisor.async_nolink(OcppSimulator.Application.UseCaseTaskSupervisor, fn ->
            send_entry(state.adapter, state.session_id, entry)
          end)

        state
        |> Map.put(:queue, remaining_queue)
        |> Map.put(
          :in_flight,
          Map.put(state.in_flight, task.ref, %{task_pid: task.pid, entry: entry})
        )
        |> dispatch_pending()
    end
  end

  defp send_entry(adapter, session_id, %{message: message, validation_opts: validation_opts}) do
    with {:ok, encoded} <- OcppJson.encode(message, validation_opts),
         :ok <- adapter.send_frame(session_id, encoded) do
      :ok
    end
  end

  defp handle_delivery_result(%State{} = state, _entry, :ok), do: state

  defp handle_delivery_result(%State{} = state, entry, {:error, reason}) do
    if entry.attempts < state.max_retry_attempts do
      next_attempt = entry.attempts + 1
      delay_ms = compute_retry_delay(state.retry_base_delay_ms, next_attempt)
      retried_entry = %{entry | attempts: next_attempt}
      Process.send_after(self(), {:retry_entry, retried_entry}, delay_ms)

      %{state | retry_count: state.retry_count + 1}
    else
      _ = reason
      %{state | dropped_count: state.dropped_count + 1}
    end
  end

  defp handle_delivery_result(%State{} = state, entry, unexpected_result) do
    handle_delivery_result(state, entry, {:error, {:unexpected_send_result, unexpected_result}})
  end

  defp push_entry(%State{} = state, entry) do
    %{state | queue: :queue.in(entry, state.queue)}
  end

  defp queue_full?(%State{} = state) do
    :queue.len(state.queue) + map_size(state.in_flight) >= state.max_queue_size
  end

  defp compute_retry_delay(base_delay_ms, attempt) do
    multiplier = :math.pow(2, attempt - 1) |> round()
    base_delay_ms * multiplier
  end

  defp cancel_in_flight(%State{} = state) do
    Enum.each(state.in_flight, fn {ref, %{task_pid: task_pid}} ->
      Process.demonitor(ref, [:flush])

      if is_pid(task_pid) and Process.alive?(task_pid) do
        Process.exit(task_pid, :kill)
      end
    end)

    %{state | in_flight: %{}, queue: :queue.new()}
  end

  defp fetch_non_empty_string(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_option, key, :must_be_non_empty_string}}
    end
  end

  defp fetch_adapter(opts) do
    case Keyword.get(opts, :adapter) do
      adapter when is_atom(adapter) -> {:ok, adapter}
      _ -> {:error, {:invalid_option, :adapter, :must_be_module}}
    end
  end

  defp fetch_positive_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_option, key, :must_be_positive_integer}}
    end
  end

  defp fetch_non_neg_integer(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid_option, key, :must_be_non_negative_integer}}
    end
  end
end
