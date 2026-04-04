defmodule OcppSimulator.Infrastructure.Security.SensitiveDataMaskerTest do
  use ExUnit.Case, async: true

  alias OcppSimulator.Infrastructure.Security.SensitiveDataMasker

  test "masks common secret/token/password fields recursively" do
    payload = %{
      "api_key" => "my-secret-key",
      "password" => "super-secret-password",
      "nested" => %{
        "token" => "abc.def.ghi",
        "normal" => "ok",
        "secret_ref" => "whsec_local"
      },
      "list" => [%{"authorization" => "Bearer token-value"}, %{"name" => "safe"}]
    }

    masked = SensitiveDataMasker.mask(payload)

    assert masked["api_key"] == SensitiveDataMasker.redacted()
    assert masked["password"] == SensitiveDataMasker.redacted()
    assert masked["nested"]["token"] == SensitiveDataMasker.redacted()
    assert masked["nested"]["secret_ref"] == SensitiveDataMasker.redacted()
    assert masked["nested"]["normal"] == "ok"

    assert masked["list"] |> Enum.at(0) |> Map.fetch!("authorization") ==
             SensitiveDataMasker.redacted()

    assert masked["list"] |> Enum.at(1) |> Map.fetch!("name") == "safe"
  end
end
