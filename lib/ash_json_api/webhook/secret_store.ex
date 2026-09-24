defmodule AshJsonApi.Webhook.SecretStore do
  @moduledoc """
  Persistence helper for resources that store encrypted webhook secrets.

  The application owns the resource and data layer. It must expose `:id` and
  `:secret_ciphertext` attributes and accept those fields on create/update.
  """

  @salt "ash-json-api:webhook-secret:v1"

  def generate!(resource, id, opts) do
    secret = AshJsonApi.Webhook.generate_secret()
    ciphertext = encrypt_with_options!(secret, opts)
    attrs = %{id: id, secret_ciphertext: ciphertext}

    case Ash.get(resource, id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        resource
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create!(authorize?: false)

      {:ok, record} ->
        record
        |> Ash.Changeset.for_update(:update, %{secret_ciphertext: ciphertext})
        |> Ash.update!(authorize?: false)
    end

    secret
  end

  def encrypt!(secret, key) when is_binary(secret) and is_binary(key) do
    Plug.Crypto.encrypt(key, @salt, secret, max_age: :infinity)
  end

  def resolve_key!(key) when is_binary(key), do: key

  def resolve_key!({module, function, args})
      when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args) || raise "webhook encryption key is not configured"
  end

  def fetch!(resource, id, opts) do
    case Ash.get(resource, id, authorize?: false, not_found_error?: false) do
      {:ok, %{secret_ciphertext: ciphertext}} -> decrypt_with_options!(ciphertext, opts)
      {:ok, nil} -> raise "webhook secret #{inspect(id)} has not been generated"
      {:error, error} -> raise error
    end
  end

  def decrypt!(ciphertext, key) when is_binary(ciphertext) do
    case Plug.Crypto.decrypt(resolve_key!(key), @salt, ciphertext, max_age: :infinity) do
      {:ok, secret} -> secret
      {:error, reason} -> raise "could not decrypt webhook secret: #{inspect(reason)}"
    end
  end

  defp encrypt_with_options!(secret, opts) do
    Plug.Crypto.encrypt(key!(opts), salt(opts), secret, max_age: :infinity)
  end

  defp decrypt_with_options!(ciphertext, opts) do
    case Plug.Crypto.decrypt(key!(opts), salt(opts), ciphertext, max_age: :infinity) do
      {:ok, secret} -> secret
      {:error, reason} -> raise "could not decrypt webhook secret: #{inspect(reason)}"
    end
  end

  defp key!(opts), do: Keyword.fetch!(opts, :encryption_key)
  defp salt(opts), do: Keyword.get(opts, :salt, @salt)
end
