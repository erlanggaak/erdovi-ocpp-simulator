defmodule OcppSimulator.Infrastructure.Persistence.Mongo.DriverIntegrationTest do
  use ExUnit.Case, async: false

  alias OcppSimulator.Infrastructure.Persistence.Mongo.DriverClient
  alias OcppSimulator.Infrastructure.Persistence.Mongo.Indexes
  alias OcppSimulator.Infrastructure.Persistence.Mongo.UserRepository

  @mongo_url System.get_env("MONGO_INTEGRATION_URL")
  @moduletag if(
               is_binary(@mongo_url) and String.trim(@mongo_url) != "",
               do: [],
               else: [skip: "set MONGO_INTEGRATION_URL to run Mongo driver integration tests"]
             )

  setup_all do
    topology = :"mongo_integration_topology_#{System.unique_integer([:positive])}"
    database = "ocpp_simulator_integration_#{System.unique_integer([:positive])}"
    original_mongo = Application.get_env(:ocpp_simulator, :mongo)
    original_client = Application.get_env(:ocpp_simulator, :mongo_persistence_client)
    original_topology = Application.get_env(:ocpp_simulator, :mongo_persistence_topology)

    Application.put_env(:ocpp_simulator, :mongo,
      url: @mongo_url,
      pool_size: 2,
      database: database
    )

    Application.put_env(:ocpp_simulator, :mongo_persistence_client, DriverClient)
    Application.put_env(:ocpp_simulator, :mongo_persistence_topology, topology)

    {:ok, pid} = Mongo.start_link(url: @mongo_url, database: database, pool_size: 2, name: topology)

    on_exit(fn ->
      _ = Mongo.drop_database(topology, database)

      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 5_000)
      end

      restore_env(:mongo, original_mongo)
      restore_env(:mongo_persistence_client, original_client)
      restore_env(:mongo_persistence_topology, original_topology)
    end)

    {:ok, %{database: database, topology: topology}}
  end

  test "driver-backed repository roundtrip works with real MongoDB", %{
    topology: topology,
    database: database
  } do
    assert {:ok, _} = Mongo.delete_many(topology, "users", %{}, database: database)
    assert :ok = Indexes.ensure_collection("users")

    user = %{
      id: "user-int-1",
      email: "integration@example.com",
      role: "operator",
      password_hash: "hash",
      metadata: %{"source" => "integration-test"}
    }

    assert {:ok, persisted} = UserRepository.upsert(user)
    assert persisted.id == "user-int-1"

    assert {:ok, fetched} = UserRepository.get_by_email("integration@example.com")
    assert fetched.id == "user-int-1"
  end

  defp restore_env(key, nil), do: Application.delete_env(:ocpp_simulator, key)
  defp restore_env(key, value), do: Application.put_env(:ocpp_simulator, key, value)
end
