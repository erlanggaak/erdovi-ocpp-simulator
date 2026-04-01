defmodule OcppSimulator do
  @moduledoc """
  Root helpers for runtime configuration lookups.
  """

  @spec runtime_config() :: keyword()
  def runtime_config do
    Application.fetch_env!(:ocpp_simulator, :runtime)
  end

  @spec mongo_config() :: keyword()
  def mongo_config do
    Application.fetch_env!(:ocpp_simulator, :mongo)
  end
end
