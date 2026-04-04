defmodule OcppSimulator.Application.Contracts.LogRepository do
  @moduledoc """
  Contract for structured run/session/message log persistence.
  """

  @type log_entry :: %{
          required(:id) => String.t(),
          required(:run_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:charge_point_id) => String.t(),
          optional(:message_id) => String.t(),
          optional(:action) => String.t(),
          optional(:step_id) => String.t(),
          required(:severity) => String.t(),
          required(:event_type) => String.t(),
          required(:payload) => map(),
          required(:timestamp) => DateTime.t()
        }

  @type page :: %{
          required(:entries) => [log_entry()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback insert(log_entry()) :: {:ok, log_entry()} | {:error, term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
