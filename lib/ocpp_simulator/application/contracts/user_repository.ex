defmodule OcppSimulator.Application.Contracts.UserRepository do
  @moduledoc """
  Contract for user/account persistence.
  """

  @type user :: %{
          required(:id) => String.t(),
          required(:email) => String.t(),
          required(:role) => String.t(),
          optional(:password_hash) => String.t(),
          optional(:metadata) => map()
        }

  @type page :: %{
          required(:entries) => [user()],
          required(:page) => pos_integer(),
          required(:page_size) => pos_integer(),
          required(:total_entries) => non_neg_integer(),
          required(:total_pages) => non_neg_integer()
        }

  @callback upsert(user()) :: {:ok, user()} | {:error, term()}
  @callback get(String.t()) :: {:ok, user()} | {:error, :not_found | term()}
  @callback get_by_email(String.t()) :: {:ok, user()} | {:error, :not_found | term()}
  @callback list(map()) :: {:ok, page()} | {:error, term()}
end
