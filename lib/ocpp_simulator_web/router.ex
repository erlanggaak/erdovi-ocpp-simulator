defmodule OcppSimulatorWeb.Router do
  use OcppSimulatorWeb, :router

  alias OcppSimulatorWeb.Auth.CurrentRolePlug
  alias OcppSimulatorWeb.Auth.LiveAuthorization

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(CurrentRolePlug, source: :session)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(CurrentRolePlug, source: :header_or_session)
  end

  scope "/", OcppSimulatorWeb do
    pipe_through(:browser)

    get("/health", HealthController, :show)

    live_session :dashboard,
      on_mount: [{LiveAuthorization, :view_dashboard}] do
      live("/", DashboardLive, :index)
    end

    live_session :charge_points,
      on_mount: [{LiveAuthorization, :view_charge_points}] do
      live("/charge-points", ChargePointsLive, :index)
    end

    live_session :target_endpoints,
      on_mount: [{LiveAuthorization, :view_target_endpoints}] do
      live("/target-endpoints", TargetEndpointsLive, :index)
    end

    live_session :scenarios,
      on_mount: [{LiveAuthorization, :view_scenarios}] do
      live("/scenarios", ScenariosLive, :index)
    end

    live_session :templates,
      on_mount: [{LiveAuthorization, :view_templates}] do
      live("/templates", TemplatesLive, :index)
    end

    live_session :scenario_builder,
      on_mount: [{LiveAuthorization, :manage_scenarios}] do
      live("/scenario-builder", ScenarioBuilderLive, :index)
    end

    live_session :run_operations,
      on_mount: [{LiveAuthorization, :start_run}] do
      live("/runs", RunOperationsLive, :index)
    end

    live_session :run_history,
      on_mount: [{LiveAuthorization, :view_runs}] do
      live("/run-history", RunHistoryLive, :index)
    end

    live_session :live_console,
      on_mount: [{LiveAuthorization, :view_runs}] do
      live("/live-console", LiveConsoleLive, :index)
    end

    live_session :logs,
      on_mount: [{LiveAuthorization, :view_runs}] do
      live("/logs", LogsLive, :index)
    end
  end

  scope "/api", OcppSimulatorWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/api", OcppSimulatorWeb.Api, as: :api do
    pipe_through(:api)

    post("/charge-points", ManagementController, :create_charge_point)
    post("/target-endpoints", ManagementController, :create_target_endpoint)
    post("/scenarios", ManagementController, :create_scenario)
    post("/templates", ManagementController, :create_template)
    get("/scenarios/export", ArtifactController, :export_scenarios)
    post("/scenarios/import", ArtifactController, :import_scenarios)
    get("/templates/export", ArtifactController, :export_templates)
    post("/templates/import", ArtifactController, :import_templates)
    post("/templates/starter", ArtifactController, :seed_starter_templates)
    get("/webhooks/endpoints", WebhookEndpointController, :index)
    post("/webhooks/endpoints", WebhookEndpointController, :upsert)

    post("/runs", RunController, :create)
    post("/runs/:id/cancel", RunController, :cancel)
  end
end
