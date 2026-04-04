defmodule OcppSimulatorWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
      import Phoenix.Controller
      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      unquote(html_helpers())

      def handle_event("dismiss_global_error_modal", _params, socket) do
        socket =
          socket
          |> clear_flash(:error)
          |> __clear_global_error_assign(:feedback)
          |> __clear_global_error_assign(:notice)

        {:noreply, socket}
      end

      defp __clear_global_error_assign(socket, key) do
        if Map.has_key?(socket.assigns, key) do
          assign(socket, key, nil)
        else
          socket
        end
      end
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def html do
    quote do
      use Phoenix.Component
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import Phoenix.Component
      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: OcppSimulatorWeb.Endpoint,
        router: OcppSimulatorWeb.Router,
        statics: []
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
