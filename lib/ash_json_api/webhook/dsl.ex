defmodule AshJsonApi.Webhook.Dsl do
  @moduledoc false

  @secret_store %Spark.Dsl.Section{
    name: :secret_store,
    describe: "Generated webhook secret storage configuration",
    schema: [
      data_layer: [type: :atom, required: true],
      repo: [type: :atom, required: false],
      table: [type: :string, default: "webhook_secrets"],
      organization_attribute: [type: :atom, default: :organization_id],
      event_attribute: [type: :atom, default: :event],
      encryption_key: [type: :any, required: true]
    ]
  }

  @webhooks %Spark.Dsl.Section{
    name: :webhooks,
    describe: "Webhook management configuration",
    sections: [@secret_store],
    schema: [
      roles: [
        type: :keyword_list,
        default: [],
        doc: "Optional AshRbac roles keyed by role name and action list."
      ]
    ]
  }

  def section, do: @webhooks
end
