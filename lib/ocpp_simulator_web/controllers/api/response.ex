defmodule OcppSimulatorWeb.Api.Response do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias OcppSimulator.Infrastructure.Security.SensitiveDataMasker

  @spec success(Plug.Conn.t(), Plug.Conn.status(), map(), map()) :: Plug.Conn.t()
  def success(conn, status, data, meta \\ %{}) when is_map(data) and is_map(meta) do
    conn
    |> put_status(status)
    |> json(%{
      ok: true,
      data: data,
      error: nil,
      meta: build_meta(conn, meta)
    })
  end

  @spec error(Plug.Conn.t(), Plug.Conn.status(), String.t(), String.t(), map(), map()) ::
          Plug.Conn.t()
  def error(conn, status, code, message, details \\ %{}, meta \\ %{})
      when is_binary(code) and is_binary(message) and is_map(details) and is_map(meta) do
    conn
    |> put_status(status)
    |> json(%{
      ok: false,
      data: nil,
      error: %{
        code: code,
        message: message,
        details: SensitiveDataMasker.mask(details)
      },
      meta: build_meta(conn, meta)
    })
  end

  @spec from_reason(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def from_reason(conn, reason) do
    case reason do
      :not_found ->
        error(conn, :not_found, "not_found", "Requested resource was not found.", %{
          reason: reason
        })

      :forbidden ->
        error(conn, :forbidden, "forbidden", "You do not have permission.", %{reason: reason})

      {:forbidden, _} ->
        error(conn, :forbidden, "forbidden", "You do not have permission.", %{reason: reason})

      {:pre_run_validation_failed, errors} ->
        error(
          conn,
          :unprocessable_entity,
          "pre_run_validation_failed",
          "Run validation failed.",
          %{
            errors: errors
          }
        )

      {:scenario_version_mismatch, expected, actual} ->
        error(
          conn,
          :conflict,
          "scenario_version_mismatch",
          "Scenario version does not match requested version.",
          %{expected: expected, actual: actual}
        )

      {:run_not_executable, state} ->
        error(conn, :conflict, "run_not_executable", "Run is not in executable state.", %{
          state: state
        })

      {:concurrency_limit_reached, limit} ->
        error(conn, :conflict, "concurrency_limit_reached", "Concurrent run limit reached.", %{
          max_concurrent_runs: limit
        })

      {:execute_after_start_failed, reason} ->
        error(
          conn,
          :internal_server_error,
          "execute_after_start_failed",
          "Run was queued but asynchronous execution could not be started.",
          %{reason: reason}
        )

      {:invalid_transition, from_state, to_state} ->
        error(conn, :conflict, "invalid_transition", "Run state transition is not allowed.", %{
          from: from_state,
          to: to_state
        })

      {:missing_dependency, dependency} ->
        error(
          conn,
          :internal_server_error,
          "missing_dependency",
          "Server dependency is missing.",
          %{
            dependency: dependency
          }
        )

      {:invalid_arguments, operation} ->
        error(conn, :unprocessable_entity, "invalid_arguments", "Request payload is invalid.", %{
          operation: operation
        })

      {:invalid_field, field, detail} ->
        error(conn, :unprocessable_entity, "invalid_field", "One or more fields are invalid.", %{
          field: field,
          detail: detail
        })

      _ ->
        error(
          conn,
          :unprocessable_entity,
          "invalid_request",
          "Request could not be processed.",
          %{
            reason: reason
          }
        )
    end
  end

  defp build_meta(conn, meta) do
    request_id =
      conn.assigns[:request_id] ||
        List.first(get_resp_header(conn, "x-request-id")) ||
        List.first(get_req_header(conn, "x-request-id"))

    base_meta =
      if is_binary(request_id) and request_id != "" do
        %{request_id: request_id}
      else
        %{}
      end

    Map.merge(base_meta, meta)
  end
end
