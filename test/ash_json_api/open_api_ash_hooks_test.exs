if Code.ensure_loaded?(OpenApiSpex) do
  defmodule AshJsonApi.OpenApiAshHooksTest.Inbound do
    defstruct [:name, :provider]
  end

  defmodule AshJsonApi.OpenApiAshHooksTest.Outbound do
    defstruct [:name]
  end

  defmodule AshHooks.Info do
    def webhooks(AshJsonApi.OpenApiAshHooksTest.Resource) do
      [
        %AshJsonApi.OpenApiAshHooksTest.Inbound{name: :quote_completed},
        %AshJsonApi.OpenApiAshHooksTest.Outbound{name: :quote_requested}
      ]
    end

    def webhooks(_resource), do: []
  end

  defmodule AshJsonApi.OpenApiAshHooksTest do
    use ExUnit.Case, async: true

    defmodule Resource do
      use Ash.Resource,
        domain: AshJsonApi.OpenApiAshHooksTest.Domain,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshJsonApi.Resource]

      json_api do
        type("quote_completion_ledger")
      end

      attributes do
        uuid_primary_key(:id)
      end

      actions do
        defaults([:read])
      end
    end

    defmodule Domain do
      use Ash.Domain, extensions: [AshJsonApi.Domain]

      resources do
        resource(Resource)
      end
    end

    test "emits only inbound AshHooks declarations in the OpenAPI webhooks object" do
      document = AshJsonApi.OpenApi.spec_json(domains: [Domain])

      assert document["openapi"] == "3.1.0"
      assert Map.has_key?(document["webhooks"], "resource.quote_completed")
      refute Map.has_key?(document["webhooks"], "resource.quote_requested")
    end
  end
end
