defmodule OcppSimulatorWeb.Live.UITheme do
  @moduledoc false

  use OcppSimulatorWeb, :html

  @nav_items [
    %{path: "/dashboard", label: "Dashboard"},
    %{path: "/charge-points", label: "Charge Points"},
    %{path: "/target-endpoints", label: "Endpoints"},
    %{path: "/scenarios", label: "Scenarios"},
    %{path: "/templates", label: "Templates"},
    %{path: "/scenario-builder", label: "Builder"},
    %{path: "/runs", label: "Runs"},
    %{path: "/run-history", label: "History"},
    %{path: "/live-console", label: "Console"},
    %{path: "/logs", label: "Logs"},
    %{path: "/", label: "Switch Role"}
  ]

  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:current_path, :string, default: "/")
  attr(:current_role, :any, default: :viewer)
  attr(:notice, :string, default: nil)
  attr(:flash, :map, default: %{})
  attr(:show_nav, :boolean, default: true)
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <style><%= raw(css()) %></style>
    <% error_message = resolve_error_message(@notice, @flash) %>
    <% notice_message = resolve_notice_message(@notice, @flash, error_message) %>
    <main class="sim-shell">
      <header :if={@show_nav} class="sim-topbar sim-card">
        <div class="sim-topbar-head">
          <p class="sim-eyebrow">OCPP 1.6J Simulator</p>
          <strong>Control Workspace</strong>
        </div>
        <nav class="sim-nav">
          <.link
            :for={item <- nav_items()}
            navigate={item.path}
            class={["sim-nav-link", if(item.path == @current_path, do: "active")]}
          >
            <%= item.label %>
          </.link>
        </nav>
        <div class="sim-role-tools">
          <div class="sim-role-chip">Role: <%= role_label(@current_role) %></div>
          <form class="sim-role-form" method="post" action={~p"/session/role"}>
            <input type="hidden" name="_csrf_token" value={csrf_token_value()} />
            <input type="hidden" name="return_to" value={@current_path} />
            <select name="role" aria-label="Switch role">
              <option value="viewer" selected={@current_role == :viewer}>Viewer</option>
              <option value="operator" selected={@current_role == :operator}>Operator</option>
              <option value="admin" selected={@current_role == :admin}>Admin</option>
            </select>
            <button type="submit" class="sim-role-submit">Apply Role</button>
          </form>
        </div>
      </header>

      <section class="sim-page sim-card">
        <header class="sim-page-header">
          <h1><%= @title %></h1>
          <p :if={@subtitle}><%= @subtitle %></p>
        </header>

        <p :if={notice_message} class="sim-feedback"><%= notice_message %></p>
        <%= render_slot(@inner_block) %>
      </section>

      <div :if={error_message} id="sim-global-error-modal" class="sim-modal-backdrop">
        <section class="sim-modal sim-modal-error">
          <h2>Terjadi Error</h2>
          <p><%= error_message %></p>
          <div class="sim-actions">
            <button
              type="button"
              class="sim-button-danger"
              onclick="document.getElementById('sim-global-error-modal')?.remove()"
              phx-click={
                JS.push("dismiss_global_error_modal")
                |> JS.hide(to: "#sim-global-error-modal")
              }
            >
              Tutup
            </button>
          </div>
        </section>
      </div>

      <script src="/vendor/phoenix/phoenix.min.js"></script>
      <script src="/vendor/phoenix_live_view/phoenix_live_view.min.js"></script>
      <script>
        (() => {
          const LiveSocketCtor =
            (window.LiveView && window.LiveView.LiveSocket) || window.LiveSocket;
          const SocketCtor = (window.Phoenix && window.Phoenix.Socket) || window.Socket;
          if (window.liveSocket || !LiveSocketCtor || !SocketCtor) return;

          const csrfToken = "<%= csrf_token_value() %>";
          const liveSocket = new LiveSocketCtor("/live", SocketCtor, {
            params: {_csrf_token: csrfToken}
          });

          liveSocket.connect();
          window.liveSocket = liveSocket;
        })();
      </script>
    </main>
    """
  end

  def nav_items, do: @nav_items

  def role_label(:admin), do: "Admin"
  def role_label(:operator), do: "Operator"
  def role_label(:viewer), do: "Viewer"
  def role_label(other), do: to_string(other || "viewer")

  defp resolve_notice_message(notice, flash, error_message) do
    notice_from_flash = present_message(flash_message(flash, :info))
    notice_from_state = present_message(notice)

    cond do
      notice_from_flash != nil -> notice_from_flash
      notice_from_state != nil and notice_from_state != error_message -> notice_from_state
      true -> nil
    end
  end

  defp resolve_error_message(notice, flash) do
    notice_from_flash = present_message(flash_message(flash, :error))
    notice_from_state = present_message(notice)

    cond do
      notice_from_flash != nil -> notice_from_flash
      error_notice?(notice_from_state) -> notice_from_state
      true -> nil
    end
  end

  defp flash_message(flash, key) when is_map(flash) do
    Map.get(flash, key) || Map.get(flash, Atom.to_string(key))
  end

  defp flash_message(_flash, _key), do: nil

  defp present_message(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      message -> message
    end
  end

  defp present_message(_value), do: nil

  defp error_notice?(nil), do: false

  defp error_notice?(message) when is_binary(message) do
    normalized = String.downcase(message)

    Enum.any?(
      [
        "unable",
        "cannot",
        "error",
        "failed",
        "forbidden",
        "invalid",
        "not allowed",
        "gagal",
        "tidak bisa",
        "tidak dapat",
        "tidak diizinkan",
        "tidak punya izin"
      ],
      &String.contains?(normalized, &1)
    )
  end

  defp csrf_token_value, do: Plug.CSRFProtection.get_csrf_token()

  def css do
    """
    @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap');

    :root {
      --ink-strong: #132234;
      --ink: #25384b;
      --ink-soft: #5d7082;
      --surface: #ffffff;
      --surface-soft: #f4f7f8;
      --line: #d8e1e6;
      --teal: #0f766e;
      --teal-deep: #0b5a54;
      --orange: #d97706;
      --red: #b93823;
      --radius-lg: 18px;
      --radius-md: 12px;
      --shadow: 0 18px 40px rgba(16, 37, 52, 0.12);
    }

    body {
      margin: 0;
      font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 5% 2%, rgba(15, 118, 110, 0.14), transparent 35%),
        radial-gradient(circle at 95% 8%, rgba(217, 119, 6, 0.18), transparent 35%),
        linear-gradient(160deg, #fffdf8, #eef4f6 55%, #f7fafc);
    }

    .sim-shell {
      max-width: 1220px;
      margin: 0 auto;
      padding: 1.2rem 1rem 3rem;
      display: grid;
      gap: 1rem;
    }

    .sim-card {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius-lg);
      box-shadow: 0 6px 20px rgba(17, 30, 41, 0.06);
      animation: rise-in 0.35s ease both;
    }

    .sim-topbar {
      padding: 0.8rem;
      display: grid;
      gap: 0.6rem;
    }

    .sim-topbar-head {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 0.6rem;
      color: var(--ink-strong);
    }

    .sim-eyebrow {
      margin: 0;
      font-size: 0.72rem;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--ink-soft);
      font-family: "IBM Plex Mono", monospace;
    }

    .sim-nav {
      display: flex;
      gap: 0.42rem;
      flex-wrap: wrap;
    }

    .sim-nav-link {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 0.28rem 0.62rem;
      background: var(--surface-soft);
      color: var(--ink-strong);
      text-decoration: none;
      font-size: 0.84rem;
      transition: border-color 0.15s ease, transform 0.15s ease, box-shadow 0.15s ease;
    }

    .sim-nav-link:hover {
      border-color: var(--teal);
      transform: translateY(-1px);
      box-shadow: 0 8px 16px rgba(15, 118, 110, 0.15);
    }

    .sim-nav-link.active {
      background: rgba(15, 118, 110, 0.1);
      border-color: var(--teal);
    }

    .sim-role-chip {
      border-radius: 999px;
      background: #e6fffa;
      border: 1px solid #8ee7d6;
      color: #0f5f58;
      padding: 0.2rem 0.6rem;
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.8rem;
    }

    .sim-role-tools {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.5rem;
    }

    .sim-role-form {
      display: flex;
      align-items: center;
      gap: 0.35rem;
      margin: 0;
    }

    .sim-role-form select {
      width: auto;
      min-width: 8rem;
      padding: 0.32rem 0.48rem;
      border-radius: 999px;
      font-size: 0.83rem;
    }

    .sim-role-submit {
      padding: 0.36rem 0.62rem;
      border-radius: 999px;
      font-size: 0.8rem;
      line-height: 1.2;
    }

    .sim-page {
      padding: 1rem;
      display: grid;
      gap: 0.9rem;
    }

    .sim-page-header h1 {
      margin: 0;
      color: var(--ink-strong);
      font-size: clamp(1.3rem, 2vw, 1.9rem);
    }

    .sim-page-header p {
      margin: 0.26rem 0 0;
      color: var(--ink-soft);
    }

    .sim-feedback {
      margin: 0;
      border-radius: var(--radius-md);
      padding: 0.65rem 0.8rem;
      font-size: 0.89rem;
      border: 1px solid #7bdcb7;
      background: #ecfdf5;
      color: #0e6c5f;
    }

    .sim-feedback.warning {
      border-color: #fdba74;
      background: #fff7ed;
      color: #9a3412;
    }

    .sim-feedback.error {
      border-color: #fca5a5;
      background: #fef2f2;
      color: #991b1b;
    }

    .sim-muted {
      margin: 0;
      color: var(--ink-soft);
      font-size: 0.9rem;
    }

    .sim-inline-link a {
      color: #0f5989;
      text-decoration: none;
      border-bottom: 1px solid rgba(15, 89, 137, 0.25);
    }

    .sim-inline-link a:hover {
      color: #084c76;
      border-color: #084c76;
    }

    .sim-form-grid {
      display: grid;
      gap: 0.7rem;
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
    }

    label {
      display: grid;
      gap: 0.32rem;
      color: var(--ink-strong);
      font-size: 0.9rem;
      font-weight: 500;
    }

    input,
    textarea,
    select {
      font: inherit;
      width: 100%;
      box-sizing: border-box;
      border: 1px solid var(--line);
      border-radius: 10px;
      background: #fff;
      color: var(--ink-strong);
      padding: 0.56rem 0.62rem;
      transition: border-color 0.16s ease, box-shadow 0.16s ease;
    }

    textarea {
      min-height: 10rem;
      resize: vertical;
      font-family: "IBM Plex Mono", monospace;
      font-size: 0.83rem;
    }

    input:focus,
    textarea:focus,
    select:focus {
      outline: none;
      border-color: var(--teal);
      box-shadow: 0 0 0 3px rgba(15, 118, 110, 0.16);
    }

    .sim-checkbox-row,
    .checkbox-row {
      display: flex;
      align-items: center;
      gap: 0.45rem;
    }

    .sim-checkbox-row input,
    .checkbox-row input {
      width: auto;
      accent-color: var(--teal);
    }

    button,
    .sim-button-link {
      font: inherit;
      border: 1px solid transparent;
      border-radius: 10px;
      background: var(--teal);
      color: #fff;
      padding: 0.5rem 0.72rem;
      cursor: pointer;
      text-decoration: none;
      transition: transform 0.18s ease, background-color 0.18s ease, box-shadow 0.18s ease;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 0.35rem;
    }

    button:hover,
    .sim-button-link:hover {
      transform: translateY(-1px);
      background: var(--teal-deep);
      box-shadow: 0 10px 22px rgba(15, 118, 110, 0.22);
    }

    button:disabled {
      cursor: not-allowed;
      transform: none;
      box-shadow: none;
      background: #b7c5ce;
      color: #eff4f7;
    }

    .sim-actions {
      display: flex;
      gap: 0.5rem;
      flex-wrap: wrap;
      align-items: center;
    }

    .sim-row-between {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.8rem;
      flex-wrap: wrap;
    }

    .sim-button-secondary {
      background: var(--surface-soft);
      color: var(--ink-strong);
      border-color: var(--line);
    }

    .sim-button-secondary:hover {
      background: #e9f0f3;
      color: var(--ink-strong);
      border-color: #b5c5ce;
      box-shadow: none;
    }

    .sim-button-danger {
      background: #b93823;
      border-color: #9f2f1d;
      color: #fff;
    }

    .sim-button-danger:hover {
      background: #942a18;
      border-color: #7d2315;
    }

    .sim-mode-toggle {
      background: var(--surface-soft);
      color: var(--ink-strong);
      border-color: var(--line);
    }

    .sim-mode-toggle.active {
      background: rgba(15, 118, 110, 0.12);
      color: #0c4d47;
      border-color: var(--teal);
      box-shadow: inset 0 0 0 1px rgba(15, 118, 110, 0.14);
    }

    .sim-section {
      border: 1px solid var(--line);
      background: #fcfdfd;
      border-radius: var(--radius-md);
      padding: 0.8rem;
      display: grid;
      gap: 0.65rem;
    }

    .sim-section h2,
    .sim-section h3 {
      margin: 0;
      color: var(--ink-strong);
    }

    .sim-table-wrap {
      overflow-x: auto;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 520px;
      font-size: 0.88rem;
    }

    th,
    td {
      border-bottom: 1px solid #e5edf1;
      padding: 0.5rem 0.35rem;
      vertical-align: top;
      text-align: left;
    }

    th {
      color: var(--ink-soft);
      font-size: 0.76rem;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      font-family: "IBM Plex Mono", monospace;
    }

    .sim-error-text {
      margin: 0;
      color: #9b1c1c;
      font-size: 0.82rem;
    }

    .sim-detail-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 0.5rem 0.9rem;
    }

    .sim-detail-grid p {
      margin: 0;
      font-size: 0.9rem;
    }

    .sim-step-list {
      display: grid;
      gap: 0.8rem;
    }

    .sim-step-card {
      border: 1px solid var(--line);
      background: #fff;
      border-radius: 12px;
      padding: 0.8rem;
      display: grid;
      gap: 0.6rem;
    }

    .sim-modal-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(15, 23, 42, 0.45);
      backdrop-filter: blur(2px);
      display: grid;
      place-items: center;
      z-index: 50;
      padding: 1rem;
    }

    .sim-modal {
      width: min(560px, 100%);
      background: #fff;
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      box-shadow: var(--shadow);
      padding: 1rem;
      display: grid;
      gap: 0.7rem;
    }

    .sim-modal h2,
    .sim-modal p {
      margin: 0;
    }

    .sim-modal.sim-modal-error {
      border-color: #fda4af;
      background: #fff8f8;
    }

    .sim-role-choices {
      display: grid;
      gap: 0.8rem;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    }

    .sim-role-choices form {
      margin: 0;
    }

    .sim-role-choice {
      width: 100%;
      text-align: left;
      background: linear-gradient(160deg, #f5fffe, #f5fbff);
      color: var(--ink-strong);
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      padding: 0.8rem;
      display: grid;
      gap: 0.2rem;
    }

    .sim-role-choice strong {
      font-size: 1.05rem;
    }

    .sim-role-choice span {
      color: var(--ink-soft);
      font-size: 0.86rem;
    }

    .sim-role-choice:hover {
      border-color: var(--teal);
    }

    .dashboard-canvas {
      display: grid;
      gap: 1rem;
    }

    .hero-panel {
      background: linear-gradient(135deg, rgba(15, 118, 110, 0.95), rgba(9, 87, 130, 0.9));
      color: #fff;
      border-radius: calc(var(--radius-lg) + 4px);
      box-shadow: var(--shadow);
      padding: 1.4rem;
      display: grid;
      gap: 1rem;
    }

    .eyebrow {
      font-family: "IBM Plex Mono", monospace;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      font-size: 0.74rem;
      opacity: 0.88;
      margin: 0;
    }

    .hero-panel h1 {
      margin: 0.4rem 0 0.3rem;
      font-size: clamp(1.6rem, 2.1vw, 2.2rem);
    }

    .subtitle {
      margin: 0;
      max-width: 68ch;
      opacity: 0.95;
    }

    .metric-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 0.7rem;
    }

    .metric-card {
      border-radius: var(--radius-md);
      background: rgba(255, 255, 255, 0.14);
      border: 1px solid rgba(255, 255, 255, 0.2);
      padding: 0.7rem;
    }

    .metric-card span {
      font-size: 0.78rem;
      display: block;
      opacity: 0.84;
    }

    .metric-card strong {
      font-size: 1.15rem;
      line-height: 1.4;
    }

    .card {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius-lg);
      box-shadow: 0 6px 20px rgba(17, 30, 41, 0.06);
      padding: 1rem;
    }

    .card h2 {
      margin: 0;
      color: var(--ink-strong);
      font-size: 1.04rem;
    }

    .card p {
      margin: 0.3rem 0 0;
      color: var(--ink-soft);
      font-size: 0.92rem;
    }

    .card header {
      margin-bottom: 0.8rem;
    }

    .grid {
      display: grid;
      gap: 1rem;
    }

    .grid.two-col {
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    }

    .role-actions {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 0.7rem;
      margin-top: 0.9rem;
    }

    .role-actions form {
      margin: 0;
    }

    .role-btn {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      background: var(--surface-soft);
      color: var(--ink-strong);
      text-align: left;
      padding: 0.6rem 0.7rem;
      display: grid;
      gap: 0.15rem;
      cursor: pointer;
    }

    .role-btn:hover {
      border-color: var(--teal);
    }

    .role-btn.active {
      border-color: var(--teal);
      background: rgba(15, 118, 110, 0.09);
    }

    .role-btn span {
      font-weight: 600;
    }

    .role-btn small {
      color: var(--ink-soft);
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      font-family: "IBM Plex Mono", monospace;
    }

    .row-actions {
      display: flex;
      gap: 0.5rem;
      flex-wrap: wrap;
      margin-top: 0.7rem;
    }

    .row-actions.compact {
      margin: 0;
    }

    .inline-link {
      margin-top: 0.78rem;
      font-size: 0.88rem;
    }

    .inline-link a {
      color: #0f5989;
      text-decoration: none;
      border-bottom: 1px solid rgba(15, 89, 137, 0.25);
    }

    .inline-link a:hover {
      color: #084c76;
      border-color: #084c76;
    }

    .notice,
    .warning {
      margin: 0;
      border-radius: var(--radius-md);
      padding: 0.65rem 0.8rem;
      font-size: 0.89rem;
      border: 1px solid;
    }

    .notice {
      background: #ecfdf5;
      border-color: #7bdcb7;
      color: #0e6c5f;
    }

    .warning {
      background: #fff7ed;
      border-color: #fdba74;
      color: #9a3412;
    }

    .table-card {
      overflow-x: auto;
    }

    .split-columns {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 1rem;
    }

    .split-columns h3 {
      margin: 0 0 0.42rem;
      color: var(--ink-strong);
      font-size: 0.92rem;
    }

    .split-columns ul {
      margin: 0;
      padding-left: 1rem;
      display: grid;
      gap: 0.32rem;
      font-size: 0.88rem;
    }

    .state-pill {
      display: inline-flex;
      border-radius: 999px;
      padding: 0.14rem 0.48rem;
      font-size: 0.78rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-family: "IBM Plex Mono", monospace;
    }

    .state-succeeded {
      background: #dcfce7;
      color: #166534;
    }

    .state-failed,
    .state-timed_out {
      background: #fee2e2;
      color: #991b1b;
    }

    .state-running,
    .state-queued {
      background: #dbeafe;
      color: #1e3a8a;
    }

    .state-canceled {
      background: #e5e7eb;
      color: #374151;
    }

    @keyframes rise-in {
      from {
        opacity: 0;
        transform: translateY(10px);
      }

      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    @media (max-width: 700px) {
      .sim-shell {
        padding: 0.8rem 0.6rem 2rem;
      }

      .sim-page,
      .sim-topbar {
        padding: 0.74rem;
      }

      .sim-form-grid {
        grid-template-columns: 1fr;
      }

      table {
        min-width: 440px;
      }
    }
    """
  end
end
