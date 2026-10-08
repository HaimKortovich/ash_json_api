if Code.ensure_loaded?(OpenApiSpex) do
  defmodule AshJsonApi.OpenApiAshHooksTest.Inbound do
    defstruct [:name]
  end

  defmodule AshJsonApi.OpenApiAshHooksTest.Outbound do
    defstruct [:name]
  end

  defmodule AshHooks.Info do
    def webhooks(AshJsonApi.OpenApiAshHooksTest.Resource) do
      [
        %AshJsonApi.OpenApiAshHooksTest.Inbound{name: :provider},
        %AshJsonApi.OpenApiAshHooksTest.Outbound{name: :emitted}
      ]
    end
  end

  defmodule AshJsonApi.OpenApiAshHooksTest do
    use ExUnit.Case, async: true

    defmodule Resource do
      use Ash.Resource,
        domain: AshJsonApi.OpenApiAshHooksTest.Domain,
        data_layer: Ash.DataLayer.Ets
    end

    defmodule Domain do
      use Ash.Domain

      resources do
        resource(Resource)
      end
    end

    test "does not generate entries without domains" do
      assert AshJsonApi.OpenApi.webhooks([]) == %{}
    end

    test "generates inbound direction metadata and ignores outbound declarations" do
      entries =
        AshJsonApi.OpenApi.AshHooks.webhook_entries(Resource, [
          %AshJsonApi.OpenApiAshHooksTest.Inbound{name: :provider},
          %AshJsonApi.OpenApiAshHooksTest.Outbound{name: :workspace_updated}
        ])
        |> Map.new()

      inbound = entries["resource.provider"]

      assert inbound["post"]["x-ash-hooks-direction"] == "inbound"
      assert inbound["post"]["x-ash-hooks-provider"] == "provider"
      assert inbound["post"]["operationId"] == "receiveResourceProviderWebhook"
      refute Map.has_key?(entries, "resource.workspace_updated")
    end

    test "renders inbound AshHooks declarations as an OpenAPI 3.1 root webhook" do
      document = AshJsonApi.OpenApi.spec_json(domains: [Domain])

      assert document["openapi"] == "3.1.0"
      assert document["webhooks"]["resource.provider"]["post"]["x-ash-hooks-direction"] ==
               "inbound"
      refute Map.has_key?(document["webhooks"], "resource.emitted")
    end
  end
end
