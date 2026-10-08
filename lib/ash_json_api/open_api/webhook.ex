if Code.ensure_loaded?(OpenApiSpex) do
  defmodule AshJsonApi.OpenApi.Webhook do
    @moduledoc """
    Typed definition for an OpenAPI webhook discovered from AshHooks.

    Webhooks are represented internally with OpenApiSpex structs and converted
    to a root-level OpenAPI `webhooks` object only when rendered.
    """

    alias OpenApiSpex.{MediaType, Operation, PathItem, RequestBody, Response, Schema}

    @enforce_keys [:name, :operation]
    defstruct [:name, :operation, schemas: %{}]

    @type t :: %__MODULE__{
            name: String.t(),
            operation: Operation.t(),
            schemas: map()
          }

    @spec path_item(t) :: PathItem.t()
    def path_item(%__MODULE__{operation: operation}) do
      %PathItem{post: operation}
    end

    @doc """
    Discovers inbound webhook definitions from AshHooks declarations in the
    supplied domains. AshHooks is optional; without it this returns `[]`.
    """
    @spec from_domains([module]) :: [t]
    def from_domains(domains) when is_list(domains) do
      domains
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.flat_map(&ash_hooks_declarations/1)
    end

    defp ash_hooks_declarations(resource) do
      if Code.ensure_loaded?(AshHooks.Info) and
           function_exported?(AshHooks.Info, :webhooks, 1) do
        resource
        |> then(&apply(AshHooks.Info, :webhooks, [&1]))
        |> Enum.filter(&ash_hooks_inbound?/1)
        |> Enum.map(&ash_hooks_webhook(resource, &1))
      else
        []
      end
    end

    defp ash_hooks_inbound?(%{__struct__: module}) do
      module |> Module.split() |> List.last() == "Inbound"
    end

    defp ash_hooks_inbound?(_), do: false

    defp ash_hooks_webhook(resource, declaration) do
      name = "#{resource_name(resource)}.#{declaration.name}"

      payload_schema = ash_hooks_payload_schema(declaration)

      %__MODULE__{
        name: name,
        operation: %Operation{
          operationId:
            "receive#{Macro.camelize(resource_name(resource))}#{Macro.camelize(to_string(declaration.name))}Webhook",
          summary: humanize(name),
          description: "Receives #{humanize(name)} events.",
          requestBody: %RequestBody{
            content: %{"application/json" => %MediaType{schema: payload_schema}},
            required: true
          },
          responses: %{
            "200" => %Response{description: "Webhook accepted."},
            "400" => %Response{description: "Invalid webhook payload."},
            "403" => %Response{description: "Webhook signature verification failed."}
          }
        }
      }
    end

    defp ash_hooks_payload_schema(%{provider: provider}) when is_atom(provider) do
      if function_exported?(provider, :open_api_schema, 0) do
        provider.open_api_schema()
      else
        %Schema{type: :object}
      end
    end

    defp ash_hooks_payload_schema(_), do: %Schema{type: :object}

    defp resource_name(resource) do
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    defp humanize(value) do
      value
      |> Macro.underscore()
      |> String.replace("_", " ")
      |> String.capitalize()
    end
  end
end
