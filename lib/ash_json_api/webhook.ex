defmodule AshJsonApi.Webhook do
  @moduledoc """
  Helpers for Standard Webhooks-compatible delivery verification.

  The signed content is `webhook_id <> "." <> timestamp <> "." <> raw_body`.
  The raw request body must be used; decoded and re-encoded JSON is not safe to
  sign because its bytes may differ from the sender's payload.
  """

  @default_tolerance 300

  @type verification_error ::
          :missing_signature
          | :invalid_signature
          | :invalid_timestamp
          | :timestamp_out_of_range

  @spec generate_secret() :: String.t()
  def generate_secret do
    "whsec_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  @doc """
  Fetches the generated secret for an event from a domain configured with
  `webhooks do` and `secret_store do`.
  """
  def secret!(domain, organization_id, event)
      when is_atom(domain) and is_binary(organization_id) and is_binary(event) do
    resource = Module.concat(domain, WebhookSecret)
    config = resource.__ash_json_api_webhook_config__()

    filters = %{
      config.organization_attribute => %{"eq" => organization_id},
      config.event_attribute => %{"eq" => event}
    }

    case resource
         |> Ash.Query.new()
         |> Ash.Query.filter_input(filters)
         |> Ash.read(authorize?: false, tenant: organization_id) do
      {:ok, [%{secret_ciphertext: ciphertext}]} ->
        AshJsonApi.Webhook.SecretStore.decrypt!(ciphertext, config.encryption_key)

      {:ok, []} ->
        raise "webhook secret for #{inspect(event)} and #{inspect(organization_id)} has not been generated"

      {:error, error} ->
        raise error
    end
  end

  @spec sign(String.t(), String.t(), integer | String.t(), iodata()) :: String.t()
  def sign(secret, webhook_id, timestamp, raw_body) do
    timestamp = to_string(timestamp)
    signed_content = webhook_id <> "." <> timestamp <> "." <> IO.iodata_to_binary(raw_body)

    :crypto.mac(:hmac, :sha256, signing_key(secret), signed_content)
    |> Base.url_encode64(padding: false)
  end

  @spec verify(
          String.t(),
          String.t(),
          String.t(),
          iodata(),
          keyword
        ) :: :ok | {:error, verification_error}
  def verify(secret, webhook_id, timestamp, raw_body, signature_header, opts \\ []) do
    with {:ok, timestamp} <- parse_timestamp(timestamp),
         :ok <- verify_timestamp(timestamp, Keyword.get(opts, :tolerance, @default_tolerance)),
         :ok <- verify_signature(secret, webhook_id, timestamp, raw_body, signature_header) do
      :ok
    end
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {timestamp, ""} -> {:ok, timestamp}
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp parse_timestamp(_timestamp), do: {:error, :invalid_timestamp}

  defp verify_timestamp(timestamp, tolerance) do
    if abs(System.system_time(:second) - timestamp) <= tolerance do
      :ok
    else
      {:error, :timestamp_out_of_range}
    end
  end

  defp verify_signature(_secret, _webhook_id, _timestamp, _raw_body, nil),
    do: {:error, :missing_signature}

  defp verify_signature(secret, webhook_id, timestamp, raw_body, signature_header) do
    expected = sign(secret, webhook_id, timestamp, raw_body)

    signatures =
      signature_header
      |> String.split(" ", trim: true)
      |> Enum.map(&String.split(&1, ",", parts: 2))

    if Enum.any?(signatures, fn [version, signature] ->
         version == "v1" and secure_compare(expected, signature)
       end) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_left, _right), do: false

  defp signing_key("whsec_" <> encoded) do
    Base.url_decode64!(encoded, padding: false)
  end

  defp signing_key(secret), do: secret
end
