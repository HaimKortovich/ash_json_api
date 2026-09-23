defmodule AshJsonApi.WebhookTest do
  use ExUnit.Case, async: true

  alias AshJsonApi.Webhook

  test "generates and verifies a Standard Webhooks signature" do
    secret = Webhook.generate_secret()
    webhook_id = "evt_123"
    timestamp = System.system_time(:second)
    body = ~s({"type":"lead.created"})

    signature = Webhook.sign(secret, webhook_id, timestamp, body)

    assert :ok ==
             Webhook.verify(
               secret,
               webhook_id,
               to_string(timestamp),
               body,
               "v1,#{signature}"
             )
  end

  test "rejects a changed body" do
    secret = Webhook.generate_secret()
    timestamp = System.system_time(:second)
    signature = Webhook.sign(secret, "evt_123", timestamp, "original")

    assert {:error, :invalid_signature} =
             Webhook.verify(
               secret,
               "evt_123",
               to_string(timestamp),
               "changed",
               "v1,#{signature}"
             )
  end

  test "rejects an old timestamp" do
    secret = Webhook.generate_secret()
    timestamp = System.system_time(:second) - 301
    signature = Webhook.sign(secret, "evt_123", timestamp, "body")

    assert {:error, :timestamp_out_of_range} =
             Webhook.verify(
               secret,
               "evt_123",
               to_string(timestamp),
               "body",
               "v1,#{signature}"
             )
  end
end
