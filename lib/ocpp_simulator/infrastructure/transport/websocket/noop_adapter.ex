defmodule OcppSimulator.Infrastructure.Transport.WebSocket.NoopAdapter do
  @moduledoc """
  Default transport adapter used when no runtime WebSocket adapter is configured.
  """

  @behaviour OcppSimulator.Infrastructure.Transport.WebSocket.Adapter

  @impl true
  def connect(_session_id, _endpoint_profile), do: {:error, :transport_adapter_not_configured}

  @impl true
  def disconnect(_session_id, _reason), do: :ok

  @impl true
  def send_frame(_session_id, _payload), do: {:error, :transport_adapter_not_configured}
end
