defmodule OcppSimulator.Infrastructure.Transport.WebSocket.TcpConnection do
  @moduledoc false

  use GenServer

  import Bitwise

  alias OcppSimulator.Infrastructure.Observability.StructuredLogger
  alias OcppSimulator.Infrastructure.Transport.WebSocket.SessionManager

  @registry OcppSimulator.Infrastructure.SessionRegistry
  @connection_key_prefix :tcp_ws_connection
  @connect_timeout_ms 5_000
  @read_timeout_ms 5_000
  @max_http_header_bytes 32_768
  @max_payload_bytes 2_097_152

  defstruct [:session_id, :socket, :buffer]

  @type state :: %__MODULE__{
          session_id: String.t(),
          socket: port(),
          buffer: binary()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec disconnect(pid(), term()) :: :ok | {:error, term()}
  def disconnect(pid, reason) when is_pid(pid) do
    GenServer.call(pid, {:disconnect, reason})
  catch
    :exit, _reason -> :ok
  end

  @spec send_frame(pid(), String.t()) :: :ok | {:error, term()}
  def send_frame(pid, payload) when is_pid(pid) and is_binary(payload) do
    GenServer.call(pid, {:send_frame, payload})
  catch
    :exit, _reason -> {:error, :connection_process_down}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, session_id} <- fetch_required_string(opts, :session_id),
         {:ok, endpoint_profile} <- fetch_map(opts, :endpoint_profile),
         {:ok, socket, remainder} <- open_websocket(endpoint_profile),
         {:ok, _registered} <- register_connection(session_id) do
      :ok = :inet.setopts(socket, active: :once)
      state = %__MODULE__{session_id: session_id, socket: socket, buffer: remainder || <<>>}

      if state.buffer != <<>> do
        send(self(), :drain_buffer)
      end

      {:ok, state}
    end
  end

  @impl true
  def handle_call({:send_frame, payload}, _from, %__MODULE__{} = state) do
    encoded = encode_text_frame(payload)

    case :gen_tcp.send(state.socket, encoded) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, {:tcp_send_failed, reason}}, state}
    end
  end

  def handle_call({:disconnect, reason}, _from, %__MODULE__{} = state) do
    _ = send_close_frame(state.socket)
    _ = :gen_tcp.close(state.socket)

    StructuredLogger.info("transport.tcp_connection.disconnected", %{
      persist: true,
      session_id: state.session_id,
      payload: %{reason: inspect(reason)}
    })

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:drain_buffer, %__MODULE__{} = state) do
    case process_buffer(state) do
      {:ok, updated_state} ->
        {:noreply, updated_state}

      {:stop, reason, updated_state} ->
        {:stop, reason, updated_state}
    end
  end

  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket} = state) do
    merged_state = %{state | buffer: state.buffer <> data}

    case process_buffer(merged_state) do
      {:ok, updated_state} ->
        :ok = :inet.setopts(socket, active: :once)
        {:noreply, updated_state}

      {:stop, reason, updated_state} ->
        {:stop, reason, updated_state}
    end
  end

  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    StructuredLogger.warn("transport.tcp_connection.closed", %{
      persist: true,
      session_id: state.session_id
    })

    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    StructuredLogger.warn("transport.tcp_connection.error", %{
      persist: true,
      session_id: state.session_id,
      payload: %{reason: inspect(reason)}
    })

    {:stop, {:tcp_error, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{socket: socket}) when is_port(socket) do
    _ = :gen_tcp.close(socket)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp process_buffer(%__MODULE__{} = state) do
    case decode_frame(state.buffer) do
      {:ok, frame, remaining} ->
        case handle_frame(frame, %{state | buffer: remaining}) do
          {:ok, next_state} -> process_buffer(next_state)
          {:stop, reason, next_state} -> {:stop, reason, next_state}
        end

      :incomplete ->
        {:ok, state}

      {:error, reason} ->
        StructuredLogger.warn("transport.tcp_connection.frame_decode_failed", %{
          persist: true,
          session_id: state.session_id,
          payload: %{reason: inspect(reason)}
        })

        {:stop, {:invalid_frame, reason}, state}
    end
  end

  defp handle_frame(%{opcode: 0x1, payload: payload}, %__MODULE__{} = state) do
    case SessionManager.ingest_inbound(state.session_id, payload) do
      {:ok, _result} ->
        {:ok, state}

      {:error, reason} ->
        StructuredLogger.warn("transport.tcp_connection.ingest_failed", %{
          persist: true,
          session_id: state.session_id,
          payload: %{reason: inspect(reason)}
        })

        {:ok, state}
    end
  end

  defp handle_frame(%{opcode: 0x8}, %__MODULE__{} = state) do
    _ = send_close_frame(state.socket)
    {:stop, :normal, state}
  end

  defp handle_frame(%{opcode: 0x9, payload: payload}, %__MODULE__{} = state) do
    _ = :gen_tcp.send(state.socket, encode_control_frame(0xA, payload))
    {:ok, state}
  end

  defp handle_frame(%{opcode: opcode}, %__MODULE__{} = state) when opcode in [0xA, 0x0],
    do: {:ok, state}

  defp handle_frame(_frame, %__MODULE__{} = state), do: {:ok, state}

  defp open_websocket(endpoint_profile) do
    with {:ok, url} <- fetch_endpoint_url(endpoint_profile),
         {:ok, host, port, path_and_query} <- parse_ws_url(url),
         {:ok, socket} <- open_socket(host, port),
         {:ok, remainder} <- perform_handshake(socket, host, port, path_and_query) do
      {:ok, socket, remainder}
    end
  end

  defp fetch_endpoint_url(endpoint_profile) when is_map(endpoint_profile) do
    case Map.get(endpoint_profile, :url) || Map.get(endpoint_profile, "url") do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, {:invalid_field, :url, :must_be_non_empty_string}}
    end
  end

  defp parse_ws_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != "ws" ->
        {:error, {:invalid_field, :url, :must_use_ws_scheme}}

      not is_binary(uri.host) or uri.host == "" ->
        {:error, {:invalid_field, :url, :missing_host}}

      true ->
        port = uri.port || 80
        path = if is_binary(uri.path) and uri.path != "", do: uri.path, else: "/"
        path_and_query = if is_binary(uri.query), do: path <> "?" <> uri.query, else: path
        {:ok, uri.host, port, path_and_query}
    end
  end

  defp open_socket(host, port) do
    :gen_tcp.connect(
      String.to_charlist(host),
      port,
      [:binary, packet: :raw, active: false, nodelay: true],
      @connect_timeout_ms
    )
  end

  defp perform_handshake(socket, host, port, path_and_query) do
    key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    request = [
      "GET ",
      path_and_query,
      " HTTP/1.1\r\n",
      "Host: ",
      host,
      ":",
      Integer.to_string(port),
      "\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Version: 13\r\n",
      "Sec-WebSocket-Key: ",
      key,
      "\r\n\r\n"
    ]

    with :ok <- :gen_tcp.send(socket, request),
         {:ok, header_bin, remainder} <- recv_http_upgrade_response(socket),
         :ok <- validate_upgrade_response(header_bin, key) do
      {:ok, remainder}
    end
  end

  defp recv_http_upgrade_response(socket, acc \\ <<>>) do
    if byte_size(acc) > @max_http_header_bytes do
      {:error, :http_upgrade_response_too_large}
    else
      case :binary.match(acc, "\r\n\r\n") do
        {index, 4} ->
          header_end = index + 4
          <<header::binary-size(header_end), remainder::binary>> = acc
          {:ok, header, remainder}

        :nomatch ->
          case :gen_tcp.recv(socket, 0, @read_timeout_ms) do
            {:ok, data} -> recv_http_upgrade_response(socket, acc <> data)
            {:error, reason} -> {:error, {:http_upgrade_read_failed, reason}}
          end
      end
    end
  end

  defp validate_upgrade_response(header_bin, key) do
    lines =
      header_bin
      |> String.split("\r\n", trim: true)

    with [status_line | header_lines] <- lines,
         :ok <- validate_status_line(status_line),
         headers = parse_headers(header_lines),
         :ok <- validate_header_contains(headers, "upgrade", "websocket"),
         :ok <- validate_header_contains(headers, "connection", "upgrade"),
         :ok <- validate_accept_header(headers, key) do
      :ok
    else
      _ -> {:error, :invalid_http_upgrade_response}
    end
  end

  defp validate_status_line("HTTP/1.1 101" <> _rest), do: :ok
  defp validate_status_line("HTTP/1.0 101" <> _rest), do: :ok
  defp validate_status_line(_line), do: {:error, :http_upgrade_rejected}

  defp parse_headers(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          Map.put(acc, String.downcase(String.trim(name)), String.trim(value))

        _ ->
          acc
      end
    end)
  end

  defp validate_header_contains(headers, key, expected_substring) do
    value =
      headers
      |> Map.get(key, "")
      |> String.downcase()

    if String.contains?(value, expected_substring),
      do: :ok,
      else: {:error, {:missing_header, key}}
  end

  defp validate_accept_header(headers, key) do
    expected =
      :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
      |> Base.encode64()

    actual = Map.get(headers, "sec-websocket-accept")

    if actual == expected do
      :ok
    else
      {:error, :invalid_websocket_accept}
    end
  end

  defp decode_frame(data) when byte_size(data) < 2, do: :incomplete

  defp decode_frame(<<byte1, byte2, rest::binary>>) do
    opcode = band(byte1, 0x0F)
    masked? = band(byte2, 0x80) == 0x80
    length_code = band(byte2, 0x7F)

    with {:ok, payload_len, rest_after_len} <- decode_payload_length(length_code, rest),
         :ok <- ensure_payload_limit(payload_len),
         {:ok, mask_key, rest_after_mask} <- decode_mask_key(masked?, rest_after_len),
         true <- byte_size(rest_after_mask) >= payload_len do
      <<payload::binary-size(payload_len), remaining::binary>> = rest_after_mask
      decoded_payload = if masked?, do: apply_mask(payload, mask_key), else: payload
      {:ok, %{opcode: opcode, payload: decoded_payload}, remaining}
    else
      false -> :incomplete
      {:error, reason} -> {:error, reason}
      :incomplete -> :incomplete
    end
  end

  defp decode_payload_length(length_code, rest) when length_code < 126,
    do: {:ok, length_code, rest}

  defp decode_payload_length(126, rest) do
    if byte_size(rest) < 2 do
      :incomplete
    else
      <<length::unsigned-big-integer-size(16), remaining::binary>> = rest
      {:ok, length, remaining}
    end
  end

  defp decode_payload_length(127, rest) do
    if byte_size(rest) < 8 do
      :incomplete
    else
      <<length::unsigned-big-integer-size(64), remaining::binary>> = rest
      {:ok, length, remaining}
    end
  end

  defp decode_mask_key(false, rest), do: {:ok, <<>>, rest}

  defp decode_mask_key(true, rest) do
    if byte_size(rest) < 4 do
      :incomplete
    else
      <<mask::binary-size(4), remaining::binary>> = rest
      {:ok, mask, remaining}
    end
  end

  defp ensure_payload_limit(payload_len) when payload_len <= @max_payload_bytes, do: :ok
  defp ensure_payload_limit(_payload_len), do: {:error, :payload_too_large}

  defp encode_text_frame(payload) when is_binary(payload), do: encode_frame(0x1, payload)

  defp encode_control_frame(opcode, payload) when is_integer(opcode) and is_binary(payload),
    do: encode_frame(opcode, payload)

  defp send_close_frame(socket) do
    :gen_tcp.send(socket, encode_control_frame(0x8, <<>>))
  end

  defp encode_frame(opcode, payload) do
    payload_len = byte_size(payload)
    mask = :crypto.strong_rand_bytes(4)
    masked_payload = apply_mask(payload, mask)
    first_byte = bor(0x80, band(opcode, 0x0F))

    cond do
      payload_len < 126 ->
        <<first_byte, bor(0x80, payload_len), mask::binary, masked_payload::binary>>

      payload_len <= 65_535 ->
        <<first_byte, 0xFE, payload_len::unsigned-big-integer-size(16), mask::binary,
          masked_payload::binary>>

      true ->
        <<first_byte, 0xFF, payload_len::unsigned-big-integer-size(64), mask::binary,
          masked_payload::binary>>
    end
  end

  defp apply_mask(payload, <<m1, m2, m3, m4>>) do
    payload
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, idx} ->
      mask_byte =
        case rem(idx, 4) do
          0 -> m1
          1 -> m2
          2 -> m3
          3 -> m4
        end

      bxor(byte, mask_byte)
    end)
    |> :erlang.list_to_binary()
  end

  defp register_connection(session_id) do
    key = {@connection_key_prefix, session_id}
    Registry.register(@registry, key, :connected)
  end

  defp fetch_required_string(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_non_empty_string}}
    end
  end

  defp fetch_map(opts, key) do
    case Keyword.get(opts, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, {:invalid_field, key, :must_be_map}}
    end
  end
end
