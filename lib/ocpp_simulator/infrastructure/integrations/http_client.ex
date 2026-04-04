defmodule OcppSimulator.Infrastructure.Integrations.HttpClient do
  @moduledoc """
  Minimal HTTP client adapter used by integration modules.
  """

  @type headers :: [{String.t(), String.t()}]
  @type response :: %{status: pos_integer(), headers: headers(), body: String.t()}

  @callback post(String.t(), String.t(), headers(), keyword()) ::
              {:ok, response()} | {:error, term()}

  @spec post(String.t(), String.t(), headers(), keyword()) :: {:ok, response()} | {:error, term()}
  def post(url, body, headers, opts \\ [])
      when is_binary(url) and is_binary(body) and is_list(headers) and is_list(opts) do
    with :ok <- ensure_http_stack_started(),
         {:ok, request} <- build_request(url, body, headers),
         timeout <- Keyword.get(opts, :timeout, 5_000),
         {:ok, {{_version, status_code, _reason_phrase}, response_headers, response_body}} <-
           :httpc.request(:post, request, [timeout: timeout], []) do
      {:ok,
       %{
         status: status_code,
         headers:
           Enum.map(response_headers, fn {name, value} -> {to_string(name), to_string(value)} end),
         body: to_string(response_body || "")
       }}
    else
      {:error, reason} -> {:error, reason}
      {:ok, unexpected_response} -> {:error, {:unexpected_http_response, unexpected_response}}
      unexpected -> {:error, {:unexpected_http_result, unexpected}}
    end
  end

  defp build_request(url, body, headers) do
    converted_headers =
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end)

    {:ok, {String.to_charlist(url), converted_headers, ~c"application/json", body}}
  rescue
    _ -> {:error, :invalid_http_request}
  end

  defp ensure_http_stack_started do
    :inets.start()
    :ssl.start()
    :ok
  end
end
