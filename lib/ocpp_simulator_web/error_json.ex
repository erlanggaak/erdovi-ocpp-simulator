defmodule OcppSimulatorWeb.ErrorJSON do
  def render(_template, _assigns), do: %{error: %{message: "Something went wrong"}}
end
