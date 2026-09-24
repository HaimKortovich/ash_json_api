defmodule Test.Acceptance.WebhookManagementTest do
  use ExUnit.Case, async: true

  import AshJsonApi.Test

  defmodule WebhookManagerCheck do
    use Ash.Policy.SimpleCheck

    def describe(_), do: "actor has the webhook manager role"

    def match?(actor, _context, _opts) do
      :webhook_manager in List.wrap(actor && Map.get(actor, :roles))
    end
  end

  defmodule Endpoint do
    @extensions
      if Code.ensure_loaded?(AshRbac) do
        [AshJsonApi.Resource, Ash.Policy, AshRbac]
      else
        [AshJsonApi.Resource, Ash.Policy]
      end

    use Ash.Resource,
      domain: Test.Acceptance.WebhookManagementTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: @extensions,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    json_api do
      type "webhook_endpoint"
      webhook_management? true

      routes do
        base "/webhooks"
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :org_id, :string, allow_nil?: false, public?: true
      attribute :name, :string, allow_nil?: false, public?: true
    end

    multitenancy do
      strategy :attribute
      attribute :org_id
    end

    actions do
      defaults [:read, :destroy]

      update :update do
        accept [:name]
      end

      create :create do
        accept [:org_id, :name]
      end
    end

    if Code.ensure_loaded?(AshRbac) do
      rbac do
        role :webhook_manager do
          actions [:read, :create, :update, :destroy]
        end
      end
    else
      policies do
        policy always() do
          authorize_if Test.Acceptance.WebhookManagementTest.WebhookManagerCheck
        end
      end
    end
  end

  defmodule Domain do
    use Ash.Domain,
      otp_app: :ash_json_api,
      extensions: [AshJsonApi.Domain]

    json_api do
      authorize? true
      log_errors? false
    end

    resources do
      resource Endpoint
    end
  end

  defmodule Router do
    use AshJsonApi.Router, domain: Domain
  end

  setup do
    Application.put_env(:ash_json_api, Domain, json_api: [test_router: Router])

    on_exit(fn ->
      try do
        Endpoint
        |> Ash.Query.for_read(:read, actor: %{roles: [:webhook_manager]})
        |> Ash.read!(tenant: "org-a", authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, actor: %{roles: [:webhook_manager]}, tenant: "org-a", authorize?: false))

        Endpoint
        |> Ash.Query.for_read(:read, actor: %{roles: [:webhook_manager]})
        |> Ash.read!(tenant: "org-b", authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, actor: %{roles: [:webhook_manager]}, tenant: "org-b", authorize?: false))
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  test "management routes are generated automatically" do
    routes = AshJsonApi.Resource.Info.routes(Endpoint, [Domain])

    assert Enum.any?(routes, &(&1.method == :get and &1.route == "/webhooks"))
    assert Enum.any?(routes, &(&1.method == :get and &1.route == "/webhooks/:id"))
    assert Enum.any?(routes, &(&1.method == :post and &1.route == "/webhooks"))
    assert Enum.any?(routes, &(&1.method == :patch and &1.route == "/webhooks/:id"))
    assert Enum.any?(routes, &(&1.method == :delete and &1.route == "/webhooks/:id"))
  end

  test "create and read are tenant-scoped and role-authorized" do
    manager = %{roles: [:webhook_manager]}

    response =
      post(
        Domain,
        "/webhooks",
        %{
          "data" => %{
            "type" => "webhook_endpoint",
            "attributes" => %{"org_id" => "org-a", "name" => "Org A endpoint"}
          }
        },
        status: 201,
        actor: manager,
        tenant: "org-a"
      )

    id = response.resp_body["data"]["id"]

    assert get(Domain, "/webhooks/#{id}", status: 200, actor: manager, tenant: "org-a").resp_body[
             "data"
           ]["attributes"]["name"] == "Org A endpoint"

    assert get(Domain, "/webhooks/#{id}", status: 404, actor: manager, tenant: "org-b").resp_body[
             "errors"
           ]

    assert [%{"id" => ^id}] =
             get(Domain, "/webhooks", status: 200, actor: manager, tenant: "org-a").resp_body[
               "data"
             ]

    patch_response =
      patch(
        Domain,
        "/webhooks/#{id}",
        %{
          "data" => %{
            "type" => "webhook_endpoint",
            "id" => id,
            "attributes" => %{"name" => "Updated endpoint"}
          }
        },
        status: 200,
        actor: manager,
        tenant: "org-a"
      )

    assert patch_response.resp_body["data"]["attributes"]["name"] == "Updated endpoint"

    delete(Domain, "/webhooks/#{id}", status: 200, actor: manager, tenant: "org-a")

    assert get(Domain, "/webhooks/#{id}", status: 404, actor: manager, tenant: "org-a").resp_body[
             "errors"
           ]
  end

  test "management routes reject an actor without the configured role" do
    response =
      post(
        Domain,
        "/webhooks",
        %{
          "data" => %{
            "type" => "webhook_endpoint",
            "attributes" => %{"org_id" => "org-a", "name" => "Not allowed"}
          }
        },
        status: 403,
        actor: %{roles: [:viewer]},
        tenant: "org-a"
      )

    assert response.resp_body["errors"]
  end
end
