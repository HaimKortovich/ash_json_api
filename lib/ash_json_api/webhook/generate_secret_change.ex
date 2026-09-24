defmodule AshJsonApi.Webhook.GenerateSecretChange do
  @moduledoc false
  use Ash.Resource.Change

  def change(changeset, opts, _context) do
    secret = AshJsonApi.Webhook.generate_secret()
    key = AshJsonApi.Webhook.SecretStore.resolve_key!(Keyword.fetch!(opts, :encryption_key))
    ciphertext = AshJsonApi.Webhook.SecretStore.encrypt!(secret, key)
    organization_attribute = Keyword.fetch!(opts, :organization_attribute)

    changeset
    |> Ash.Changeset.change_attribute(organization_attribute, changeset.tenant)
    |> Ash.Changeset.change_attribute(:secret_ciphertext, ciphertext)
    |> Ash.Changeset.set_context(%{webhook_secret: secret})
    |> Ash.Changeset.after_action(fn changeset, record ->
      {:ok,
       Ash.Resource.set_metadata(record, %{webhook_secret: changeset.context[:webhook_secret]})}
    end)
  end
end
