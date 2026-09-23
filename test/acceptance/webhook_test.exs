# SPDX-FileCopyrightText: 2019 ash_json_api contributors <https://github.com/ash-project/ash_json_api/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Test.Acceptance.WebhookTest do
  use ExUnit.Case, async: true

  alias AshJsonApi.Webhook

  defmodule Lead do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:id, :string, allow_nil?: false)
      attribute(:name, :string, allow_nil?: false)
      attribute(:email, :string)
    end
  end

  defmodule LeadCreatedPayload do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:id, :string, allow_nil?: false)
      attribute(:type, :string, allow_nil?: false)
      attribute(:occurred_at, :utc_datetime, allow_nil?: false)

      attribute(:lead, :struct,
        allow_nil?: false,
        constraints: [instance_of: Test.Acceptance.WebhookTest.Lead]
      )
    end
  end

  defmodule Accepted do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute(:accepted, :boolean, allow_nil?: false, public?: true)
      attribute(:event_id, :string, allow_nil?: false, public?: true)
      attribute(:lead_name, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule LeadWebhook do
    use Ash.Resource,
      domain: Test.Acceptance.WebhookTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshJsonApi.Resource]

    @secret "whsec_test-secret"

    def verify(_conn, raw_body, headers) do
      Webhook.verify(
        @secret,
        headers["webhook-id"],
        headers["webhook-timestamp"],
        raw_body,
        headers["webhook-signature"]
      )
    end

    json_api do
      type("lead_webhook")

      routes do
        route(:post, "/webhooks/leads", :receive,
          webhook?: true,
          verify: &__MODULE__.verify/3,
          headers: ["webhook-id", "webhook-timestamp", "webhook-signature"]
        )
      end
    end

    actions do
      action(:receive, :struct) do
        constraints(instance_of: Test.Acceptance.WebhookTest.Accepted)

        argument(:payload, :struct,
          allow_nil?: false,
          constraints: [instance_of: Test.Acceptance.WebhookTest.LeadCreatedPayload]
        )

        run(fn input, _context ->
          payload = input.arguments.payload

          {:ok,
           %Test.Acceptance.WebhookTest.Accepted{
             accepted: true,
             event_id: payload.id,
             lead_name: payload.lead.name
           }}
        end)
      end
    end
  end

  defmodule Domain do
    use Ash.Domain,
      otp_app: :ash_json_api,
      extensions: [AshJsonApi.Domain]

    json_api do
      log_errors?(false)
    end

    resources do
      resource(LeadWebhook)
    end
  end

  defmodule Router do
    use AshJsonApi.Router, domain: Domain
  end

  import AshJsonApi.Test

  setup do
    Application.put_env(:ash_json_api, Domain, json_api: [test_router: Router])
    :ok
  end

  test "a webhook is verified, cast into typed structs, and runs through the domain" do
    payload = %{
      "id" => "evt_123",
      "type" => "lead.created",
      "occurred_at" => "2026-09-23T12:00:00Z",
      "lead" => %{
        "id" => "lead_123",
        "name" => "Ada Lovelace",
        "email" => "ada@example.com"
      }
    }

    body = Jason.encode!(payload)
    timestamp = System.system_time(:second)
    signature = Webhook.sign("whsec_test-secret", "evt_123", timestamp, body)

    response =
      Domain
      |> post("/webhooks/leads", payload,
        status: 201,
        headers: [
          {"webhook-id", "evt_123"},
          {"webhook-timestamp", to_string(timestamp)},
          {"webhook-signature", "v1,#{signature}"}
        ]
      )

    assert response.resp_body["accepted"] == true
    assert response.resp_body["event_id"] == "evt_123"
    assert response.resp_body["lead_name"] == "Ada Lovelace"
  end

  test "an invalid signature never reaches the typed action" do
    response =
      Domain
      |> post("/webhooks/leads", %{"id" => "evt_123"},
        status: 403,
        headers: [
          {"webhook-id", "evt_123"},
          {"webhook-timestamp", to_string(System.system_time(:second))},
          {"webhook-signature", "v1,not-valid"}
        ]
      )

    assert response.resp_body["errors"] != []
  end

  test "webhook routes are not duplicated as ordinary OpenAPI paths" do
    spec = AshJsonApi.OpenApi.spec(domain: [Domain])

    refute Map.has_key?(spec.paths, "/webhooks/leads")
  end
end
