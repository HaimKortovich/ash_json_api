if Code.ensure_loaded?(OpenApiSpex) do
  defmodule AshJsonApi.OpenApi.Webhook do
    @moduledoc """
    Typed definition for an OpenAPI webhook.

    Webhooks are represented internally with OpenApiSpex structs and converted
    to a root-level OpenAPI `webhooks` object only when rendered.
    """

    alias OpenApiSpex.{MediaType, Operation, PathItem, Reference, RequestBody, Response, Schema}

    @enforce_keys [:name, :operation]
    defstruct [:name, :operation]

    @type t :: %__MODULE__{
            name: String.t(),
            operation: Operation.t()
          }

    @spec new(atom | String.t(), keyword) :: t
    def new(name, opts) when (is_atom(name) or is_binary(name)) and is_list(opts) do
      name = to_string(name)
      content_type = Keyword.get(opts, :content_type, "application/json")

      payload_schema =
        opts
        |> Keyword.get(:payload_schema, %Schema{type: :object})
        |> validate_schema!()

      responses =
        opts
        |> Keyword.get(:responses, %{
          "200" => %Response{description: "Webhook received"}
        })
        |> validate_responses!()

      request_body = %RequestBody{
        description: Keyword.get(opts, :request_description),
        content: %{content_type => %MediaType{schema: payload_schema}},
        required: Keyword.get(opts, :required, true)
      }

      operation = %Operation{
        operationId: Keyword.get(opts, :operation_id, "#{name}Webhook"),
        summary: Keyword.get(opts, :summary, "#{name} webhook"),
        description: Keyword.get(opts, :description),
        requestBody: request_body,
        responses: responses,
        security: Keyword.get(opts, :security)
      }

      %__MODULE__{name: name, operation: operation}
    end

    @spec path_item(t) :: PathItem.t()
    def path_item(%__MODULE__{operation: operation}) do
      %PathItem{post: operation}
    end

    @doc """
    Discovers webhook definitions from AshJsonApi routes in the supplied domains.

    A route marked `webhook?: true` is enough to appear in the OpenAPI 3.1
    `webhooks` object. The request schema is derived from the public action
    arguments, including embedded Ash typed structs.
    """
    @spec from_domains([module]) :: [t]
    def from_domains(domains) when is_list(domains) do
      for domain <- domains,
          resource <- Ash.Domain.Info.resources(domain),
          route <- AshJsonApi.Resource.Info.routes(resource, domains),
          route.webhook? do
        action = Ash.Resource.Info.action(resource, route.action)
        path_arguments = route_path_arguments(route)

        payload =
          Enum.find(action.arguments, fn argument ->
            argument.public? and to_string(argument.name) not in path_arguments
          end)

        name = webhook_name(resource, payload)

        new(name,
          summary: humanize(name),
          description: "Receives #{humanize(name)} events.",
          operation_id: "#{name}Webhook",
          payload_schema: payload_schema(payload, resource),
          responses: %{
            "201" => %Response{description: "Webhook accepted."},
            "400" => %Response{description: "Invalid webhook payload."},
            "403" => %Response{description: "Webhook signature verification failed."}
          }
        )
      end
    end

    defp webhook_name(_resource, %{type: type, constraints: constraints})
         when type in [:struct, Ash.Type.Struct] do
      case Keyword.get(constraints, :instance_of) do
        type when is_atom(type) -> webhook_name_from_type(type)
        _ -> "webhook"
      end
    end

    defp webhook_name(_resource, %{type: type}) when is_atom(type) do
      webhook_name_from_type(type)
    end

    defp webhook_name(resource, _payload) do
      resource
      |> AshJsonApi.Resource.Info.type()
      |> to_string()
      |> String.replace_suffix("_webhook", "")
      |> Macro.camelize()
      |> lower_first()
    end

    defp route_path_arguments(%{route: route}) do
      Regex.scan(~r/:([A-Za-z0-9_]+)/, route, capture: :all_but_first)
      |> List.flatten()
    end

    defp webhook_name_from_type(type) do
      type
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.replace_suffix("_event", "")
      |> Macro.camelize()
      |> lower_first()
    end

    defp lower_first(<<first::utf8, rest::binary>>),
      do: <<String.downcase(<<first>>)::binary, rest::binary>>

    defp lower_first(value), do: value

    defp humanize(value) do
      value
      |> Macro.underscore()
      |> String.replace("_", " ")
      |> String.capitalize()
    end

    defp payload_schema(nil, _resource), do: %Schema{type: :object}

    defp payload_schema(payload, resource) do
      {schema, _acc} =
        AshJsonApi.OpenApi.resource_write_attribute_type(
          payload,
          resource,
          :create,
          AshJsonApi.OpenApi.empty_acc(),
          :json
        )

      schema
    end

    defp validate_schema!(schema) do
      if is_struct(schema, Schema) or is_struct(schema, Reference) or
           (is_map(schema) && (Map.has_key?(schema, :type) || Map.has_key?(schema, "$ref"))) or
           is_atom(schema) do
        schema
      else
        raise ArgumentError,
              "webhook payload_schema must be an OpenApiSpex.Schema, Reference, or schema module"
      end
    end

    defp validate_responses!(responses) when is_map(responses) do
      if Enum.all?(responses, fn {_status, response} ->
           is_struct(response, Response) or is_struct(response, Reference)
         end) do
        responses
      else
        raise ArgumentError,
              "webhook responses must map status codes to OpenApiSpex.Response or Reference structs"
      end
    end

    defp validate_responses!(_responses) do
      raise ArgumentError, "webhook responses must be a map"
    end
  end
end
